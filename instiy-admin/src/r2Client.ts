import { supabase } from './supabaseClient';

// Upload file to R2 via Supabase Edge Function using presigned URLs
export async function uploadToR2(file: File, folder: string): Promise<string> {
  const { data: { session } } = await supabase.auth.getSession();
  const accessToken = session?.access_token;
  if (!accessToken) throw new Error('Not authenticated');

  const extension = file.name.split('.').pop() || 'jpg';

  const presignedResponse = await fetch(
    'https://api.instiy.com/functions/v1/get-r2-upload-url',
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ folder, extension }),
    }
  );

  if (!presignedResponse.ok) {
    const error = await presignedResponse.json();
    throw new Error(error.error || 'Failed to get upload URL');
  }

  const { uploadUrl, publicUrl, headers } = await presignedResponse.json();

  const uploadResponse = await fetch(uploadUrl, {
    method: 'PUT',
    headers: headers,
    body: file,
  });

  if (!uploadResponse.ok) {
    throw new Error(`Upload failed: ${uploadResponse.status}`);
  }

  return publicUrl;
}