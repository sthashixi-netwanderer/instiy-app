function sanitizeError(error: unknown): string {
  console.error('Push Notification Function error:', error);
  return 'Failed to process push notifications';
}

async function getAccessToken(serviceAccount: { client_email: string; private_key: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const payload = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  };

  const encoder = new TextEncoder();
  const signingInput = `${btoa(JSON.stringify(header)).replace(/=/g, '')}.${btoa(JSON.stringify(payload)).replace(/=/g, '')}`;

  const keyData = serviceAccount.private_key
    .replace(/-----BEGIN [A-Z ]+-----/g, '')
    .replace(/-----END [A-Z ]+-----/g, '')
    .replace(/\\n/g, '')
    .replace(/\s/g, '');

  const binaryDer = Uint8Array.from(atob(keyData), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryDer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  );

  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, encoder.encode(signingInput));
  const signedInput = `${signingInput}.${btoa(String.fromCharCode(...new Uint8Array(signature))).replace(/=/g, '')}`;

  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${signedInput}`,
  });

  const tokenData = (await tokenRes.json()) as { access_token?: string };
  if (!tokenData.access_token) {
    throw new Error('Failed to get access token from Google');
  }
  return tokenData.access_token;
}

export async function handlePushNotifications(request: Request, env: Env, corsHeaders: Record<string, string>): Promise<Response> {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const payload = (await request.json()) as Record<string, unknown>;

    const record = (payload.record || payload) as Record<string, unknown>;
    if (!record || !record.user_id) {
      return new Response(JSON.stringify({ error: 'Missing recipient user_id in record' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const title = (record.title as string) || 'New Notification';
    const body = (record.body as string) || '';
    const type = (record.type as string) || 'notification';

    // Fetch user push tokens via Supabase REST API
    const tokenRes = await fetch(
      `${env.SUPABASE_URL}/rest/v1/user_push_tokens?user_id=eq.${record.user_id}&select=token`,
      {
        headers: {
          apikey: env.SUPABASE_ANON_KEY,
          Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY || ''}`,
        },
      }
    );

    const tokenRecords = (await tokenRes.json()) as Array<{ token: string }>;
    if (!tokenRecords || tokenRecords.length === 0) {
      return new Response(JSON.stringify({ message: 'No active FCM tokens found for this user.' }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const serviceAccountKeyStr = env.FCM_SERVICE_ACCOUNT_KEY;
    if (!serviceAccountKeyStr) {
      return new Response(JSON.stringify({ error: 'FCM service not configured' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    let serviceAccount: { client_email: string; private_key: string; project_id: string };
    try {
      serviceAccount = JSON.parse(serviceAccountKeyStr);
    } catch {
      return new Response(JSON.stringify({ error: 'Invalid FCM configuration' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const projectId = serviceAccount.project_id;
    if (!projectId) {
      return new Response(JSON.stringify({ error: 'Invalid FCM configuration' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const accessToken = await getAccessToken(serviceAccount);

    const stringData: Record<string, string> = {};
    if (record.data && typeof record.data === 'object') {
      for (const [key, val] of Object.entries(record.data as Record<string, unknown>)) {
        stringData[key] = typeof val === 'object' ? JSON.stringify(val) : String(val);
      }
    }
    stringData['id'] = String(record.id);
    stringData['type'] = String(type);
    stringData['click_action'] = 'FLUTTER_NOTIFICATION_CLICK';

    const results: Array<{ token: string; success: boolean; messageId?: string; error?: unknown }> = [];
    for (const { token } of tokenRecords) {
      const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

      const fcmPayload = {
        message: {
          token: token,
          notification: { title, body },
          data: stringData,
          android: {
            priority: 'high',
            notification: {
              sound: 'default',
              click_action: 'FLUTTER_NOTIFICATION_CLICK',
              // Branded tray icon: white logo silhouette shipped in the
              // Android res/drawable-* buckets (falls back to the manifest
              // default when absent).
              icon: 'ic_notification',
              color: '#7C3AED',
            },
          },
          apns: {
            payload: { aps: { sound: 'default', 'content-available': 1 } },
          },
        },
      };

      try {
        const response = await fetch(fcmUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify(fcmPayload),
        });

        const resBody = (await response.json()) as { name?: string; error?: { status?: string; message?: string } };
        if (!response.ok) {
          if (resBody.error && (resBody.error.status === 'UNREGISTERED' || resBody.error.message?.includes('not registered'))) {
            await fetch(
              `${env.SUPABASE_URL}/rest/v1/user_push_tokens?token=eq.${token}`,
              {
                method: 'DELETE',
                headers: {
                  apikey: env.SUPABASE_ANON_KEY,
                  Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY || ''}`,
                },
              }
            );
          }
          results.push({ token, success: false, error: resBody });
        } else {
          results.push({ token, success: true, messageId: resBody.name });
        }
      } catch {
        results.push({ token, success: false, error: 'Network error' });
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        sentCount: results.filter((r) => r.success).length,
        failCount: results.filter((r) => !r.success).length,
        results,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: sanitizeError(error) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
}
