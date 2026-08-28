import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function sanitizeError(error) {
  console.error("Push Notification Function error:", error);
  return `Failed to process push notifications: ${error?.message ?? String(error)}`;
}

// Google OAuth2 JWT assertion signed with Web Crypto — no external auth
// library, so cold starts never depend on registry module fetches.
async function getAccessToken(serviceAccount) {
  const now = Math.floor(Date.now() / 1000);
  // JWT segments must be base64URL (- and _, no padding) — a raw '+' or '/'
// from btoa silently invalidates the signature.
const b64url = (s) => btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const body = b64url(
    JSON.stringify({
      iss: serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      exp: now + 3600,
      iat: now,
    }),
  );
  const signingInput = `${header}.${body}`;

  const keyData = serviceAccount.private_key
    .replace(/-----BEGIN [A-Z ]+-----/g, "")
    .replace(/-----END [A-Z ]+-----/g, "")
    .replace(/\\n/g, "")
    .replace(/\s/g, "");
  const binaryDer = Uint8Array.from(atob(keyData), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signingInput),
  );
  let sigB64 = "";
  const sigBytes = new Uint8Array(signature);
  for (let i = 0; i < sigBytes.length; i++) sigB64 += String.fromCharCode(sigBytes[i]);
  const assertion = `${signingInput}.${b64url(sigB64)}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${assertion}`,
  });
  const tokenData = await tokenRes.json();
  if (!tokenData.access_token) {
    throw new Error(
      `Failed to get access token from Google: HTTP ${tokenRes.status} ${JSON.stringify(tokenData).slice(0, 300)}`,
    );
  }
  return tokenData.access_token;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload = await req.json();

    const record = payload.record || payload;
    if (!record || !record.user_id) {
      return new Response(JSON.stringify({ error: "Missing recipient user_id in record" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const title = record.title || "New Notification";
    const body = record.body || "";
    const type = record.type || "notification";

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const { data: tokenRecords, error: tokenError } = await supabase
      .from("user_push_tokens")
      .select("token")
      .eq("user_id", record.user_id);

    if (tokenError) {
      console.error("Error fetching user push tokens:", tokenError);
      throw tokenError;
    }

    if (!tokenRecords || tokenRecords.length === 0) {
      return new Response(JSON.stringify({ message: "No active FCM tokens found for this user." }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const serviceAccountKeyStr = Deno.env.get("FCM_SERVICE_ACCOUNT_KEY");
    if (!serviceAccountKeyStr) {
      return new Response(JSON.stringify({ error: "FCM service not configured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    let serviceAccount;
    try {
      serviceAccount = JSON.parse(serviceAccountKeyStr);
    } catch {
      return new Response(JSON.stringify({ error: "Invalid FCM configuration" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const projectId = serviceAccount.project_id;
    if (!projectId) {
      return new Response(JSON.stringify({ error: "Invalid FCM configuration" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const accessToken = await getAccessToken(serviceAccount);

    const stringData = {};
    if (record.data) {
      for (const [key, val] of Object.entries(record.data)) {
        stringData[key] = typeof val === "object" ? JSON.stringify(val) : String(val);
      }
    }
    stringData["id"] = String(record.id);
    stringData["type"] = String(type);
    stringData["click_action"] = "FLUTTER_NOTIFICATION_CLICK";

    // Calls are sent as data-only on Android: notification-bearing messages
    // are handled by the system tray and never reach the app's background
    // handler, so a backgrounded/terminated callee would only see a passive
    // banner. Data-only + high priority invokes the app's background handler,
    // which presents the full-screen incoming-call notification. iOS keeps an
    // explicit apns alert so a banner still shows.
    const isCall = type === "call";

    const results = [];
    for (const { token } of tokenRecords) {
      const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

      const fcmPayload = {
        message: {
          token: token,
          ...(isCall ? {} : { notification: { title: title, body: body } }),
          data: stringData,
          android: {
            priority: "high",
            ...(isCall
              ? {}
              : {
                  notification: {
                    sound: "default",
                    click_action: "FLUTTER_NOTIFICATION_CLICK",
                  },
                }),
          },
          apns: {
            payload: {
              aps: isCall
                ? {
                    alert: { title: title, body: body },
                    sound: "default",
                    "content-available": 1,
                  }
                : { sound: "default", "content-available": 1 },
            },
          },
        },
      };

      try {
        const response = await fetch(fcmUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify(fcmPayload),
        });

        const resBody = await response.json();
        if (!response.ok) {
          if (
            resBody.error &&
            (resBody.error.status === "UNREGISTERED" ||
              resBody.error.message?.includes("not registered"))
          ) {
            await supabase.from("user_push_tokens").delete().eq("token", token);
          }
          results.push({ token, success: false, error: resBody });
        } else {
          results.push({ token, success: true, messageId: resBody.name });
        }
      } catch {
        results.push({ token, success: false, error: "Network error" });
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        sentCount: results.filter((r) => r.success).length,
        failCount: results.filter((r) => !r.success).length,
        results,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: sanitizeError(error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
