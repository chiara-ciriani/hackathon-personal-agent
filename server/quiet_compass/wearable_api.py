"""Authenticated private summaries and a browser-bound, one-use Oura OAuth handshake."""

from html import escape

from starlette.requests import Request
from starlette.responses import HTMLResponse, JSONResponse, RedirectResponse, Response
from starlette.routing import Route

from .api import ApiError, guarded
from .wearables import HealthSnapshot, WearableError, WearableService

HEADERS = {
    "Cache-Control": "no-store",
    "Referrer-Policy": "no-referrer",
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
}
COOKIE = "qc_oura_browser"
CALLBACK = "/oauth/oura/callback"


def build_wearable_routes(service: WearableService, token: str) -> list[Route]:
    async def link(_: Request) -> Response:
        return JSONResponse({"connection_url": service.connection_link()})

    async def context(_: Request) -> Response:
        return JSONResponse(service.context())

    async def sync(_: Request) -> Response:
        return JSONResponse(await service.sync_oura())

    async def upload(request: Request) -> Response:
        raw = bytearray()
        async for chunk in request.stream():
            raw.extend(chunk)
            if len(raw) > 65536:
                raise ApiError(413, "Health summary exceeds 64 KiB")
        from pydantic import ValidationError

        try:
            snapshot = HealthSnapshot.model_validate_json(bytes(raw))
        except ValidationError as exc:
            raise ApiError(422, exc.errors(include_input=False, include_context=False, include_url=False)) from exc
        service.save_health(snapshot)
        return JSONResponse({"saved": True})

    async def disconnect(request: Request) -> Response:
        return JSONResponse(await service.disconnect(request.path_params["source"]))

    async def begin(request: Request) -> Response:
        url, browser = service.begin(request.query_params.get("ticket", ""))
        response = RedirectResponse(url, status_code=303)
        response.set_cookie(
            COOKIE,
            browser,
            max_age=600,
            httponly=True,
            samesite="lax",
            secure=service.callback_url.startswith("https:"),
            path=CALLBACK,
        )
        return response

    async def callback(request: Request) -> Response:
        await service.finish(
            request.query_params.get("state", ""),
            request.cookies.get(COOKIE, ""),
            request.query_params.get("code"),
            "error" in request.query_params,
        )
        response = HTMLResponse(
            "<h1>Oura connected</h1><p>Return to Quiet Compass and tap Sync Oura to share daily summaries.</p>"
        )
        response.delete_cookie(COOKIE, path=CALLBACK)
        return response

    def endpoint(handler, authenticated=True):
        async def safe(request: Request) -> Response:
            try:
                response = await handler(request)
            except WearableError as exc:
                if authenticated:
                    response = JSONResponse({"detail": str(exc)}, status_code=exc.status)
                else:
                    response = HTMLResponse(
                        f"<h1>Connection incomplete</h1><p>{escape(str(exc))}</p>", status_code=exc.status
                    )
                    response.delete_cookie(COOKIE, path=CALLBACK)
            response.headers.update(HEADERS)
            return response

        return guarded(token, safe) if authenticated else safe

    return [
        Route("/v1/wearables/oura/link", endpoint(link), methods=["POST"]),
        Route("/v1/wearables/context", endpoint(context), methods=["GET"]),
        Route("/v1/wearables/oura/sync", endpoint(sync), methods=["POST"]),
        Route("/v1/wearables/apple-health", endpoint(upload), methods=["PUT"]),
        Route("/v1/wearables/{source}", endpoint(disconnect), methods=["DELETE"]),
        Route("/connect/oura", endpoint(begin, False), methods=["GET"]),
        Route(CALLBACK, endpoint(callback, False), methods=["GET"]),
    ]
