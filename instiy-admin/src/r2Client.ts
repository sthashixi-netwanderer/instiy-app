import { supabase } from './supabaseClient';

// Upload file to R2 via the Cloudflare Worker proxy (same flow as the mobile app).
// Presigned URLs can't be used from a browser — R2 endpoints don't send CORS headers.
export async function uploadToR2(file: File, folder: string): Promise<string> {
  const { data: { session } } = await supabase.auth.getSession();
  const accessToken = session?.access_token;
  if (!accessToken) throw new Error('Not authenticated');

  const extension = file.name.split('.').pop() || 'jpg';

  const response = await fetch('https://api.instiy.com/functions/v1/upload-to-r2', {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': file.type || 'application/octet-stream',
      'X-R2-Folder': folder,
      'X-R2-Extension': extension,
    },
    body: file,
  });

  if (!response.ok) {
    const error = await response.json().catch(() => null);
    throw new Error(error?.error || `Upload failed: ${response.status}`);
  }

  const { publicUrl } = await response.json();
  return publicUrl;
}
