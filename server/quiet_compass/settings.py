"""Runtime configuration, read from environment variables."""

from __future__ import annotations

import os
import uuid
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path

LOCAL_HOSTS = ("localhost:*", "127.0.0.1:*", "[::1]:*", "localhost", "127.0.0.1")
LOCAL_ORIGINS = ("http://localhost:*", "http://127.0.0.1:*", "http://[::1]:*")


class SettingsError(ValueError):
    """Raised when the environment does not describe a runnable service."""


def _flag(value: str | None) -> bool:
    return (value or "").strip().lower() in {"1", "true", "yes", "on"}


def _csv(value: str | None) -> tuple[str, ...]:
    return tuple(part.strip() for part in (value or "").split(",") if part.strip())


def _optional(value: str | None) -> str | None:
    value = (value or "").strip()
    return value or None


@dataclass(frozen=True)
class Settings:
    """Service settings. Build with `Settings.from_env()` or directly in tests."""

    api_token: str
    db_path: Path = Path("./data/quiet_compass.db")
    allowed_hosts: tuple[str, ...] = ()
    active_session_id: str | None = None
    socrata_app_token: str | None = None
    city_layer_enabled: bool = False
    mcp_path_secret: str | None = None

    def __post_init__(self) -> None:
        if not self.api_token:
            raise SettingsError("QC_API_TOKEN must be set to a long random string")
        if self.active_session_id is not None:
            try:
                normalized = str(uuid.UUID(self.active_session_id))
            except ValueError as exc:
                raise SettingsError("QC_ACTIVE_SESSION_ID must be a UUID") from exc
            object.__setattr__(self, "active_session_id", normalized)
        if self.mcp_path_secret is not None and (
            len(self.mcp_path_secret) < 16 or not self.mcp_path_secret.isalnum()
        ):
            raise SettingsError("QC_MCP_PATH_SECRET must be at least 16 letters or digits")

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> Settings:
        env = os.environ if env is None else env
        hosts = _csv(env.get("QC_ALLOWED_HOSTS"))
        fly_app = _optional(env.get("FLY_APP_NAME"))
        if fly_app:
            hosts = (*hosts, f"{fly_app}.fly.dev")
        return cls(
            api_token=(env.get("QC_API_TOKEN") or "").strip(),
            db_path=Path(env.get("QC_DB_PATH") or "./data/quiet_compass.db"),
            allowed_hosts=hosts,
            active_session_id=_optional(env.get("QC_ACTIVE_SESSION_ID")),
            socrata_app_token=_optional(env.get("QC_SOCRATA_APP_TOKEN")),
            city_layer_enabled=_flag(env.get("QC_CITY_LAYER_ENABLED")),
            mcp_path_secret=_optional(env.get("QC_MCP_PATH_SECRET")),
        )

    @property
    def any_host_allowed(self) -> bool:
        return "*" in self.allowed_hosts

    @property
    def mcp_hosts(self) -> list[str]:
        """Host header values the MCP transport accepts (DNS rebinding protection)."""
        return [*LOCAL_HOSTS, *(h for h in self.allowed_hosts if h != "*")]

    @property
    def mcp_origins(self) -> list[str]:
        extra = [f"https://{h}" for h in self.allowed_hosts if h != "*" and ":" not in h]
        return [*LOCAL_ORIGINS, *extra]
