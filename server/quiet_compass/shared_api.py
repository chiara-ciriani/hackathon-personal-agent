"""REST routes for the shared sound layer (contracts/README.md, "Shared sound layer").

Writes (`POST /v1/contributions`, `PUT /v1/areas/{area_id}`) need the bearer token.
`GET /v1/map/aggregates` is a public read with CORS for the web map: it returns only
released aggregates, which are the same data the map displays to anyone.
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
from .settings import Settings
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


def public(handler: Callable[[Request], Response]) -> Handler:
    """Run a synchronous, unauthenticated handler with uniform error responses."""

    async def endpoint(request: Request) -> Response:
        try:
            return await run_in_threadpool(handler, request)
        except ApiError as exc:
            return JSONResponse({"detail": exc.detail}, status_code=exc.status_code)

    return endpoint


def build_shared_routes(layer: SharedLayer, settings: Settings) -> list[BaseRoute]:
    async def post_contribution(request: Request) -> Response:
        body = await parse_body(request, ContributionUpload)
        return model_response(await run_in_threadpool(layer.submit, body.contribution))

    async def put_area(request: Request) -> Response:
        area_id = request.path_params["area_id"]
        if not re.fullmatch(AREA_ID_PATTERN, area_id):
            raise ApiError(422, "area_id may use letters, digits and : . _ , - (max 120 characters)")
        body = await parse_body(request, AreaUpsert)
        area = await run_in_threadpool(layer.upsert_area, area_id, body.name, body.lat, body.lon, body.kind)
        return model_response(area)

    def get_aggregates(request: Request) -> Response:
        result = layer.sound_map(
            _query_number(request, "lat", float),
            _query_number(request, "lon", float),
            _query_number(request, "radius_m", int, 500),
            _query_number(request, "since_minutes", int, 60),
        )
        return model_response(result)

    cors = Middleware(
        CORSMiddleware, allow_origins=list(settings.map_allowed_origins), allow_methods=["GET"], max_age=600
    )
    token = settings.api_token
    return [
        Route("/v1/contributions", guarded(token, post_contribution), methods=["POST"]),
        Route("/v1/areas/{area_id}", guarded(token, put_area), methods=["PUT"]),
        Route("/v1/map/aggregates", public(get_aggregates), methods=["GET", "OPTIONS"], middleware=[cors]),
    ]
