"""One contribution unlocks released shared data for fifteen minutes."""

from .shared_db import SharedStore

CONTRIBUTION_REQUIRED = (
    "contribution_required: call submit_observation with a fresh device measurement and "
    "explicit share_consent=true. Pass its access_receipt to queries for 15 minutes. "
    "After expiry contribute a new measurement. Never invent readings or share health, routes or audio."
)
SHARED_INSTRUCTIONS = (
    "To measure using the user's phone: call connect_phone, show its link to the user, then "
    "request_phone_measurement after they connect. Poll phone_measurement_status. The phone "
    "contributes with the owner's explicit consent and returns the 15-minute access_receipt. "
    "For browser measurements, pass the returned lat/lon and access_receipt to "
    "find_suitable_places or query_sound_map, then use fresh readings and the user's goal to "
    "recommend whether to stay or move. "
    "Then use the returned walk analysis and, when present, its approximately 100 m location "
    "to personalize the owner's advice. With explicit sharing consent, the native walk also "
    "returns an access_receipt; use it to query nearby community measurements. Without that "
    "consent, keep the location private. Use measured sound level, variability and quiet spots "
    "for the owner's stated goal. If they explicitly ask for event monitoring while this Dot "
    "session is active, keep requesting fresh phone readings until their chosen end time or the "
    "15-minute connection expires. Compare only readings with the same capture_profile. Use "
    "the receipt to check recent shared readings around the phone, and write a calm alert in this "
    "Dot chat when the current area is at least 3 dB louder than a measured alternative; avoid "
    "repeated "
    "alerts. Write the finding and recommendation directly in this Dot conversation. "
    "send_phone_recommendation only mirrors it to the connected phone; use it only if the owner "
    "also asks for the phone display. Sound level is not a stress or health diagnosis. "
    "Use find_suitable_places and query_sound_map for recent community evidence; use "
    "quiet_sf_layers and quiet_city_noise_reports for local context, keeping proxy or historical "
    "data distinct from live measurements. This MCP cannot wake a "
    "closed Dot chat or run after the phone app disconnects; never imply background monitoring "
    "or a delivered chat alert in that state. "
    "This endpoint exposes shared sound tools and public SF context layers. First obtain the user's consent to share a "
    "coarse acoustic summary, then call submit_observation with share_consent=true. A valid, "
    "recent device summary without clipping returns access_receipt and access_expires_at, even "
    "if the aggregate is withheld for lack of observations. Use that receipt in query_sound_map "
    "and find_suitable_places until it expires after 15 minutes. Duplicate submissions do not "
    "extend access. Simulated readings do not grant access. If no real measurement is available, "
    "explain what is missing; never fabricate one. No raw audio, health data, routes or identity. "
    "State measurement age and uncertainty; unknown coverage is not quiet."
)


class ContributionRequired(ValueError):
    pass


def require_access(store: SharedStore, receipt: str | None) -> None:
    if not store.has_access(receipt):
        raise ContributionRequired(CONTRIBUTION_REQUIRED)
