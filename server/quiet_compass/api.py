"""REST routes for the phone (contracts/README.md, "HTTP API").

Plain Starlette with Pydantic validation. Error bodies are `{"detail": ...}`:
401 bad token, 409 records for a session that was never PUT, 404 unknown guidance,
422 a body that does not match the contract.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable, Sequence
from typing import Any
from uuid import UUID

from pydantic import BaseModel, ValidationError
from starlette.concurrency import run_in_threadpool
from starlette.requests import Request
from starlette.responses import JSONResponse, Response
from starlette.routing import BaseRoute, Route

from .auth import token_matches, unauthorized
from .contracts import (
    CrumbBatch,
    FeedbackBatch,
    GuidanceStatusUpdate,
    IngestResult,
    ObservationBatch,
    PlaceBatch,
    SessionUpsert,
)
from .db import Store, UnknownSessionError

Handler = Callable[[Request], Awaitable[Response]]


class ApiError(Exception):
    def __init__(self, status_code: int, detail: Any) -> None:
        self.status_code = status_code
        self.detail = detail


def model_response(model: BaseModel, status_code: int = 200) -> Response:
    return Response(
        model.model_dump_json(), status_code=status_code, media_type="application/json"
    )


async def parse_body[ModelT: BaseModel](request: Request, model: type[ModelT]) -> ModelT:
    raw = await request.body()
    try:
        return model.model_validate_json(raw)
    except ValidationError as exc:
        errors = exc.errors(include_url=False, include_context=False, include_input=False)
        raise ApiError(422, errors) from exc


def path_uuid(request: Request, name: str) -> UUID:
    try:
        return UUID(request.path_params[name])
    except ValueError as exc:
        raise ApiError(422, f"{name} must be a UUID") from exc


def guarded(token: str, handler: Handler) -> Handler:
    """Wrap a handler with bearer auth and uniform error responses."""

    async def endpoint(request: Request) -> Response:
        if not token_matches(request.headers.get("authorization"), token):
            return unauthorized()
        try:
            return await handler(request)
        except ApiError as exc:
            return JSONResponse({"detail": exc.detail}, status_code=exc.status_code)
        except UnknownSessionError as exc:
            detail = f"{exc}. Send PUT /v1/sessions/{{session_id}} first."
            return JSONResponse({"detail": detail}, status_code=409)

    return endpoint


def build_routes(store: Store, token: str) -> list[BaseRoute]:
    async def put_session(request: Request) -> Response:
        session_id = path_uuid(request, "session_id")
        body = await parse_body(request, SessionUpsert)
        if body.session.id != session_id:
            raise ApiError(422, "session.id must match the session_id in the path")
        return model_response(await run_in_threadpool(store.upsert_session, body.session))

    def ingest(model: type[BaseModel], field: str, write: Callable[[Sequence[Any]], IngestResult]) -> Handler:
        async def handler(request: Request) -> Response:
            body = await parse_body(request, model)
            return model_response(await run_in_threadpool(write, getattr(body, field)))

        return handler

    async def get_guidance(request: Request) -> Response:
        session_id = path_uuid(request, "session_id")
        guidance = await run_in_threadpool(store.get_guidance, session_id)
        if guidance is None or guidance.status != "active":
            return Response(status_code=204)
        return model_response(guidance)

    async def post_guidance_status(request: Request) -> Response:
        session_id = path_uuid(request, "session_id")
        body = await parse_body(request, GuidanceStatusUpdate)
        guidance = await run_in_threadpool(store.set_guidance_status, session_id, body.status)
        if guidance is None:
            raise ApiError(404, "No guidance exists for this session")
        return model_response(guidance)

    def route(path: str, handler: Handler, method: str) -> Route:
        return Route(path, guarded(token, handler), methods=[method])

    return [
        route("/v1/sessions/{session_id}", put_session, "PUT"),
        route("/v1/observations", ingest(ObservationBatch, "observations", store.add_observations), "POST"),
        route("/v1/crumbs", ingest(CrumbBatch, "crumbs", store.add_crumbs), "POST"),
        route("/v1/places", ingest(PlaceBatch, "places", store.upsert_places), "POST"),
        route("/v1/feedback", ingest(FeedbackBatch, "feedback", store.add_feedback), "POST"),
        route("/v1/sessions/{session_id}/guidance", get_guidance, "GET"),
        route("/v1/sessions/{session_id}/guidance/status", post_guidance_status, "POST"),
    ]


async def healthz(_: Request) -> Response:
    return JSONResponse({"ok": True})
