"""Runtime configuration, loaded from environment (VGET_* / backend/.env)."""
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", env_prefix="VGET_", extra="ignore"
    )

    # --- Auth ---
    dev_auth_bypass: bool = False
    google_client_ids: str = ""
    allowlist: str = ""
    jwt_secret: str = "dev-insecure-change-me"
    jwt_ttl_seconds: int = 3600

    # --- CORS ---
    cors_origins: str = "*"

    # --- Downloads ---
    work_dir: str = "/tmp/vget"
    job_ttl_seconds: int = 3600
    max_filesize_mb: int = 2048

    @property
    def allowed_emails(self) -> set[str]:
        return {e.strip().lower() for e in self.allowlist.split(",") if e.strip()}

    @property
    def accepted_client_ids(self) -> list[str]:
        return [c.strip() for c in self.google_client_ids.split(",") if c.strip()]

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()] or ["*"]


@lru_cache
def get_settings() -> Settings:
    return Settings()
