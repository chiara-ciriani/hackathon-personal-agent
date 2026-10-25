"""Bearer-token checks for the REST routes and the MCP endpoint (separate owner and shared credentials)."""

from __future__ import annotations

import hmac

from starlette.requests import HTTPConnection
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Receive, Scope, Send

CHALLENGE = {"WWW-Authenticate": 'Bearer realm="quiet-compass"'}


def token_matches(header: str | None, token: str) -> bool:
    """Constant-time check of an `Authorization: Bearer <token>` header."""
    scheme, _, value = (header or "").partition(" ")
    if scheme.lower() != "bearer" or not value:
        return False
    return hmac.compare_digest(value.strip().encode(), token.encode())


def unauthorized() -> JSONResponse:
    return JSONResponse(
        {"detail": "Missing or invalid bearer token"}, status_code=401, headers=CHALLENGE
    )


class BearerAuth:
    """ASGI middleware that rejects HTTP requests without the right bearer token."""

    def __init__(self, app: ASGIApp, token: str) -> None:
        self.app = app
        self.token = token

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] == "http" and not token_matches(
            HTTPConnection(scope).headers.get("authorization"), self.token
        ):
            await unauthorized()(scope, receive, send)
            return
        await self.app(scope, receive, send)
