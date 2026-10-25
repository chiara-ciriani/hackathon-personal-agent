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
