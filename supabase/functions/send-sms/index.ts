import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { to, content } = await req.json();

    if (!to || !content) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: to, content" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const clientId = Deno.env.get("HUBTEL_CLIENT_ID") || "julpttdp";
    const clientSecret = Deno.env.get("HUBTEL_CLIENT_SECRET") || "tolpllbe";
    const from = Deno.env.get("HUBTEL_SENDER_ID") || "Instiy";

    const basicAuth = 'Basic ' + btoa(`${clientId}:${clientSecret}`);
    const response = await fetch('https://smsc.hubtel.com/v1/messages/send', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': basicAuth
      },
      body: JSON.stringify({
        from: from,
        to: to,
        content: content
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Hubtel responded with ${response.status}: ${errorText}`);
    }

    const data = await response.json();
    return new Response(
      JSON.stringify({ success: true, data }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("SMS send error:", error);
    return new Response(
      JSON.stringify({ error: error.message || "Failed to send SMS" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
