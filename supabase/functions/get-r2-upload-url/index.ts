import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const R2_ENDPOINT = Deno.env.get("R2_ENDPOINT")!;
const R2_ACCESS_KEY_ID = Deno.env.get("R2_ACCESS_KEY_ID")!;
const R2_SECRET_ACCESS_KEY = Deno.env.get("R2_SECRET_ACCESS_KEY")!;
const R2_BUCKET_NAME = Deno.env.get("R2_BUCKET_NAME")!;
const R2_PUBLIC_URL = Deno.env.get("R2_PUBLIC_URL")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

async function hmacSha256(key: Uint8Array, data: string): Promise<Uint8Array> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    key,
    { name: "HMAC", hash: { name: "SHA-256" } },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(data));
  return new Uint8Array(sig);
}

function toHex(buf: Uint8Array): string {
  return Array.from(buf).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256Hex(data: Uint8Array): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", data);
  return toHex(new Uint8Array(hash));
}

function getContentType(extension: string): string {
  const types: Record<string, string> = {
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    png: "image/png",
    gif: "image/gif",
    webp: "image/webp",
    mp4: "video/mp4",
    mov: "video/quicktime",
    webm: "video/webm",
    pdf: "application/pdf",
    m4a: "audio/mp4",
  };
  return types[extension.toLowerCase()] || "application/octet-stream";
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } }
    );

    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const { folder, extension, contentType: providedContentType } = body;

    if (!folder || !extension) {
      return new Response(JSON.stringify({ error: "Missing required fields: folder, extension" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const allowedFolderPrefixes = [
      "uploads",
      "verifications",
      "reviews",
      "avatars",
      "products",
      "banners",
      "chat-media",
      "carousel",
    ];
    const folderPrefix = folder.split("/")[0];
    if (!allowedFolderPrefixes.includes(folderPrefix)) {
      return new Response(JSON.stringify({ error: "Invalid folder" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const allowedExtensions = ["jpg", "jpeg", "png", "gif", "webp", "mp4", "mov", "webm", "pdf", "m4a"];
    if (!allowedExtensions.includes(extension.toLowerCase())) {
      return new Response(JSON.stringify({ error: "Invalid file extension" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const contentType = providedContentType || getContentType(extension);

    const fileName = crypto.randomUUID().replace(/-/g, "") + crypto.randomUUID().replace(/-/g, "").slice(0, 16);
    const key = `${folder}/${fileName}.${extension}`;

    const endpointUrl = new URL(R2_ENDPOINT);
    const host = endpointUrl.host;
    const region = "auto";
    const service = "s3";

    const now = new Date();
    const y = now.getUTCFullYear();
    const m = String(now.getUTCMonth() + 1).padStart(2, "0");
    const d = String(now.getUTCDate()).padStart(2, "0");
    const h = String(now.getUTCHours()).padStart(2, "0");
    const mi = String(now.getUTCMinutes()).padStart(2, "0");
    const s = String(now.getUTCSeconds()).padStart(2, "0");
    const dateStamp = `${y}${m}${d}`;
    const amzDate = `${dateStamp}T${h}${mi}${s}Z`;

    const canonicalUri = `/${R2_BUCKET_NAME}/${key}`;
    const canonicalHeaders = `host:${host}\nx-amz-content-sha256:UNSIGNED-PAYLOAD\nx-amz-date:${amzDate}\n`;
    const signedHeaders = "host;x-amz-content-sha256;x-amz-date";

    const credentialScope = `${dateStamp}/${region}/${service}/aws4_request`;
    const canonicalRequest = `PUT\n${canonicalUri}\n\n${canonicalHeaders}\n${signedHeaders}\nUNSIGNED-PAYLOAD`;
    const canonicalRequestHash = await sha256Hex(new TextEncoder().encode(canonicalRequest));

    const stringToSign = `AWS4-HMAC-SHA256\n${amzDate}\n${credentialScope}\n${canonicalRequestHash}`;

    const kDate = await hmacSha256(new TextEncoder().encode(`AWS4${R2_SECRET_ACCESS_KEY}`), dateStamp);
    const kRegion = await hmacSha256(kDate, region);
    const kService = await hmacSha256(kRegion, service);
    const kSigning = await hmacSha256(kService, "aws4_request");

    const signatureBuf = await hmacSha256(kSigning, stringToSign);
    const signature = toHex(signatureBuf);

    const authorization = `AWS4-HMAC-SHA256 Credential=${R2_ACCESS_KEY_ID}/${credentialScope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;

    const uploadUrl = `${R2_ENDPOINT}/${R2_BUCKET_NAME}/${key}`;
    const publicUrl = `${R2_PUBLIC_URL}/${key}`;

    return new Response(
      JSON.stringify({
        uploadUrl,
        publicUrl,
        key,
        headers: {
          Authorization: authorization,
          "x-amz-date": amzDate,
          "x-amz-content-sha256": "UNSIGNED-PAYLOAD",
          "Content-Type": contentType,
          Host: host,
        },
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("R2 presigned URL error:", error);
    return new Response(JSON.stringify({ error: "Failed to generate upload URL" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});