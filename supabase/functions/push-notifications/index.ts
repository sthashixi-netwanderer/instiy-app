import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { JWT } from "npm:google-auth-library";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function sanitizeError(error: unknown): string {
  console.error("Push Notification Function error:", error);
  return "Failed to process push notifications";
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

    const stringData: Record<string, string> = {};
    if (record.data) {
      for (const [key, val] of Object.entries(record.data)) {
        stringData[key] = typeof val === "object" ? JSON.stringify(val) : String(val);
      }
    }
    stringData["id"] = String(record.id);
    stringData["type"] = String(type);
    stringData["click_action"] = "FLUTTER_NOTIFICATION_CLICK";

    const results = [];
    for (const { token } of tokenRecords) {
      const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

      const fcmPayload = {
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
          body: JSON.stringify(fcmPayload),
        });

        const resBody = await response.json();
        if (!response.ok) {
          if (resBody.error && (resBody.error.status === "UNREGISTERED" || resBody.error.message?.includes("not registered"))) {
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
      }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: sanitizeError(error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});