"""REST routes for the shared sound layer (contracts/README.md, "Shared sound layer").

Contributions and reads accept the shared credential or the owner's credential.
Shared reads also require an unexpired contribution receipt. Area editing stays private.
"""

from __future__ import annotations

import re
from collections.abc import Callable

from starlette.concurrency import run_in_threadpool
from starlette.middleware import Middleware
from starlette.middleware.cors import CORSMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response
from starlette.routing import BaseRoute, Route

from .api import ApiError, Handler, guarded, model_response, parse_body
from .auth import token_matches, unauthorized
from .settings import Settings
from .shared_access import ContributionRequired, require_access
from .shared_contracts import AREA_ID_PATTERN, AreaUpsert, ContributionUpload
from .shared_layer import SharedLayer

QUERY_LIMITS: dict[str, tuple[float, float]] = {
    "lat": (-90, 90),
    "lon": (-180, 180),
    "radius_m": (50, 5000),
    "since_minutes": (5, 1440),
}


def _query_number[NumberT: (int, float)](
    request: Request, name: str, kind: Callable[[str], NumberT], default: NumberT | None = None
) -> NumberT:
    raw = request.query_params.get(name)
    if raw is None:
        if default is None:
            raise ApiError(422, f"query parameter {name} is required")
        return default
    try:
        value = kind(raw)
    except ValueError as exc:
        raise ApiError(422, f"{name} must be a number") from exc
    low, high = QUERY_LIMITS[name]
    if not low <= value <= high:
        raise ApiError(422, f"{name} must be between {low:g} and {high:g}")
    return value


def build_shared_routes(layer: SharedLayer, settings: Settings) -> list[BaseRoute]:
    def shared_guarded(handler: Handler) -> Handler:
        async def endpoint(request: Request) -> Response:
            for token in (settings.shared_api_token, settings.api_token):
                if token and token_matches(request.headers.get("authorization"), token):
                    response = await guarded(token, handler)(request)
                    response.headers["Cache-Control"] = "no-store"
                    return response
            return unauthorized()
        return endpoint

    async def post_contribution(request: Request) -> Response:
        body = await parse_body(request, ContributionUpload)
        return model_response(await run_in_threadpool(layer.submit_shared, body.contribution, body.share_consent))

    async def put_area(request: Request) -> Response:
        area_id = request.path_params["area_id"]
        if not re.fullmatch(AREA_ID_PATTERN, area_id):
            raise ApiError(422, "area_id may use letters, digits and : . _ , - (max 120 characters)")
        body = await parse_body(request, AreaUpsert)
        area = await run_in_threadpool(layer.upsert_area, area_id, body.name, body.lat, body.lon, body.kind)
        return model_response(area)

    async def get_aggregates(request: Request) -> Response:
        try:
            await run_in_threadpool(require_access, layer.store, request.headers.get("x-qc-access-receipt"))
        except ContributionRequired as exc:
            return JSONResponse({"error": "contribution_required", "detail": str(exc)}, status_code=428)
        result = await run_in_threadpool(
            layer.sound_map,
            _query_number(request, "lat", float),
            _query_number(request, "lon", float),
            _query_number(request, "radius_m", int, 500),
            _query_number(request, "since_minutes", int, 60),
        )
        return model_response(result)

    async def exchange_status(_: Request) -> Response:
        return JSONResponse({
            "protocol": "contribution-window-v1", "access_window_seconds": 900,
            "shared_endpoint_enabled": bool(settings.shared_api_token), "mcp_path": "/mcp/shared",
            "tools": ["submit_observation", "query_sound_map", "find_suitable_places"],
        }, headers={"Cache-Control": "no-store"})

    cors = Middleware(
        CORSMiddleware, allow_origins=list(settings.map_allowed_origins), allow_methods=["GET"],
        allow_headers=["Authorization", "X-QC-Access-Receipt"], max_age=600,
    )
    token = settings.api_token
    return [
        Route("/v1/exchange/status", exchange_status, methods=["GET"]),
        Route("/v1/contributions", shared_guarded(post_contribution), methods=["POST"]),
        Route("/v1/areas/{area_id}", guarded(token, put_area), methods=["PUT"]),
        Route("/v1/map/aggregates", shared_guarded(get_aggregates), methods=["GET", "OPTIONS"], middleware=[cors]),
    ]
