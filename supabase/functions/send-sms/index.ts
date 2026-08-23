import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function isValidPhoneNumber(phone: string): boolean {
  const phoneRegex = /^\+?[1-9]\d{1,14}$/;
  return phoneRegex.test(phone.replace(/\s/g, ''));
}

function sanitizeError(error: unknown): string {
  console.error("SMS send error:", error);
  return "Failed to send SMS";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const token = authHeader.replace("Bearer ", "").trim();
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

    const isServiceRole = token === serviceRoleKey && serviceRoleKey !== "";
    const isAnon = token === anonKey && anonKey !== "";

    let user = null;
    if (!isServiceRole && !isAnon) {
      const supabase = createClient(
        Deno.env.get("SUPABASE_URL") ?? "",
        Deno.env.get("SUPABASE_ANON_KEY") ?? "",
        { global: { headers: { Authorization: authHeader } } }
      );

      const {
        data: { user: authUser },
      } = await supabase.auth.getUser();
      user = authUser;
    }

    if (!isServiceRole && !isAnon && !user) {
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const body = await req.json();
    const { to, content } = body;

    if (!to || !content) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: to, content" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const cleanTo = to.replace(/\s/g, '');
    if (!isValidPhoneNumber(cleanTo)) {
      return new Response(
        JSON.stringify({ error: "Invalid phone number format" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (content.length > 1600) {
      return new Response(
        JSON.stringify({ error: "Message too long (max 1600 characters)" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const clientId = Deno.env.get("HUBTEL_CLIENT_ID");
    const clientSecret = Deno.env.get("HUBTEL_CLIENT_SECRET");
    const from = Deno.env.get("HUBTEL_SENDER_ID") || "Instiy";

    if (!clientId || !clientSecret) {
      return new Response(
        JSON.stringify({ error: "SMS service not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Hubtel "Regular Send" per https://developers.hubtel.com (SMS docs):
    // POST https://smsc.hubtel.com/v1/messages/send with
    // Authorization: Basic base64(clientid:clientsecret) and lowercase
    // from/to/content JSON fields. `to` must be E.164, `from` an approved
    // sender ID (<= 11 alphanumeric chars).
    const basicAuth = 'Basic ' + btoa(`${clientId}:${clientSecret}`);
    const response = await fetch('https://smsc.hubtel.com/v1/messages/send', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': basicAuth,
      },
      body: JSON.stringify({
        from,
        to: cleanTo,
        content,
      }),
    });

    if (response.ok) {
      const data = await response.json();
      return new Response(
        JSON.stringify({ success: true, data }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const errorText = await response.text();
    console.error(`Hubtel SMS failed (${response.status}): ${errorText}`);
    return new Response(
      JSON.stringify({ error: 'Failed to send SMS', detail: `${response.status}: ${errorText}` }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: sanitizeError(error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
