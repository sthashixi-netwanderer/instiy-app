import { verifyAuth } from '../middleware/auth';

const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const PAYSTACK_API = 'https://api.paystack.co';

function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

export async function handlePaystack(request: Request, env: Env, _corsHeaders: Record<string, string>): Promise<Response> {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const auth = await verifyAuth(request, env);
  if (!auth.isAuthenticated) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  try {
    const url = new URL(request.url);
    const path = url.pathname.replace('/functions/v1/paystack', '');
    const body = (await request.json()) as Record<string, unknown>;

    if (path === '/initialize') {
      const { email, amount, reference, metadata } = body as { email?: string; amount?: string | number; reference?: string; metadata?: Record<string, unknown> };

      if (!email || !amount) {
        return new Response(JSON.stringify({ error: 'Missing required fields: email, amount' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      if (!isValidEmail(email)) {
        return new Response(JSON.stringify({ error: 'Invalid email address' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const parsedAmount = parseInt(String(amount));
      if (isNaN(parsedAmount) || parsedAmount <= 0) {
        return new Response(JSON.stringify({ error: 'Invalid amount' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const paystackRes = await fetch(`${PAYSTACK_API}/transaction/initialize`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${env.PAYSTACK_SECRET_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          email,
          amount: parsedAmount,
          reference,
          metadata: {
            ...metadata,
            initiated_from: 'instiy_mobile',
          },
        }),
      });

      const data = (await paystackRes.json()) as Record<string, unknown>;
      return new Response(JSON.stringify(data), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (path === '/verify') {
      const { reference } = body as { reference?: string };

      if (!reference) {
        return new Response(JSON.stringify({ error: 'Missing required field: reference' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const paystackRes = await fetch(`${PAYSTACK_API}/transaction/verify/${reference}`, {
        headers: {
          Authorization: `Bearer ${env.PAYSTACK_SECRET_KEY}`,
        },
      });

      const data = (await paystackRes.json()) as Record<string, unknown>;
      return new Response(JSON.stringify(data), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ error: 'Not found' }), {
      status: 404,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Paystack error:', error);
    return new Response(JSON.stringify({ error: 'Payment service error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}
