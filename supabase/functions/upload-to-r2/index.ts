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

const MAX_FILE_SIZE = 50 * 1024 * 1024; // 50MB
const ALLOWED_EXTENSIONS = ["jpg", "jpeg", "png", "gif", "webp", "mp4", "mov", "webm", "pdf", "m4a", "wav"];
const ALLOWED_FOLDERS = ["uploads", "verifications", "reviews", "avatars", "products", "services", "banners", "chat-media", "reports", "recordings"];

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
    wav: "audio/wav",
  };
  return types[extension.toLowerCase()] || "application/octet-stream";
}

function sanitizeError(error: unknown): string {
  console.error("R2 upload error:", error);
  return "Failed to upload file";
}

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

    const formData = await req.formData();
    const file = formData.get("file") as File;
    const folder = (formData.get("folder") as string) || "uploads";

    if (!file) {
      return new Response(JSON.stringify({ error: "No file provided" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (file.size > MAX_FILE_SIZE) {
      return new Response(JSON.stringify({ error: "File too large (max 50MB)" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const fileExt = file.name.split(".").pop() || "jpg";
    if (!ALLOWED_EXTENSIONS.includes(fileExt.toLowerCase())) {
      return new Response(JSON.stringify({ error: "Invalid file type" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const folderPrefix = folder.split("/")[0];
    if (!ALLOWED_FOLDERS.includes(folderPrefix)) {
      return new Response(JSON.stringify({ error: "Invalid folder" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const randomName = crypto.randomUUID().replace(/-/g, "") + crypto.randomUUID().replace(/-/g, "").slice(0, 16);
    const key = `${folder}/${randomName}.${fileExt}`;

    const arrayBuffer = await file.arrayBuffer();
    const body = new Uint8Array(arrayBuffer);

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

    const payloadHash = await sha256Hex(body);
    const canonicalUri = `/${R2_BUCKET_NAME}/${key}`;
    const canonicalHeaders = `host:${host}\nx-amz-content-sha256:${payloadHash}\nx-amz-date:${amzDate}\n`;
    const signedHeaders = "host;x-amz-content-sha256;x-amz-date";

    const canonicalRequest = `PUT\n${canonicalUri}\n\n${canonicalHeaders}\n${signedHeaders}\n${payloadHash}`;
    const canonicalRequestHash = await sha256Hex(new TextEncoder().encode(canonicalRequest));

    const credentialScope = `${dateStamp}/${region}/${service}/aws4_request`;
    const stringToSign = `AWS4-HMAC-SHA256\n${amzDate}\n${credentialScope}\n${canonicalRequestHash}`;

    const kDate = await hmacSha256(new TextEncoder().encode(`AWS4${R2_SECRET_ACCESS_KEY}`), dateStamp);
    const kRegion = await hmacSha256(kDate, region);
    const kService = await hmacSha256(kRegion, service);
    const kSigning = await hmacSha256(kService, "aws4_request");

    const signatureBuf = await hmacSha256(kSigning, stringToSign);
    const signature = toHex(signatureBuf);

    const authorization = `AWS4-HMAC-SHA256 Credential=${R2_ACCESS_KEY_ID}/${credentialScope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;

    const response = await fetch(`${R2_ENDPOINT}/${R2_BUCKET_NAME}/${key}`, {
      method: "PUT",
      headers: {
        Authorization: authorization,
        "x-amz-date": amzDate,
        "x-amz-content-sha256": payloadHash,
        "Content-Type": getContentType(fileExt),
        "Content-Length": body.length.toString(),
        Host: host,
      },
      body: body,
    });

    if (!response.ok) {
      const errorText = await response.text();
      return new Response(JSON.stringify({ error: `Upload failed: ${response.status}` }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const publicUrl = `${R2_PUBLIC_URL}/${key}`;

    return new Response(JSON.stringify({ url: publicUrl }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: sanitizeError(error) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});