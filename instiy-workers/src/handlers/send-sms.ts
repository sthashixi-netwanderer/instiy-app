import { verifyAuth } from '../middleware/auth';

const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function isValidPhoneNumber(phone: string): boolean {
  return /^\+?[1-9]\d{1,14}$/.test(phone.replace(/\s/g, ''));
}

export async function handleSendSms(request: Request, env: Env, _corsHeaders: Record<string, string>): Promise<Response> {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const apikey = request.headers.get('apikey');
  const authHeader = request.headers.get('Authorization');
  const token = authHeader ? authHeader.replace('Bearer ', '').trim() : '';

  const isAnonKey = apikey === env.SUPABASE_ANON_KEY || token === env.SUPABASE_ANON_KEY;
  const isServiceKey = !!env.SUPABASE_SERVICE_ROLE_KEY && token === env.SUPABASE_SERVICE_ROLE_KEY;

  if (!isAnonKey && !isServiceKey) {
    const auth = await verifyAuth(request, env);
    if (!auth.isAuthenticated) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
  }

  try {
    const body = (await request.json()) as { to?: string; content?: string };
    const { to, content } = body;

    if (!to || !content) {
      return new Response(JSON.stringify({ error: 'Missing required fields: to, content' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const cleanTo = to.replace(/\s/g, '');
    if (!isValidPhoneNumber(cleanTo)) {
      return new Response(JSON.stringify({ error: 'Invalid phone number format' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Hubtel expects international format WITHOUT leading '+' or '00' (e.g. 233244000000)
    const hubtelTo = cleanTo.replace(/^\+/, '').replace(/^00/, '');

    if (content.length > 1600) {
      return new Response(JSON.stringify({ error: 'Message too long (max 1600 characters)' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (!env.HUBTEL_CLIENT_ID || !env.HUBTEL_CLIENT_SECRET) {
      return new Response(JSON.stringify({ error: 'SMS service not configured' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const basicAuth = 'Basic ' + btoa(`${env.HUBTEL_CLIENT_ID}:${env.HUBTEL_CLIENT_SECRET}`);
    const response = await fetch('https://smsc.hubtel.com/v1/messages/send', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: basicAuth,
      },
      body: JSON.stringify({
        from: env.HUBTEL_SENDER_ID || 'Instiy',
        to: hubtelTo,
        content,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`Hubtel responded with ${response.status}: ${errorText}`);
      return new Response(JSON.stringify({ error: 'Failed to send SMS', details: errorText, hubtelStatus: response.status }), {
        status: response.status >= 400 && response.status < 500 ? 400 : 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const data = (await response.json()) as Record<string, unknown>;
    return new Response(JSON.stringify({ success: true, data }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('SMS send error:', error);
    return new Response(JSON.stringify({ error: 'Failed to send SMS' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}
