"""Download job lifecycle: run yt-dlp on a worker thread, stream progress events,
hold the produced file for retrieval, and clean up (including any per-job cookies).
"""
import asyncio
import shutil
import threading
import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path

import yt_dlp

# Sentinel pushed to a job's event queue to close the SSE stream.
_END = {"type": "_end"}


class JobStatus(str, Enum):
    queued = "queued"
    downloading = "downloading"
    processing = "processing"
    finished = "finished"
    error = "error"


@dataclass
class Job:
    id: str
    url: str
    owner: str
    status: JobStatus = JobStatus.queued
    progress: float = 0.0
    title: str | None = None
    filename: str | None = None
    filepath: Path | None = None
    error: str | None = None
    created_at: float = field(default_factory=time.time)

    def public(self) -> dict:
        return {
            "jobId": self.id,
            "status": self.status.value,
            "progress": round(self.progress, 1),
            "title": self.title,
            "filename": self.filename,
            "error": self.error,
        }


class JobManager:
    def __init__(self, work_dir: str, loop: asyncio.AbstractEventLoop,
                 max_filesize_mb: int = 0):
        self._jobs: dict[str, Job] = {}
        self._queues: dict[str, asyncio.Queue] = {}
        self._loop = loop
        self._work_dir = Path(work_dir)
        self._work_dir.mkdir(parents=True, exist_ok=True)
        self._max_filesize_mb = max_filesize_mb

    # -- lookup ------------------------------------------------------------
    def get(self, job_id: str) -> Job | None:
        return self._jobs.get(job_id)

    def queue_for(self, job_id: str) -> asyncio.Queue | None:
        return self._queues.get(job_id)

    # -- creation ----------------------------------------------------------
    def create(self, url: str, owner: str, cookies: str | None = None,
               fmt: str | None = None) -> Job:
        job = Job(id=uuid.uuid4().hex, url=url, owner=owner)
        self._jobs[job.id] = job
        self._queues[job.id] = asyncio.Queue()
        threading.Thread(
            target=self._run, args=(job, cookies, fmt), daemon=True
        ).start()
        return job

    # -- cleanup -----------------------------------------------------------
    def remove(self, job_id: str) -> None:
        job = self._jobs.pop(job_id, None)
        self._queues.pop(job_id, None)
        if job is not None:
            shutil.rmtree(self._work_dir / job.id, ignore_errors=True)

    # -- internals ---------------------------------------------------------
    def _emit(self, job_id: str, event: dict) -> None:
        """Push an event onto a job's async queue from the worker thread."""
        queue = self._queues.get(job_id)
        if queue is not None:
            self._loop.call_soon_threadsafe(queue.put_nowait, event)

    def _run(self, job: Job, cookies: str | None, fmt: str | None) -> None:
        job_dir = self._work_dir / job.id
        job_dir.mkdir(parents=True, exist_ok=True)
        cookie_file = job_dir / "cookies.txt" if cookies else None

        def hook(d: dict) -> None:
            if d["status"] == "downloading":
                job.status = JobStatus.downloading
                total = d.get("total_bytes") or d.get("total_bytes_estimate")
                done = d.get("downloaded_bytes", 0)
                if total:
                    job.progress = min(done / total * 100, 100.0)
                self._emit(job.id, {"type": "progress", "status": job.status.value,
                                    "progress": round(job.progress, 1)})
            elif d["status"] == "finished":
                # download done; merge/remux may still follow
                job.status = JobStatus.processing
                self._emit(job.id, {"type": "progress",
                                    "status": JobStatus.processing.value,
                                    "progress": 100.0})

        options: dict = {
            "outtmpl": str(job_dir / "%(title).80s.%(ext)s"),
            "restrictfilenames": True,
            "progress_hooks": [hook],
            "quiet": True,
            "noprogress": True,
            "noplaylist": True,
        }
        if fmt:
            options["format"] = fmt
        if self._max_filesize_mb:
            options["max_filesize"] = self._max_filesize_mb * 1024 * 1024
        if cookie_file is not None:
            cookie_file.write_text(cookies)
            options["cookiefile"] = str(cookie_file)

        try:
            with yt_dlp.YoutubeDL(options) as ydl:
                info = ydl.extract_info(job.url, download=True)
            produced = self._resolve_output(info, job_dir)
            if produced is None:
                raise RuntimeError("download produced no file")

            job.title = info.get("title")
            job.filepath = produced
            job.filename = produced.name
            job.progress = 100.0
            job.status = JobStatus.finished
            self._emit(job.id, {"type": "done", "status": "finished",
                                "filename": job.filename, "title": job.title})
        except Exception as exc:
            job.status = JobStatus.error
            job.error = str(exc)
            self._emit(job.id, {"type": "error", "status": "error",
                                "error": job.error})
        finally:
            if cookie_file is not None:
                cookie_file.unlink(missing_ok=True)  # never persist credentials
            self._emit(job.id, _END)

    @staticmethod
    def _resolve_output(info: dict, job_dir: Path) -> Path | None:
        """Find the final media file yt-dlp produced (post-merge/remux)."""
        # Most reliable: yt-dlp records the final path here after postprocessing.
        for dl in info.get("requested_downloads") or []:
            fp = dl.get("filepath")
            if fp and Path(fp).exists():
                return Path(fp)
        # Fallback: largest non-cookie file left in the job dir.
        candidates = [
            p for p in job_dir.iterdir()
            if p.is_file() and p.name != "cookies.txt"
        ]
        if candidates:
            return max(candidates, key=lambda p: p.stat().st_size)
        return None
