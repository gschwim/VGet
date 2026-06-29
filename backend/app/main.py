"""VGet backend API.

Endpoints:
  POST /auth/google        exchange a Google ID token for a session JWT (allowlist-gated)
  POST /jobs               create a download job  -> {jobId}
  GET  /jobs/{id}          poll job status
  GET  /jobs/{id}/events   Server-Sent Events stream of progress
  GET  /jobs/{id}/file     download the produced media file
  GET  /healthz            liveness
"""
import asyncio
import json
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, StreamingResponse
from pydantic import BaseModel

from .auth import (
    check_allowlist,
    get_current_user,
    issue_session_token,
    verify_google_id_token,
)
from .config import get_settings
from .jobs import JobManager


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    app.state.manager = JobManager(
        settings.work_dir,
        asyncio.get_running_loop(),
        max_filesize_mb=settings.max_filesize_mb,
    )
    yield


app = FastAPI(title="VGet backend", lifespan=lifespan)

_settings = get_settings()
app.add_middleware(
    CORSMiddleware,
    allow_origins=_settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def manager(request: Request) -> JobManager:
    return request.app.state.manager


# --- models ----------------------------------------------------------------
class GoogleLogin(BaseModel):
    id_token: str


class JobCreate(BaseModel):
    url: str
    cookies: str | None = None
    format: str | None = None


# --- routes ----------------------------------------------------------------
@app.get("/healthz")
def healthz():
    return {"ok": True}


@app.post("/auth/google")
def auth_google(body: GoogleLogin, settings=Depends(get_settings)):
    info = verify_google_id_token(body.id_token, settings)
    email = info["email"]
    check_allowlist(email, settings)
    return {"token": issue_session_token(email, settings), "email": email}


@app.post("/jobs")
def create_job(body: JobCreate, request: Request, user: str = Depends(get_current_user)):
    if not body.url.strip():
        raise HTTPException(status_code=400, detail="url is required")
    job = manager(request).create(
        body.url.strip(), user, cookies=body.cookies, fmt=body.format
    )
    return {"jobId": job.id}


def _owned_job(request: Request, job_id: str, user: str):
    job = manager(request).get(job_id)
    if job is None or job.owner != user:
        raise HTTPException(status_code=404, detail="job not found")
    return job


@app.get("/jobs/{job_id}")
def get_job(job_id: str, request: Request, user: str = Depends(get_current_user)):
    return _owned_job(request, job_id, user).public()


@app.get("/jobs/{job_id}/events")
async def job_events(job_id: str, request: Request, user: str = Depends(get_current_user)):
    job = _owned_job(request, job_id, user)
    queue = manager(request).queue_for(job_id)
    if queue is None:
        raise HTTPException(status_code=404, detail="job not found")

    async def stream():
        # Emit current state immediately so late subscribers are in sync.
        yield f"data: {json.dumps(job.public())}\n\n"
        while True:
            event = await queue.get()
            if event.get("type") == "_end":
                break
            yield f"data: {json.dumps(event)}\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")


@app.get("/jobs/{job_id}/file")
def job_file(job_id: str, request: Request, user: str = Depends(get_current_user)):
    job = _owned_job(request, job_id, user)
    if job.filepath is None or not job.filepath.exists():
        raise HTTPException(status_code=409, detail=f"file not ready ({job.status.value})")
    return FileResponse(
        job.filepath, filename=job.filename, media_type="application/octet-stream"
    )
