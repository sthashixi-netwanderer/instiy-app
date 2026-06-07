import { supabase } from './supabaseClient';

// Upload file to R2 via Supabase Edge Function (avoids CORS issues)
export async function uploadToR2(file: File, folder: string): Promise<string> {
  const formData = new FormData();
  formData.append('file', file);
  formData.append('folder', folder);

  const { data: { session } } = await supabase.auth.getSession();

  const response = await fetch(
    'https://wqasatrxqinkfaafgnli.supabase.co/functions/v1/upload-to-r2',
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${session?.access_token || ''}`,
      },
      body: formData,
    }
  );

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || 'Upload failed');
  }

  const { url } = await response.json();
  return url;
}
