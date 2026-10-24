"""Runtime configuration, read from environment variables."""

from __future__ import annotations

import os
import uuid
from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urlsplit

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


def _number[NumberT: (int, float)](value: str | None, default: NumberT, kind: type[NumberT]) -> NumberT:
    value = (value or "").strip()
    if not value:
        return default
    try:
        return kind(value)
    except ValueError as exc:
        raise SettingsError(f"expected a number, got {value!r}") from exc


@dataclass(frozen=True)
class Settings:
    """Service settings. Build with `Settings.from_env()` or directly in tests."""

    api_token: str = field(repr=False)
    db_path: Path = Path("./data/quiet_compass.db")
    allowed_hosts: tuple[str, ...] = ()
    active_session_id: str | None = None
    socrata_app_token: str | None = None
    city_layer_enabled: bool = False
    mcp_path_secret: str | None = None
    phone_page_url: str = "https://quiet-compass-navy.vercel.app/measure"
    public_url: str | None = None
    encryption_key: str | None = field(default=None, repr=False)
    oura_client_id: str | None = None
    oura_client_secret: str | None = field(default=None, repr=False)
    release_min_contributions: int = 2
    contribution_retention_hours: float = 24.0
    map_allowed_origins: tuple[str, ...] = ("*",)
    shared_api_token: str | None = field(default=None, repr=False)

    def __post_init__(self) -> None:
        if not self.api_token:
            raise SettingsError("QC_API_TOKEN must be set to a long random string")
        if self.shared_api_token and (len(self.shared_api_token) < 16 or self.shared_api_token == self.api_token):
            raise SettingsError("QC_SHARED_API_TOKEN must be at least 16 characters and different from QC_API_TOKEN")
        if self.public_url:
            url = urlsplit(self.public_url)
            local = url.hostname in {"localhost", "127.0.0.1", "::1"}
            if (url.scheme != "https" and not (local and url.scheme == "http")) or (
                not url.netloc or url.username or url.password or url.query or url.fragment or url.path not in {"", "/"}
            ):
                raise SettingsError("QC_PUBLIC_URL must be an HTTPS origin (HTTP localhost is allowed for development)")
        page = urlsplit(self.phone_page_url)
        local_page = page.scheme == "http" and page.hostname in {"localhost", "127.0.0.1", "::1"}
        if ((page.scheme != "https" and not local_page)
                or not page.netloc or page.username or page.password or page.query or page.fragment):
            raise SettingsError("QC_PHONE_PAGE_URL must be an HTTPS page URL (localhost HTTP allowed)")
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
        if self.release_min_contributions < 1:
            raise SettingsError("QC_RELEASE_MIN_CONTRIBUTIONS must be at least 1")
        if self.contribution_retention_hours < 0.5:
            raise SettingsError("QC_CONTRIBUTION_RETENTION_HOURS must be at least 0.5 to preserve the 15-minute grant")

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> Settings:
        env = os.environ if env is None else env
        hosts = _csv(env.get("QC_ALLOWED_HOSTS"))
        fly_app = _optional(env.get("FLY_APP_NAME"))
        if fly_app:
            hosts = (*hosts, f"{fly_app}.fly.dev")
        render_host = _optional(env.get("RENDER_EXTERNAL_HOSTNAME"))
        if render_host:
            hosts = (*hosts, render_host)
        return cls(
            api_token=(env.get("QC_API_TOKEN") or "").strip(),
            phone_page_url=env.get("QC_PHONE_PAGE_URL") or "https://quiet-compass-navy.vercel.app/measure",
            db_path=Path(env.get("QC_DB_PATH") or "./data/quiet_compass.db"),
            allowed_hosts=hosts,
            active_session_id=_optional(env.get("QC_ACTIVE_SESSION_ID")),
            socrata_app_token=_optional(env.get("QC_SOCRATA_APP_TOKEN")),
            city_layer_enabled=_flag(env.get("QC_CITY_LAYER_ENABLED")),
            mcp_path_secret=_optional(env.get("QC_MCP_PATH_SECRET")),
            public_url=_optional(env.get("QC_PUBLIC_URL")) or _optional(env.get("RENDER_EXTERNAL_URL")),
            encryption_key=_optional(env.get("QC_ENCRYPTION_KEY")),
            oura_client_id=_optional(env.get("QC_OURA_CLIENT_ID")),
            oura_client_secret=_optional(env.get("QC_OURA_CLIENT_SECRET")),
            release_min_contributions=_number(env.get("QC_RELEASE_MIN_CONTRIBUTIONS"), 2, int),
            contribution_retention_hours=_number(env.get("QC_CONTRIBUTION_RETENTION_HOURS"), 24.0, float),
            map_allowed_origins=_csv(env.get("QC_MAP_ALLOWED_ORIGINS")) or ("*",),
            shared_api_token=_optional(env.get("QC_SHARED_API_TOKEN")),
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
