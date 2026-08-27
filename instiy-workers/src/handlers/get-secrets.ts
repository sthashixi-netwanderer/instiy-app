import { verifyAuth } from '../middleware/auth';

const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

export async function handleGetSecrets(request: Request, env: Env, _corsHeaders: Record<string, string>): Promise<Response> {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // No auth required — this endpoint provides client-side config values.
  // Called at app startup before user login.
  //
  // Exception: paystack_secret_key is the client-side checkout key required
  // by pay_with_paystack (it initializes transactions from the app). It is
  // returned ONLY for requests carrying a valid user JWT — never anonymously.
  const auth = await verifyAuth(request, env);

  return new Response(
    JSON.stringify({
      r2_endpoint: env.R2_ENDPOINT || 'https://220fcabda76df0d761a0e57dd6d1552f.r2.cloudflarestorage.com',
      r2_access_key_id: env.R2_ACCESS_KEY_ID || '',
      r2_bucket_name: env.R2_BUCKET_NAME,
      r2_public_url: env.R2_PUBLIC_URL,
      hubtel_client_id: env.HUBTEL_CLIENT_ID || '',
      hubtel_client_secret: env.HUBTEL_CLIENT_SECRET || '',
      hubtel_sender_id: env.HUBTEL_SENDER_ID || '',
      paystack_public_key: env.PAYSTACK_PUBLIC_KEY || '',
      paystack_secret_key: auth.isAuthenticated ? (env.PAYSTACK_SECRET_KEY || '') : '',
      supabase_redirect_url: env.REDIRECT_URL || '',
      giphy_api_key: env.GIPHY_API_KEY || '',
      app_version: env.APP_VERSION || '',
      turn_url: env.TURN_URL || '',
      turn_username: env.TURN_USERNAME || '',
      turn_credential: env.TURN_CREDENTIAL || '',
    }),
    {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    }
  );
}
