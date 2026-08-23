import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import nodemailer from "npm:nodemailer";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function isValidEmail(email: string): boolean {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

function sanitizeError(error: unknown): string {
  console.error("Email send error:", error);
  return "Failed to send email";
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

    // Two auth paths:
    //  1. Server-to-server (pg_net triggers): publishable key for the
    //     gateway + x-notify-secret, which must match the RLS-locked
    //     _push_trigger_config.notify_secret row (read via the
    //     auto-injected service-role client).
    //  2. App clients: a user JWT, verified via getUser().
    const notifySecret = req.headers.get("x-notify-secret");
    let authorized = false;

    if (notifySecret) {
      const admin = createClient(
        Deno.env.get("SUPABASE_URL") ?? "",
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
      );
      const { data: secretRow } = await admin
        .from("_push_trigger_config")
        .select("value")
        .eq("key", "notify_secret")
        .maybeSingle();
      authorized = !!secretRow && notifySecret === secretRow.value;

      if (!authorized) {
        return new Response(
          JSON.stringify({ error: "Unauthorized" }),
          { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    } else {
      const supabase = createClient(
        Deno.env.get("SUPABASE_URL") ?? "",
        Deno.env.get("SUPABASE_ANON_KEY") ?? "",
        { global: { headers: { Authorization: authHeader } } }
      );

      const {
        data: { user },
      } = await supabase.auth.getUser();

      if (!user) {
        return new Response(
          JSON.stringify({ error: "Unauthorized" }),
          { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    const body = await req.json();
    const { to, subject, html } = body;

    if (!to || !subject || !html) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: to, subject, html" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!isValidEmail(to)) {
      return new Response(
        JSON.stringify({ error: "Invalid email address" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (subject.length > 200) {
      return new Response(
        JSON.stringify({ error: "Subject too long (max 200 characters)" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (html.length > 50000) {
      return new Response(
        JSON.stringify({ error: "HTML content too large (max 50KB)" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log(`Sending email to ${to} with subject: "${subject}"`);

    const host = Deno.env.get("SMTP_HOST") ?? "";
    const port = Number(Deno.env.get("SMTP_PORT") ?? "587");
    const secure = Deno.env.get("SMTP_SECURE")?.toLowerCase() === "true";

    if (!host) {
      return new Response(
        JSON.stringify({ error: "Email service not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const transporter = nodemailer.createTransport({
      host,
      port,
      secure,
      auth: {
        user: Deno.env.get("SMTP_USER") ?? "",
        pass: Deno.env.get("SMTP_PASS") ?? "",
      },
      connectionTimeout: 10000,
    });

    const fromEmail = Deno.env.get("SMTP_FROM") ?? "Instiy <no-reply@instiy.com>";

    await transporter.sendMail({
      from: fromEmail,
      to,
      subject,
      html,
    });

    return new Response(
      JSON.stringify({ success: true, message: "Email sent successfully" }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: sanitizeError(error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});