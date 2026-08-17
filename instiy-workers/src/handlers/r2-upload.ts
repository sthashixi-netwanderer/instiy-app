function getContentType(extension: string): string {
  const types: Record<string, string> = {
    jpg: 'image/jpeg',
    jpeg: 'image/jpeg',
    png: 'image/png',
    gif: 'image/gif',
    webp: 'image/webp',
    mp4: 'video/mp4',
    mov: 'video/quicktime',
    webm: 'video/webm',
    pdf: 'application/pdf',
    m4a: 'audio/mp4',
  };
  return types[extension.toLowerCase()] || 'application/octet-stream';
}

// Worker proxy upload — client sends file bytes, Worker puts in R2
// This replaces the old presigned URL approach (R2 bindings don't support CORS presigned URLs)
export async function handleR2UploadProxy(request: Request, env: Env, corsHeaders: Record<string, string>): Promise<Response> {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const contentType = request.headers.get('Content-Type') || 'application/octet-stream';
    const folder = request.headers.get('X-R2-Folder') || 'uploads';
    const extension = request.headers.get('X-R2-Extension') || 'jpg';

    const allowedFolderPrefixes = ['uploads', 'verifications', 'reviews', 'avatars', 'products', 'banners', 'chat-media'];
    const folderPrefix = folder.split('/')[0];
    if (!allowedFolderPrefixes.includes(folderPrefix)) {
      return new Response(JSON.stringify({ error: 'Invalid folder' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const allowedExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'mov', 'webm', 'pdf', 'm4a'];
    if (!allowedExtensions.includes(extension.toLowerCase())) {
      return new Response(JSON.stringify({ error: 'Invalid file extension' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const fileName = crypto.randomUUID().replace(/-/g, '') + crypto.randomUUID().replace(/-/g, '').slice(0, 16);
    const key = `${folder}/${fileName}.${extension}`;

    const body = await request.arrayBuffer();

    // Direct R2 binding upload
    await env.R2_BUCKET.put(key, body, {
      httpMetadata: { contentType },
    });

    const publicUrl = `${env.R2_PUBLIC_URL}/${key}`;

    return new Response(
      JSON.stringify({ uploadUrl: publicUrl, publicUrl, key, headers: { 'Content-Type': contentType } }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('R2 upload error:', error);
    return new Response(JSON.stringify({ error: 'Failed to upload file' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// Delete R2 object
export async function handleDeleteR2Object(request: Request, env: Env, corsHeaders: Record<string, string>): Promise<Response> {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = (await request.json()) as { key?: string };
    const key = body.key;

    if (!key) {
      return new Response(JSON.stringify({ error: 'Missing required field: key' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    await env.R2_BUCKET.delete(key);

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('R2 delete error:', error);
    return new Response(JSON.stringify({ success: false, error: 'Failed to delete object' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}
