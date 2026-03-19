const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

const stravaClientId = defineSecret("STRAVA_CLIENT_ID");
const stravaClientSecret = defineSecret("STRAVA_CLIENT_SECRET");

exports.stravaTokenExchange = onCall(
  { secrets: [stravaClientId, stravaClientSecret] },
  async (request) => {
    const { code } = request.data;

    if (!code) {
      throw new HttpsError("invalid-argument", "Missing authorization code.");
    }

    const response = await fetch("https://www.strava.com/oauth/token", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        client_id: stravaClientId.value(),
        client_secret: stravaClientSecret.value(),
        code: code,
        grant_type: "authorization_code",
      }),
    });

    if (!response.ok) {
      const errorBody = await response.text();
      throw new HttpsError(
        "internal",
        `Strava token exchange failed: ${errorBody}`
      );
    }

    const data = await response.json();

    return {
      access_token: data.access_token,
      refresh_token: data.refresh_token,
      expires_at: data.expires_at,
    };
  }
);

exports.stravaTokenRefresh = onCall(
  { secrets: [stravaClientId, stravaClientSecret] },
  async (request) => {
    const { refresh_token } = request.data;

    if (!refresh_token) {
      throw new HttpsError("invalid-argument", "Missing refresh token.");
    }

    const response = await fetch("https://www.strava.com/oauth/token", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        client_id: stravaClientId.value(),
        client_secret: stravaClientSecret.value(),
        refresh_token: refresh_token,
        grant_type: "refresh_token",
      }),
    });

    if (!response.ok) {
      const errorBody = await response.text();
      throw new HttpsError(
        "internal",
        `Strava token refresh failed: ${errorBody}`
      );
    }

    const data = await response.json();

    return {
      access_token: data.access_token,
      refresh_token: data.refresh_token,
      expires_at: data.expires_at,
    };
  }
);
