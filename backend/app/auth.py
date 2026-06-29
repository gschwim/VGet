"""Authentication: Google ID-token verification, email allowlist, session JWTs.

Two distinct concerns live here:
  * `/auth/google` exchanges a Google ID token for a short-lived backend session JWT,
    after checking the verified email against the allowlist.
  * `get_current_user` guards every protected route by validating that session JWT.

`VGET_DEV_AUTH_BYPASS=true` short-circuits both so the download pipeline can be tested
before a real Google OAuth client exists.
"""
import time

import jwt
from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token

from .config import Settings, get_settings

_bearer = HTTPBearer(auto_error=False)
DEV_USER = "dev@local"


def verify_google_id_token(token: str, settings: Settings) -> dict:
    """Verify a Google-issued ID token and return its claims."""
    try:
        info = google_id_token.verify_oauth2_token(token, google_requests.Request())
    except Exception as exc:  # invalid signature / expired / malformed
        raise HTTPException(status_code=401, detail="Invalid Google token") from exc

    accepted = settings.accepted_client_ids
    if accepted and info.get("aud") not in accepted:
        raise HTTPException(status_code=401, detail="Token audience mismatch")
    if not info.get("email_verified"):
        raise HTTPException(status_code=401, detail="Email not verified")
    if not info.get("email"):
        raise HTTPException(status_code=401, detail="Token missing email")
    return info


def check_allowlist(email: str, settings: Settings) -> None:
    allowed = settings.allowed_emails
    if allowed and email.lower() not in allowed:
        raise HTTPException(status_code=403, detail="Account not authorized")


def issue_session_token(email: str, settings: Settings) -> str:
    now = int(time.time())
    payload = {"sub": email, "iat": now, "exp": now + settings.jwt_ttl_seconds}
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def get_current_user(
    request: Request,
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    settings: Settings = Depends(get_settings),
) -> str:
    """Resolve the caller's email from a bearer token (or `?token=` for SSE/file URLs)."""
    if settings.dev_auth_bypass:
        return DEV_USER

    token = creds.credentials if creds else request.query_params.get("token")
    if not token:
        raise HTTPException(status_code=401, detail="Missing session token")
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
    except jwt.PyJWTError as exc:
        raise HTTPException(status_code=401, detail="Invalid session token") from exc
    return payload["sub"]
