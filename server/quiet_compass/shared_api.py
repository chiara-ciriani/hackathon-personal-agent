"""REST routes for the shared sound layer (contracts/README.md, "Shared sound layer").

Contributions and reads accept the shared credential or the owner's credential.
Agent reads require an unexpired contribution receipt. The public map shows only released
device aggregates. Area editing stays private.
"""

from __future__ import annotations

import re
import time
from collections import deque
from collections.abc import Callable

from starlette.concurrency import run_in_threadpool
from starlette.middleware import Middleware
from starlette.middleware.cors import CORSMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response
from starlette.routing import BaseRoute, Route

from .api import ApiError, Handler, guarded, model_response, parse_body
from .auth import token_matches, unauthorized
from .mcp_oauth import REQUEST_SECONDS
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

    community_requests: dict[str, deque[float]] = {}

    async def post_community_contribution(request: Request) -> Response:
        # Public, opt-in ingestion. Neither account credentials nor private phone sessions are exposed.
        now = time.monotonic()
        for key in list(community_requests):
            if not community_requests[key] or community_requests[key][-1] < now - 3600:
                del community_requests[key]
        peer = request.client.host if request.client else "unknown"
        recent = community_requests.setdefault(peer, deque())
        while recent and recent[0] < now - 3600:
            recent.popleft()
        if len(recent) >= 30:
            return JSONResponse({"error": "Please try sharing again later."}, status_code=429)
        recent.append(now)
        if len(await request.body()) > 8192:
            return JSONResponse({"error": "Summary exceeds the size limit."}, status_code=413)
        try:
            body = await parse_body(request, ContributionUpload)
        except ApiError:
            return JSONResponse({"error": "Invalid sound summary."}, status_code=422)
        c = body.contribution
        if (not body.share_consent or c.source != "device" or c.quality.clipping_detected
                or c.lat is None or c.lon is None or not 37.6 <= c.lat <= 37.85
                or not -122.55 <= c.lon <= -122.3
                or not (9 <= c.duration_seconds <= 11 or 25 <= c.duration_seconds <= 35)
                or not c.quality.capture_profile.startswith("qc-community-v1:")):
            return JSONResponse({"error": "Share a consented 10-second, unclipped measurement in San Francisco."},
                                status_code=422, headers={"Cache-Control": "no-store"})
        result = await run_in_threadpool(layer.submit_shared, c, True)
        response = model_response(result)
        response.headers["Cache-Control"] = "no-store"
        return response

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

    async def get_map_view(request: Request) -> Response:
        # A receipt is a short-lived read capability, never an owner or shared API key.
        # Fixed SF bounds and window; the full MCP/REST query APIs retain their own auth.
        header = request.headers.get("authorization", "")
        receipt = header[7:] if header.startswith("Bearer ") else None
        try:
            await run_in_threadpool(require_access, layer.store, receipt)
        except ContributionRequired as exc:
            return JSONResponse({"error": "contribution_required", "detail": str(exc)}, status_code=428,
                                headers={"Cache-Control": "no-store"})
        return await get_public_map(request)

    async def get_public_map(_: Request) -> Response:
        # Consented, released aggregates only. Never private room maps or raw audio.
        result = await run_in_threadpool(layer.sound_map, 37.77, -122.43, 5000, 1440)
        result.aggregates = [a for a in result.aggregates if a.source == "device" and not a.has_synthetic]
        response = model_response(result)
        response.headers["Cache-Control"] = "no-store"
        return response

    async def exchange_status(_: Request) -> Response:
        return JSONResponse({
            "protocol": "contribution-window-v1", "access_window_seconds": 900,
            "shared_endpoint_enabled": bool(settings.shared_api_token), "mcp_path": "/mcp/shared",
            "dot_mcp_enabled": bool(settings.shared_api_token and settings.public_url),
            "dot_mcp_path": "/mcp/dot",
            "dot_oauth_request_lifetime_seconds": (
                REQUEST_SECONDS if settings.shared_api_token and settings.public_url else 0
            ),
            "tools": ["connect_phone", "request_phone_measurement", "phone_measurement_status",
                      "send_phone_recommendation", "submit_observation", "query_sound_map", "find_suitable_places"],
            "phone_measurement": {"protocol": "phone-bridge-v1", "session_seconds": 900, "duration_seconds": 10,
                                  "native_protocol": "phone-walk-v1"},
        }, headers={"Cache-Control": "no-store"})

    cors = Middleware(
        CORSMiddleware, allow_origins=list(settings.map_allowed_origins), allow_methods=["GET"],
        allow_headers=["Authorization", "X-QC-Access-Receipt"], max_age=600,
    )
    token = settings.api_token
    return [
        Route("/v1/community/contributions", post_community_contribution, methods=["POST"]),
        Route("/v1/map/view", get_map_view, methods=["GET"]),
        Route("/v1/map/public", get_public_map, methods=["GET"]),
        Route("/v1/exchange/status", exchange_status, methods=["GET"]),
        Route("/v1/contributions", shared_guarded(post_contribution), methods=["POST"]),
        Route("/v1/areas/{area_id}", guarded(token, put_area), methods=["PUT"]),
        Route("/v1/map/aggregates", shared_guarded(get_aggregates), methods=["GET", "OPTIONS"], middleware=[cors]),
    ]
