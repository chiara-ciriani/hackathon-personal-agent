"""Sound-field routes: the floor-plane grid built from a session's positioned readings.

`GET /v1/sessions/{session_id}/sound_field` needs the bearer token. The venue page reads the
active session through `GET /v1/venue/sound_field`, which is public only when
QC_PUBLIC_VENUE_FIELD is on (it reveals where the user walked); otherwise it answers 404.
"""

from __future__ import annotations

from collections.abc import Callable

from starlette.concurrency import run_in_threadpool
from starlette.middleware import Middleware
from starlette.middleware.cors import CORSMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response
from starlette.routing import BaseRoute, Route

from .api import ApiError, Handler, guarded, model_response, path_uuid
from .mcp_server import Service
from .settings import Settings


def public(handler: Callable[[Request], Response]) -> Handler:
    """Run a synchronous, unauthenticated handler with uniform error responses."""

    async def endpoint(request: Request) -> Response:
        try:
            return await run_in_threadpool(handler, request)
        except ApiError as exc:
            return JSONResponse({"detail": exc.detail}, status_code=exc.status_code)

    return endpoint


def build_field_routes(service: Service, settings: Settings) -> list[BaseRoute]:
    async def get_session_field(request: Request) -> Response:
        session = service.store.get_session(path_uuid(request, "session_id"))
        if session is None:
            raise ApiError(404, "Unknown session")
        return model_response(service.sound_field(session))

    def get_venue_field(_: Request) -> Response:
        if not settings.public_venue_field:
            raise ApiError(404, "The venue sound field is not public on this server (QC_PUBLIC_VENUE_FIELD)")
        session = service.active_session()
        if session is None:
            raise ApiError(404, "No session yet")
        return model_response(service.sound_field(session))

    cors = Middleware(
        CORSMiddleware, allow_origins=list(settings.map_allowed_origins), allow_methods=["GET"], max_age=600
    )
    return [
        Route("/v1/sessions/{session_id}/sound_field", guarded(settings.api_token, get_session_field), methods=["GET"]),
        Route("/v1/venue/sound_field", public(get_venue_field), methods=["GET", "OPTIONS"], middleware=[cors]),
    ]
