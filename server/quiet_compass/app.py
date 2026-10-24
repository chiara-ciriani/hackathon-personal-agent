"""ASGI application: REST routes under /v1, /healthz, and the MCP endpoint at /mcp.

Run with `uvicorn quiet_compass.app:create_app --factory`.
"""

from __future__ import annotations

import asyncio
import contextlib
from collections.abc import AsyncIterator

import httpx2 as httpx
from mcp.server.mcpserver import MCPServer
from mcp.server.transport_security import TransportSecuritySettings
from starlette.applications import Starlette
from starlette.responses import Response
from starlette.routing import BaseRoute, Mount, Route
from starlette.types import ASGIApp, Receive, Scope, Send

from .api import build_routes, healthz
from .auth import BearerAuth
from .city import CityNoiseLayer
from .db import Store
from .mcp_server import Service, build_mcp
from .phone_bridge import PhoneBridge, build_phone_routes, register_phone_tools
from .settings import Settings
from .sf_layers import SfLayers
from .shared_access import SHARED_INSTRUCTIONS
from .shared_api import build_shared_routes
from .shared_db import SharedStore
from .shared_layer import SharedLayer
from .shared_tools import register_shared_tools
from .wearable_api import build_wearable_routes
from .wearables import WearableService


class ExactMount:
    """Serve the mounted app at the bare prefix too, so the endpoint is exactly /mcp
    (no redirect to /mcp/, which some clients do not follow for POST)."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] == "http":
            scope = {**scope, "path": "/", "root_path": scope.get("root_path", "") + scope["path"]}
        await self.app(scope, receive, send)


def mcp_path(settings: Settings) -> str:
    """`/mcp`, or `/mcp/<secret>` when QC_MCP_PATH_SECRET is set (development-only fallback for
    clients that cannot send an Authorization header)."""
    return f"/mcp/{settings.mcp_path_secret}" if settings.mcp_path_secret else "/mcp"


def create_app(
    settings: Settings | None = None,
    store: Store | None = None,
    layers: SfLayers | None = None,
    wearable_transport: httpx.AsyncBaseTransport | None = None,
) -> Starlette:
    settings = settings or Settings.from_env()
    store = store or Store(settings.db_path)
    store.migrate()
    city = CityNoiseLayer(settings.socrata_app_token) if settings.city_layer_enabled else None
    if layers is None and settings.city_layer_enabled:
        layers = SfLayers(settings.socrata_app_token)
    wearables = WearableService(store, settings, wearable_transport)
    mcp = build_mcp(Service(store, settings, clock=store.clock), city, layers, wearables)
    shared = SharedLayer(SharedStore(store.path, clock=store.clock), settings, clock=store.clock)
    shared.store.migrate_shared()
    register_shared_tools(mcp, shared)
    shared_mcp = MCPServer("quiet-compass-shared", instructions=SHARED_INSTRUCTIONS)
    register_shared_tools(shared_mcp, shared)
    phone = PhoneBridge(shared, settings.phone_page_url)
    register_phone_tools(mcp, phone)
    register_phone_tools(shared_mcp, phone)
    security = TransportSecuritySettings(
        enable_dns_rebinding_protection=not settings.any_host_allowed,
        allowed_hosts=settings.mcp_hosts,
        allowed_origins=settings.mcp_origins,
    )
    mcp_asgi = mcp.streamable_http_app(
        streamable_http_path="/",
        stateless_http=True,
        json_response=True,
        transport_security=security,
    )
    endpoint: ASGIApp = mcp_asgi
    if not settings.mcp_path_secret:
        endpoint = BearerAuth(mcp_asgi, settings.api_token)
    path = mcp_path(settings)
    shared_asgi = shared_mcp.streamable_http_app(
        streamable_http_path="/", stateless_http=True, json_response=True, transport_security=security,
    )
    shared_endpoint: ASGIApp = (
        BearerAuth(shared_asgi, settings.shared_api_token) if settings.shared_api_token
        else Response("Shared agent access is not configured", status_code=503)
    )

    @contextlib.asynccontextmanager
    async def lifespan(_: Starlette) -> AsyncIterator[None]:
        async with mcp.session_manager.run(), shared_mcp.session_manager.run():
            sync_task = asyncio.create_task(wearables.sync_periodically()) if wearables.configured else None
            try:
                yield
            finally:
                if sync_task:
                    sync_task.cancel()
                    with contextlib.suppress(asyncio.CancelledError):
                        await sync_task

    routes: list[BaseRoute] = [
        Route("/healthz", healthz, methods=["GET"]),
        *build_routes(store, settings.api_token),
        *build_wearable_routes(wearables, settings.api_token),
        *build_shared_routes(shared, settings),
        *build_phone_routes(phone),
        Route("/mcp/shared", ExactMount(shared_endpoint), methods=["GET", "POST", "DELETE"]),
        Route(path, ExactMount(endpoint), methods=["GET", "POST", "DELETE"]),
    ]
    if settings.mcp_path_secret:
        # The bare /mcp must not be reachable without the secret.
        routes.append(Mount("/mcp", app=Response(status_code=404)))
    app = Starlette(routes=routes, lifespan=lifespan)
    app.state.store = store
    app.state.settings = settings
    app.state.wearables = wearables
    return app
