# Quiet Compass memory service

The Python service exposes authenticated ingestion at `/v1` and MCP tools at
`/mcp`, backed by SQLite. The implementation uses Starlette and the MCP Python SDK.
The web map's older browser-cookie Oura connection remains separate in
`apps/quiet-compass`; the native app uses this server's private wearable connection.

## Run locally

From this directory, use Python 3.12 or later:

```sh
python3.12 -m venv .venv
. .venv/bin/activate
pip install -e '.[dev]'
cp .env.example .env
# Edit .env and replace QC_API_TOKEN with a long random value.
uvicorn quiet_compass.app:create_app --factory --env-file .env --reload --no-access-log
```

`--env-file` loads the configuration; copying `.env` alone does not load it.
`GET /healthz` is public and returns `{"ok":true}`. Every `/v1` operation and the
default `/mcp` endpoint require `Authorization: Bearer <QC_API_TOKEN>`.

```sh
ruff check .
pytest -q
```

The HTTP payloads and tool parameters are in [the contract](../contracts/README.md).
No observations are created automatically. An empty service reports that there
is no recording session. Fixtures in `tests/` are synthetic test data.

## Host the demo on Render

The root [render.yaml](../render.yaml) prepares one Python web service in Oregon,
one worker process, a generated API token and a 1 GB persistent disk. The database
lives at `/var/data/quiet_compass.db`. Importing the Blueprint creates paid
resources; check the current [Render prices](https://render.com/pricing) before
creating the service. No cloud resources are created by committing this file.

1. In Render, create a Blueprint from this GitHub repository and branch `main`.
2. Review the service and disk, then create them. The Blueprint starts Uvicorn on
   Render's assigned port and checks `/healthz`.
3. Copy the assigned HTTPS base URL. Use the actual URL from Render, not the
   example name in these documents. `RENDER_EXTERNAL_HOSTNAME` is automatically
   added to the MCP host allowlist; custom domains go in `QC_ALLOWED_HOSTS`.
4. Retrieve the generated `QC_API_TOKEN` from the service's environment settings.
   Configure it in the phone and the agent connector, never in Git or a chat.
5. Register a recording session from the phone. Set `QC_ACTIVE_SESSION_ID` to that
   session's UUID for the demo. Without it, tools select the last updated session.
6. Confirm that a valid connector can list tools, an unauthorized call fails,
   and saved observations are still present after a restart.

Subsequent backend commits deploy after linked CI checks pass. A disk-backed
service has a brief interruption during deployment and cannot share its disk
across replicas. Keep one instance. The free service has no persistent disk and
does not fit this SQLite setup. The disk survives restarts; deletion of the
service/disk is a separate operation. Before destructive operations, export a
consistent SQLite backup using the SQLite backup API and verify restoration.

This is a **single-user demo backend**. Its shared token can access every session
in its database. An active-session setting selects context; it does not enforce
user isolation. Do not connect unrelated participants to the same instance as
though it provided private accounts. Multi-user hosting needs authenticated
ownership on every record and query, followed by a database migration plan.

## Connect the agent and phone

For Claude, add the actual `https://<assigned-host>/mcp` URL as a custom connector
and set a fixed request header `Authorization: Bearer <QC_API_TOKEN>`. Enable the
connector in the conversation and use [agent_instructions.md](agent_instructions.md).
This server implements bearer authentication, not an OAuth authorization server.
Keep `QC_MCP_PATH_SECRET` unset for this deployment.

Enter the server URL and the same API token in the native app's Connection section.
The token is stored in Keychain, not in the application bundle.
Starting guidance records a target; it does not prove the phone received or
displayed it. Verify that behavior on a connected device.

## Wearables, learning and proactive help

The server now supports Oura OAuth with PKCE, encrypted token storage, rotating
refresh tokens, periodic sync and disconnection. It accepts explicitly shared
Apple Health summaries and exposes `quiet_get_personal_context` through MCP.
Set `QC_ENCRYPTION_KEY` for private storage; Oura additionally requires
`QC_OURA_CLIENT_ID`, `QC_OURA_CLIENT_SECRET` and a public URL. Keep one worker.
See [setup, endpoints and verification](../docs/WEARABLES_AND_PHONE.md).

The autonomous agent runner and learning a profile across sessions are still
pending. Oura's polling task only updates data; it does not invoke a model or
send notifications. Do not expose browser cookies as MCP credentials.

## Hosting references

Reviewed October 24, 2026:

- [Render web services and ports](https://render.com/docs/web-services)
- [Blueprint fields and deployment triggers](https://render.com/docs/blueprint-spec)
- [Persistent disks and their limitations](https://render.com/docs/disks)
- [Assigned host environment variable](https://render.com/docs/environment-variables)
- [Claude custom connectors and request headers](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp)
