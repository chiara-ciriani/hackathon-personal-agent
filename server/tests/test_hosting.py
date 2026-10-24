"""Exercise the hosted MCP boundary with Render's assigned hostname."""

from pathlib import Path

from conftest import TOKEN
from starlette.testclient import TestClient
from test_mcp import HEADERS, rpc

from quiet_compass.app import create_app
from quiet_compass.settings import Settings


def test_render_hostname_preserves_explicit_hosts_and_auth(tmp_path: Path) -> None:
    settings = Settings.from_env({
        "QC_API_TOKEN": TOKEN,
        "QC_DB_PATH": str(tmp_path / "render.db"),
        "QC_ALLOWED_HOSTS": "api.example.com",
        "RENDER_EXTERNAL_HOSTNAME": "quiet-sample.onrender.com",
    })
    assert settings.mcp_origins[-2:] == [
        "https://api.example.com", "https://quiet-sample.onrender.com",
    ]
    assert not settings.any_host_allowed
    with TestClient(create_app(settings)) as client:
        for host in ("quiet-sample.onrender.com", "api.example.com"):
            headers = {**HEADERS, "Host": host}
            assert rpc(client, "tools/list", headers=headers).status_code == 200
            headers.pop("Authorization")
            assert rpc(client, "tools/list", headers=headers).status_code == 401
        assert rpc(client, "tools/list", headers={**HEADERS, "Host": "unrelated.example"}).status_code == 421


def test_render_hostname_is_optional_and_fly_is_preserved() -> None:
    settings = Settings.from_env({
        "QC_API_TOKEN": TOKEN,
        "FLY_APP_NAME": "existing-app",
        "RENDER_EXTERNAL_HOSTNAME": " ",
    })
    assert settings.allowed_hosts == ("existing-app.fly.dev",)
