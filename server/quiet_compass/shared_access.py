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
    "Then find_suitable_places and send_phone_recommendation return advice to the phone. "
    "This endpoint contains only shared sound tools. First obtain the user's consent to share a "
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
