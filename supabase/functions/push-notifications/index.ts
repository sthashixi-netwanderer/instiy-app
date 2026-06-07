import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { JWT } from "npm:google-auth-library";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload = await req.json();
    console.log("Push notification webhook triggered with payload:", JSON.stringify(payload));

    // Supabase Webhook sends payload.record on INSERT. Otherwise fallback to the payload itself.
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

    // 1. Initialize Supabase Service Role client to bypass RLS
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // 2. Fetch all registered FCM tokens for the recipient user
    const { data: tokenRecords, error: tokenError } = await supabase
      .from("user_push_tokens")
      .select("token")
      .eq("user_id", record.user_id);

    if (tokenError) {
      console.error("Error fetching user push tokens:", tokenError);
      throw tokenError;
    }

    if (!tokenRecords || tokenRecords.length === 0) {
      console.log(`No active FCM tokens registered for user: ${record.user_id}`);
      return new Response(JSON.stringify({ message: "No active FCM tokens found for this user." }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 3. Load Firebase Service Account Credentials from environment variables
    const serviceAccountKeyStr = Deno.env.get("FCM_SERVICE_ACCOUNT_KEY");
    if (!serviceAccountKeyStr) {
      console.error("FCM_SERVICE_ACCOUNT_KEY environment variable is not configured.");
      return new Response(JSON.stringify({ error: "FCM_SERVICE_ACCOUNT_KEY not configured on Supabase" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    let serviceAccount;
    try {
      serviceAccount = JSON.parse(serviceAccountKeyStr);
    } catch (e) {
      console.error("Failed to parse FCM_SERVICE_ACCOUNT_KEY JSON:", e);
      return new Response(JSON.stringify({ error: "Invalid FCM_SERVICE_ACCOUNT_KEY JSON format" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const projectId = serviceAccount.project_id;
    if (!projectId) {
      return new Response(JSON.stringify({ error: "Missing project_id in Service Account credentials" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 4. Authenticate using Google OAuth2 JWT to get access token for Firebase Messaging scope
    const jwtClient = new JWT({
      email: serviceAccount.client_email,
      key: serviceAccount.private_key,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });

    const jwtToken = await jwtClient.authorize();
    const accessToken = jwtToken.access_token;
    if (!accessToken) {
      throw new Error("Failed to generate Google OAuth2 Access Token for FCM");
    }

    // 5. Build Stringified Data Payload
    const stringData: Record<string, string> = {};
    if (record.data) {
      for (const [key, val] of Object.entries(record.data)) {
        stringData[key] = typeof val === "object" ? JSON.stringify(val) : String(val);
      }
    }
    stringData["id"] = String(record.id);
    stringData["type"] = String(type);
    stringData["click_action"] = "FLUTTER_NOTIFICATION_CLICK";

    // 6. Send push notification to each registered device token
    const results = [];
    for (const { token } of tokenRecords) {
      const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
      
      const payload = {
        message: {
          token: token,
          notification: {
            title: title,
            body: body,
          },
          data: stringData,
          android: {
            priority: "high",
            notification: {
              sound: "default",
              click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
                "content-available": 1,
              },
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
          body: JSON.stringify(payload),
        });

        const resBody = await response.json();
        if (!response.ok) {
          console.error(`FCM send failed for token: ${token.substring(0, 10)}...`, resBody);
          // If token is invalid or inactive (UNREGISTERED), we should delete it from our DB
          if (resBody.error && (resBody.error.status === "UNREGISTERED" || resBody.error.message?.includes("not registered"))) {
            console.log(`Deleting invalid token from DB: ${token.substring(0, 10)}...`);
            await supabase.from("user_push_tokens").delete().eq("token", token);
          }
          results.push({ token, success: false, error: resBody });
        } else {
          console.log(`Successfully sent FCM push to token: ${token.substring(0, 10)}...`);
          results.push({ token, success: true, messageId: resBody.name });
        }
      } catch (err) {
        console.error(`Network error sending FCM for token ${token}:`, err);
        results.push({ token, success: false, error: err.message });
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
      }
    );
  } catch (error) {
    console.error("Push Notification Function error:", error);
    return new Response(JSON.stringify({ error: error.message || "Failed to process push notifications" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
