import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing authorization" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const token = authHeader.replace("Bearer ", "");
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser(token);

  if (error || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const secrets = {
    r2_endpoint: Deno.env.get("R2_ENDPOINT"),
    r2_access_key_id: Deno.env.get("R2_ACCESS_KEY_ID"),
    r2_secret_access_key: Deno.env.get("R2_SECRET_ACCESS_KEY"),
    r2_bucket_name: Deno.env.get("R2_BUCKET_NAME"),
    r2_public_url: Deno.env.get("R2_PUBLIC_URL"),
    hubtel_client_id: Deno.env.get("HUBTEL_CLIENT_ID"),
    hubtel_client_secret: Deno.env.get("HUBTEL_CLIENT_SECRET"),
    hubtel_sender_id: Deno.env.get("HUBTEL_SENDER_ID"),
    paystack_public_key: Deno.env.get("PAYSTACK_PUBLIC_KEY"),
    supabase_redirect_url: Deno.env.get("REDIRECT_URL"),
    giphy_api_key: Deno.env.get("GIPHY_API_KEY"),
    app_version: Deno.env.get("APP_VERSION"),
  };

  return new Response(JSON.stringify(secrets), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
