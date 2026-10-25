import asyncio
from urllib.parse import parse_qs, urlparse

from mcp.server.auth.provider import AuthorizationParams
from mcp.shared.auth import OAuthClientInformationFull
from pydantic import AnyUrl

from quiet_compass.mcp_oauth import DOT_SCOPE, DotOAuthProvider


def test_dot_oauth_consent_issues_scoped_rotating_tokens(tmp_path):
    async def run():
        resource = "https://quiet.example/mcp/dot"
        provider = DotOAuthProvider(
            tmp_path / "oauth.sqlite", "https://quiet.example", resource,
            ("shared-access-key-for-test",),
        )
        client = OAuthClientInformationFull(
            client_id="chatgpt-test-client", client_name="ChatGPT",
            redirect_uris=[AnyUrl("https://chatgpt.example/callback")],
            token_endpoint_auth_method="none",
        )
        await provider.register_client(client)
        params = AuthorizationParams(
            state="state", scopes=[DOT_SCOPE], code_challenge="a" * 43,
            redirect_uri=AnyUrl("https://chatgpt.example/callback"),
            redirect_uri_provided_explicitly=True, resource=resource,
        )
        consent_url = await provider.authorize(client, params)
        request_id = parse_qs(urlparse(consent_url).query)["request"][0]

        assert not provider.verify_owner_key("wrong-key")
        redirect = await provider.allow(request_id, "shared-access-key-for-test")
        code = parse_qs(urlparse(redirect).query)["code"][0]
        stored_code = await provider.load_authorization_code(client, code)
        tokens = await provider.exchange_authorization_code(client, stored_code)
        access = await provider.verify_token(tokens.access_token)
        assert access.scopes == [DOT_SCOPE]
        assert access.resource == resource

        refresh = await provider.load_refresh_token(client, tokens.refresh_token)
        renewed = await provider.exchange_refresh_token(client, refresh, [DOT_SCOPE])
        assert await provider.verify_token(tokens.access_token) is None
        assert await provider.verify_token(renewed.access_token) is not None
        await provider.revoke_token(await provider.load_refresh_token(client, renewed.refresh_token))
        assert await provider.verify_token(renewed.access_token) is None

    asyncio.run(run())


def test_consent_page_allows_redirect_to_client_callback(tmp_path, monkeypatch):
    import base64
    import hashlib

    from starlette.testclient import TestClient

    from quiet_compass.app import create_app

    monkeypatch.setenv("QC_API_TOKEN", "a" * 32)
    monkeypatch.setenv("QC_SHARED_API_TOKEN", "b" * 32)
    monkeypatch.setenv("QC_DB_PATH", str(tmp_path / "qc.db"))
    monkeypatch.setenv("QC_PUBLIC_URL", "https://srv.example")
    monkeypatch.setenv("QC_ENCRYPTION_KEY", base64.b64encode(b"k" * 32).decode())
    callback = "https://chatgpt.com/connector_platform_oauth_redirect"
    with TestClient(create_app(), base_url="https://srv.example") as client:
        registered = client.post("/register", json={
            "client_name": "ChatGPT", "redirect_uris": [callback],
            "grant_types": ["authorization_code", "refresh_token"], "response_types": ["code"],
            "token_endpoint_auth_method": "none",
        }).json()
        verifier = "v" * 64
        challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
        consent = client.get("/authorize", params={
            "response_type": "code", "client_id": registered["client_id"], "redirect_uri": callback,
            "code_challenge": challenge, "code_challenge_method": "S256", "state": "s",
            "scope": "quiet-compass:shared", "resource": "https://srv.example/mcp/dot",
        })
        assert consent.status_code == 200
        assert "form-action 'self' https://chatgpt.com;" in consent.headers["content-security-policy"]
        request_id = parse_qs(urlparse(str(consent.url)).query)["request"][0]
        approved = client.post("/oauth/consent", data={
            "request": request_id, "action": "allow", "shared_access_key": "b" * 32,
        }, follow_redirects=False)
        assert approved.status_code == 303
        assert approved.headers["location"].startswith(callback + "?code=")
