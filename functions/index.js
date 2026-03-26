const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onMessagePublished } = require("firebase-functions/v2/pubsub");
const { defineSecret } = require("firebase-functions/params");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { initializeApp } = require("firebase-admin/app");

initializeApp();

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

// Budget alert kill switch — triggered by Google Cloud Budget Pub/Sub notifications
exports.budgetAlertHandler = onMessagePublished(
  { topic: "budget-alerts" },
  async (event) => {
    const data = event.data.message.json;
    const costAmount = data.costAmount;
    const budgetAmount = data.budgetAmount;

    if (costAmount >= budgetAmount) {
      const db = getFirestore();
      await db.doc("config/googleApi").set({
        enabled: false,
        disabledAt: FieldValue.serverTimestamp(),
        reason: `Budget threshold reached: $${costAmount} of $${budgetAmount}`,
      });
    }
  }
);

// Manually re-enable Google Routes API
exports.reenableGoogleApi = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  const db = getFirestore();
  await db.doc("config/googleApi").set({
    enabled: true,
    reenableAt: FieldValue.serverTimestamp(),
    reenableBy: request.auth.uid,
  });

  return { success: true };
});
