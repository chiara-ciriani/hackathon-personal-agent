"""OAuth 2.1 authorization for the shared Quiet Compass MCP tools."""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import secrets
import sqlite3
import time
from html import escape
from pathlib import Path
from urllib.parse import urlencode

from mcp.server.auth.provider import (
    AccessToken,
    AuthorizationCode,
    AuthorizationParams,
    AuthorizeError,
    OAuthAuthorizationServerProvider,
    RefreshToken,
    TokenError,
    construct_redirect_uri,
)
from mcp.server.auth.routes import create_auth_routes, create_protected_resource_routes
from mcp.server.auth.settings import ClientRegistrationOptions, RevocationOptions
from mcp.shared.auth import OAuthClientInformationFull, OAuthToken
from pydantic import AnyHttpUrl
from starlette.requests import Request
from starlette.responses import HTMLResponse, RedirectResponse, Response
from starlette.routing import Route

DOT_SCOPE = "quiet-compass:shared"
ACCESS_SECONDS = 3600
REFRESH_SECONDS = 30 * 24 * 3600
CODE_SECONDS = 300
REQUEST_SECONDS = 600


def _fingerprint(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


class OAuthStore:
    """Persist OAuth grants by hash so bearer tokens and codes never rest in SQLite."""

    def __init__(self, path: Path | str) -> None:
        self.path = Path(path)

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=5, isolation_level=None)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA busy_timeout=5000")
        connection.execute("PRAGMA synchronous=NORMAL")
        return connection

    def migrate(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as connection:
            connection.executescript("""
                CREATE TABLE IF NOT EXISTS mcp_oauth_clients (
                    client_id TEXT PRIMARY KEY, body TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS mcp_oauth_requests (
                    request_hash TEXT PRIMARY KEY, body TEXT NOT NULL, expires_at INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS mcp_oauth_codes (
                    code_hash TEXT PRIMARY KEY, body TEXT NOT NULL, expires_at INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS mcp_oauth_access (
                    token_hash TEXT PRIMARY KEY, body TEXT NOT NULL, expires_at INTEGER NOT NULL,
                    refresh_hash TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS mcp_oauth_refresh (
                    token_hash TEXT PRIMARY KEY, body TEXT NOT NULL, access_hash TEXT NOT NULL,
                    expires_at INTEGER NOT NULL
                );
            """)

    def save_client(self, client: OAuthClientInformationFull) -> None:
        with self._connect() as connection:
            connection.execute(
                "INSERT OR REPLACE INTO mcp_oauth_clients (client_id, body) VALUES (?, ?)",
                (client.client_id, client.model_dump_json(exclude_none=True)),
            )

    def get_client(self, client_id: str) -> str | None:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT body FROM mcp_oauth_clients WHERE client_id = ?", (client_id,)
            ).fetchone()
        return row["body"] if row else None

    def save_request(self, request_id: str, body: dict[str, object]) -> None:
        now = int(time.time())
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            connection.execute("DELETE FROM mcp_oauth_requests WHERE expires_at <= ?", (now,))
            connection.execute(
                "INSERT INTO mcp_oauth_requests (request_hash, body, expires_at) VALUES (?, ?, ?)",
                (_fingerprint(request_id), json.dumps(body), now + REQUEST_SECONDS),
            )
            connection.commit()

    def get_request(self, request_id: str) -> dict[str, object] | None:
        now = int(time.time())
        key = _fingerprint(request_id)
        with self._connect() as connection:
            row = connection.execute(
                "SELECT body, expires_at FROM mcp_oauth_requests WHERE request_hash = ?", (key,)
            ).fetchone()
            if row is None or row["expires_at"] <= now:
                connection.execute("DELETE FROM mcp_oauth_requests WHERE request_hash = ?", (key,))
                return None
        return json.loads(row["body"])

    def consume_request(self, request_id: str) -> dict[str, object] | None:
        now = int(time.time())
        key = _fingerprint(request_id)
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                "SELECT body, expires_at FROM mcp_oauth_requests WHERE request_hash = ?", (key,)
            ).fetchone()
            connection.execute("DELETE FROM mcp_oauth_requests WHERE request_hash = ?", (key,))
            connection.commit()
        if row is None or row["expires_at"] <= now:
            return None
        return json.loads(row["body"])

    def save_code(self, code: AuthorizationCode) -> None:
        body = code.model_dump(exclude={"code"})
        body["redirect_uri"] = str(code.redirect_uri)
        with self._connect() as connection:
            connection.execute(
                "INSERT OR REPLACE INTO mcp_oauth_codes (code_hash, body, expires_at) VALUES (?, ?, ?)",
                (_fingerprint(code.code), json.dumps(body), int(code.expires_at)),
            )

    def get_code(self, code: str) -> dict[str, object] | None:
        now = int(time.time())
        key = _fingerprint(code)
        with self._connect() as connection:
            row = connection.execute(
                "SELECT body, expires_at FROM mcp_oauth_codes WHERE code_hash = ?", (key,)
            ).fetchone()
            if row is None or row["expires_at"] <= now:
                connection.execute("DELETE FROM mcp_oauth_codes WHERE code_hash = ?", (key,))
                return None
        return json.loads(row["body"])

    def consume_code(self, code: str) -> dict[str, object] | None:
        now = int(time.time())
        key = _fingerprint(code)
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                "SELECT body, expires_at FROM mcp_oauth_codes WHERE code_hash = ?", (key,)
            ).fetchone()
            connection.execute("DELETE FROM mcp_oauth_codes WHERE code_hash = ?", (key,))
            connection.commit()
        if row is None or row["expires_at"] <= now:
            return None
        return json.loads(row["body"])

    def save_tokens(self, access: AccessToken, refresh: RefreshToken) -> None:
        access_hash, refresh_hash = _fingerprint(access.token), _fingerprint(refresh.token)
        access_body = access.model_dump(exclude={"token"})
        refresh_body = refresh.model_dump(exclude={"token"})
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            connection.execute(
                "INSERT INTO mcp_oauth_access (token_hash, body, expires_at, refresh_hash) VALUES (?, ?, ?, ?)",
                (access_hash, json.dumps(access_body), access.expires_at or 0, refresh_hash),
            )
            connection.execute(
                "INSERT INTO mcp_oauth_refresh (token_hash, body, access_hash, expires_at) VALUES (?, ?, ?, ?)",
                (refresh_hash, json.dumps(refresh_body), access_hash, refresh.expires_at or 0),
            )
            connection.commit()

    def get_access(self, token: str) -> dict[str, object] | None:
        now = int(time.time())
        key = _fingerprint(token)
        with self._connect() as connection:
            row = connection.execute(
                "SELECT body, expires_at FROM mcp_oauth_access WHERE token_hash = ?", (key,)
            ).fetchone()
            if row is None or row["expires_at"] <= now:
                connection.execute("DELETE FROM mcp_oauth_access WHERE token_hash = ?", (key,))
                return None
        return json.loads(row["body"])

    def get_refresh(self, token: str) -> dict[str, object] | None:
        now = int(time.time())
        key = _fingerprint(token)
        with self._connect() as connection:
            row = connection.execute(
                "SELECT body, expires_at FROM mcp_oauth_refresh WHERE token_hash = ?", (key,)
            ).fetchone()
            if row is None or row["expires_at"] <= now:
                connection.execute("DELETE FROM mcp_oauth_refresh WHERE token_hash = ?", (key,))
                return None
        return json.loads(row["body"])

    def rotate_refresh(self, token: str) -> dict[str, object] | None:
        now = int(time.time())
        key = _fingerprint(token)
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                "SELECT body, access_hash, expires_at FROM mcp_oauth_refresh WHERE token_hash = ?", (key,)
            ).fetchone()
            connection.execute("DELETE FROM mcp_oauth_refresh WHERE token_hash = ?", (key,))
            if row is not None:
                connection.execute("DELETE FROM mcp_oauth_access WHERE token_hash = ?", (row["access_hash"],))
            connection.commit()
        if row is None or row["expires_at"] <= now:
            return None
        return json.loads(row["body"])

    def revoke_access(self, token: str) -> None:
        key = _fingerprint(token)
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                "SELECT refresh_hash FROM mcp_oauth_access WHERE token_hash = ?", (key,)
            ).fetchone()
            connection.execute("DELETE FROM mcp_oauth_access WHERE token_hash = ?", (key,))
            if row:
                connection.execute("DELETE FROM mcp_oauth_refresh WHERE token_hash = ?", (row["refresh_hash"],))
            connection.commit()

    def revoke_refresh(self, token: str) -> None:
        key = _fingerprint(token)
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                "SELECT access_hash FROM mcp_oauth_refresh WHERE token_hash = ?", (key,)
            ).fetchone()
            connection.execute("DELETE FROM mcp_oauth_refresh WHERE token_hash = ?", (key,))
            if row:
                connection.execute("DELETE FROM mcp_oauth_access WHERE token_hash = ?", (row["access_hash"],))
            connection.commit()


class DotOAuthProvider(OAuthAuthorizationServerProvider[AuthorizationCode, RefreshToken, AccessToken]):
    """Minimal OAuth issuer limited to the shared MCP scope and tool set."""

    def __init__(self, path: Path | str, issuer: str, resource: str, credentials: tuple[str, ...]) -> None:
        self.store = OAuthStore(path)
        self.store.migrate()
        self.issuer = issuer.rstrip("/")
        self.resource = resource
        self.credentials = tuple(value for value in credentials if value)

    async def get_client(self, client_id: str) -> OAuthClientInformationFull | None:
        body = await asyncio.to_thread(self.store.get_client, client_id)
        return OAuthClientInformationFull.model_validate_json(body) if body else None

    async def register_client(self, client_info: OAuthClientInformationFull) -> None:
        await asyncio.to_thread(self.store.save_client, client_info)

    async def authorize(self, client: OAuthClientInformationFull, params: AuthorizationParams) -> str:
        if params.resource and params.resource.rstrip("/") != self.resource.rstrip("/"):
            raise AuthorizeError("invalid_target", "This token is only valid for Quiet Compass shared tools")
        scopes = params.scopes or [DOT_SCOPE]
        if not scopes or any(scope != DOT_SCOPE for scope in scopes):
            raise AuthorizeError("invalid_scope", "Only shared Quiet Compass tools are available")
        request_id = secrets.token_urlsafe(32)
        await asyncio.to_thread(self.store.save_request, request_id, {
            "client_id": client.client_id,
            "scopes": scopes,
            "code_challenge": params.code_challenge,
            "redirect_uri": str(params.redirect_uri),
            "redirect_uri_provided_explicitly": params.redirect_uri_provided_explicitly,
            "state": params.state,
            "resource": self.resource,
        })
        return f"{self.issuer}/oauth/consent?{urlencode({'request': request_id})}"

    async def authorization_request(self, request_id: str) -> dict[str, object] | None:
        return await asyncio.to_thread(self.store.get_request, request_id)

    def verify_owner_key(self, supplied: str) -> bool:
        if not supplied:
            return False
        candidate = supplied.encode()
        return any(hmac.compare_digest(candidate, expected.encode()) for expected in self.credentials)

    async def allow(self, request_id: str, supplied_key: str) -> str | None:
        if not self.verify_owner_key(supplied_key):
            return None
        request = await asyncio.to_thread(self.store.consume_request, request_id)
        if request is None:
            return None
        client = await self.get_client(str(request["client_id"]))
        if client is None:
            return None
        code = AuthorizationCode(
            code=secrets.token_urlsafe(32),
            client_id=str(request["client_id"]),
            scopes=list(request["scopes"]),
            expires_at=time.time() + CODE_SECONDS,
            code_challenge=str(request["code_challenge"]),
            redirect_uri=str(request["redirect_uri"]),
            redirect_uri_provided_explicitly=bool(request["redirect_uri_provided_explicitly"]),
            resource=self.resource,
            subject="quiet-compass-owner",
        )
        await asyncio.to_thread(self.store.save_code, code)
        params = {"code": code.code}
        if request.get("state") is not None:
            params["state"] = str(request["state"])
        return construct_redirect_uri(str(code.redirect_uri), **params)

    async def deny(self, request_id: str) -> str | None:
        request = await asyncio.to_thread(self.store.consume_request, request_id)
        if request is None:
            return None
        client = await self.get_client(str(request["client_id"]))
        if client is None:
            return None
        params = {"error": "access_denied"}
        if request.get("state") is not None:
            params["state"] = str(request["state"])
        return construct_redirect_uri(str(request["redirect_uri"]), **params)

    async def load_authorization_code(
        self, client: OAuthClientInformationFull, authorization_code: str
    ) -> AuthorizationCode | None:
        body = await asyncio.to_thread(self.store.get_code, authorization_code)
        if body is None or body.get("client_id") != client.client_id:
            return None
        return AuthorizationCode.model_validate({"code": authorization_code, **body})

    async def exchange_authorization_code(
        self, client: OAuthClientInformationFull, authorization_code: AuthorizationCode
    ) -> OAuthToken:
        body = await asyncio.to_thread(self.store.consume_code, authorization_code.code)
        if body is None or body.get("client_id") != client.client_id:
            raise TokenError("invalid_grant", "Authorization code is invalid or has already been used")
        access = AccessToken(
            token=secrets.token_urlsafe(32), client_id=str(client.client_id),
            scopes=list(body["scopes"]), expires_at=int(time.time()) + ACCESS_SECONDS,
            resource=self.resource, subject="quiet-compass-owner",
        )
        refresh = RefreshToken(
            token=secrets.token_urlsafe(32), client_id=str(client.client_id),
            scopes=list(body["scopes"]), expires_at=int(time.time()) + REFRESH_SECONDS,
            resource=self.resource, subject="quiet-compass-owner",
        )
        await asyncio.to_thread(self.store.save_tokens, access, refresh)
        return OAuthToken(
            access_token=access.token, token_type="Bearer", expires_in=ACCESS_SECONDS,
            scope=" ".join(access.scopes), refresh_token=refresh.token,
        )

    async def load_access_token(self, token: str) -> AccessToken | None:
        body = await asyncio.to_thread(self.store.get_access, token)
        return AccessToken.model_validate({"token": token, **body}) if body else None

    async def verify_token(self, token: str) -> AccessToken | None:
        return await self.load_access_token(token)

    async def load_refresh_token(
        self, client: OAuthClientInformationFull, refresh_token: str
    ) -> RefreshToken | None:
        body = await asyncio.to_thread(self.store.get_refresh, refresh_token)
        if body is None or body.get("client_id") != client.client_id:
            return None
        return RefreshToken.model_validate({"token": refresh_token, **body})

    async def exchange_refresh_token(
        self, client: OAuthClientInformationFull, refresh_token: RefreshToken, scopes: list[str]
    ) -> OAuthToken:
        body = await asyncio.to_thread(self.store.rotate_refresh, refresh_token.token)
        if body is None or body.get("client_id") != client.client_id:
            raise TokenError("invalid_grant", "Refresh token is invalid or has already been used")
        granted = set(body["scopes"])
        requested = set(scopes) if scopes else granted
        if not requested or not requested.issubset(granted) or requested != {DOT_SCOPE}:
            raise TokenError("invalid_scope", "Only shared Quiet Compass tools are available")
        access = AccessToken(
            token=secrets.token_urlsafe(32), client_id=str(client.client_id),
            scopes=list(requested), expires_at=int(time.time()) + ACCESS_SECONDS,
            resource=self.resource, subject="quiet-compass-owner",
        )
        refresh = RefreshToken(
            token=secrets.token_urlsafe(32), client_id=str(client.client_id),
            scopes=list(requested), expires_at=int(time.time()) + REFRESH_SECONDS,
            resource=self.resource, subject="quiet-compass-owner",
        )
        await asyncio.to_thread(self.store.save_tokens, access, refresh)
        return OAuthToken(
            access_token=access.token, token_type="Bearer", expires_in=ACCESS_SECONDS,
            scope=" ".join(access.scopes), refresh_token=refresh.token,
        )

    async def revoke_token(self, token: AccessToken | RefreshToken) -> None:
        revoke = self.store.revoke_access if isinstance(token, AccessToken) else self.store.revoke_refresh
        await asyncio.to_thread(revoke, token.token)


def build_dot_oauth_routes(
    provider: DotOAuthProvider, issuer: str, resource: str
) -> list[Route]:
    """OAuth discovery, dynamic client registration, and owner-consent page for ChatGPT."""
    routes = create_auth_routes(
        provider,
        issuer_url=AnyHttpUrl(issuer),
        client_registration_options=ClientRegistrationOptions(
            enabled=True, valid_scopes=[DOT_SCOPE], default_scopes=[DOT_SCOPE]
        ),
        revocation_options=RevocationOptions(enabled=True),
    )
    routes.extend(create_protected_resource_routes(
        resource_url=AnyHttpUrl(resource),
        authorization_servers=[AnyHttpUrl(issuer)],
        scopes_supported=[DOT_SCOPE],
        resource_name="Quiet Compass shared sound tools",
    ))

    def page(request_id: str, client_name: str, error: str = "") -> HTMLResponse:
        error_html = f'<p role="alert">{escape(error)}</p>' if error else ""
        body = f"""<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Connect Quiet Compass</title>
<style>
body{{font:16px system-ui;max-width:520px;margin:12vh auto;padding:24px;color:#171717}}
input,button{{font:inherit;padding:12px;border:1px solid #ccc;border-radius:10px}}
input{{box-sizing:border-box;width:100%;margin:12px 0}}
button{{cursor:pointer}}
button[type=submit]{{background:#5b35a5;color:white;border:0}}
small{{color:#666}}
</style>
<h1>Connect Quiet Compass</h1><p><strong>{escape(client_name)}</strong> wants to use shared sound and phone tools.</p>
<p>It will not receive raw audio, personal health data, or private routes.
Phone capture still requires your approval.</p>
{error_html}<form method="post" action="/oauth/consent">
<input type="hidden" name="request" value="{escape(request_id, quote=True)}">
<label for="key">Shared server access key</label>
<input id="key" name="shared_access_key" type="password" autocomplete="current-password" required>
<small>The key is checked by Quiet Compass and is not saved in your browser.</small><p>
<button type="submit" name="action" value="allow">Allow access</button>
<button type="submit" name="action" value="deny" formnovalidate>Cancel</button></p></form></html>"""
        return HTMLResponse(body, headers={
            "Cache-Control": "no-store", "Pragma": "no-cache", "Referrer-Policy": "no-referrer",
            "X-Content-Type-Options": "nosniff",
            "Content-Security-Policy": (
                "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; "
                "base-uri 'none'; frame-ancestors 'none'"
            ),
        })

    async def consent_get(request: Request) -> HTMLResponse:
        request_id = request.query_params.get("request", "")
        details = await provider.authorization_request(request_id) if request_id else None
        if details is None:
            return HTMLResponse("Authorization request expired. Reconnect Quiet Compass.", status_code=400,
                                headers={"Cache-Control": "no-store", "Referrer-Policy": "no-referrer"})
        client = await provider.get_client(str(details["client_id"]))
        if client is None:
            return HTMLResponse("Unknown MCP client.", status_code=400, headers={"Cache-Control": "no-store"})
        name = client.client_name or "ChatGPT"
        return page(request_id, name)

    async def consent_post(request: Request) -> Response:
        form = await request.form()
        request_id = str(form.get("request", ""))
        action = str(form.get("action", ""))
        if action == "deny":
            redirect = await provider.deny(request_id)
            if redirect:
                return RedirectResponse(redirect, status_code=303, headers={"Cache-Control": "no-store"})
            return HTMLResponse("Authorization request expired. Reconnect Quiet Compass.", status_code=400,
                                headers={"Cache-Control": "no-store"})
        details = await provider.authorization_request(request_id) if request_id else None
        client = await provider.get_client(str(details["client_id"])) if details else None
        if details is None or client is None:
            return HTMLResponse("Authorization request expired. Reconnect Quiet Compass.", status_code=400,
                                headers={"Cache-Control": "no-store"})
        secret = str(form.get("shared_access_key", ""))
        if not provider.verify_owner_key(secret):
            return page(request_id, client.client_name or "ChatGPT", "That access key did not match.")
        redirect = await provider.allow(request_id, secret)
        if redirect:
            return RedirectResponse(redirect, status_code=303, headers={"Cache-Control": "no-store"})
        return HTMLResponse("Authorization request expired. Reconnect Quiet Compass.", status_code=400,
                            headers={"Cache-Control": "no-store"})

    routes.extend([
        Route("/oauth/consent", consent_get, methods=["GET"]),
        Route("/oauth/consent", consent_post, methods=["POST"]),
    ])
    return routes
