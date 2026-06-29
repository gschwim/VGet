# VGet

Paste a link, get the media. A cross-platform (macOS / web / mobile) media downloader
built with **Flutter** clients talking to a **yt-dlp** backend.

> Rewrite of the original Kivy desktop app. The old app and its history are preserved on
> the `dev` branch.

## Architecture

```
Flutter client (macOS / web / iOS / Android)
  • URL input + progress + result
  • Google Sign-In  -> backend session token
  • Cookie capture (per-platform) for authenticated media
        |  HTTPS (REST + SSE)
        v   Internet -> Nginx (TLS, rate-limit) -> Docker
Backend (FastAPI + yt-dlp + ffmpeg, in Docker)
  • verify Google ID token + email allowlist
  • run download jobs, stream progress, serve the file
  • cookies used per-job then deleted; never persisted
```

See the approved design notes in
`~/.claude/plans/assess-the-code-here-sleepy-thimble.md`.

## Repo layout

| Path        | What |
|-------------|------|
| `backend/`  | FastAPI service wrapping yt-dlp; Dockerfile + docker-compose |
| `app/`      | Flutter client (added in Phase 1 client step) |
| `flake.nix` | Nix dev shells: `backend` (Python) and `flutter` |

## Quick start (backend)

```bash
cd backend
cp .env.example .env            # set VGET_DEV_AUTH_BYPASS=true for local testing
docker compose up --build       # serves on http://localhost:8000

# smoke test (dev bypass on):
curl -s -X POST localhost:8000/jobs \
  -H 'content-type: application/json' \
  -d '{"url":"https://www.youtube.com/watch?v=aqz-KE-bpKQ"}'
# -> {"jobId":"..."}
curl -N localhost:8000/jobs/<jobId>/events     # SSE progress
curl -OJ localhost:8000/jobs/<jobId>/file      # download the result
```

## Status

- **Phase 1 (in progress):** public media, macOS + web. Backend job pipeline + auth gate
  (Google login stubbed behind `VGET_DEV_AUTH_BYPASS` until a Google OAuth client exists).
- **Phase 2:** authenticated media (Instagram / Facebook / X) via per-platform cookie
  capture forwarded per-job.
- **Phase 3:** mobile polish + web browser-extension for authenticated web.
