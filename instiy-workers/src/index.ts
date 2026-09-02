import { handleGetSecrets } from './handlers/get-secrets';
import { handleShareProduct } from './handlers/share-product';
import { handlePaystack } from './handlers/paystack';
import { handleSendSms } from './handlers/send-sms';
import { handlePushNotifications } from './handlers/push-notifications';
import { handleR2UploadProxy, handleDeleteR2Object } from './handlers/r2-upload';
import { handleDeepLinks } from './handlers/deep-links';

// Env interface is globally defined in worker-configuration.d.ts

const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-r2-folder, x-r2-extension',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === 'OPTIONS') {
      return new Response('ok', { headers: corsHeaders });
    }

    const url = new URL(request.url);
    const path = url.pathname;

    // Health check
    if (path === '/' || path === '/health') {
      return new Response(JSON.stringify({ status: 'ok', service: 'instiy-api' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Auth callback proxy — Google OAuth hits this, Worker forwards to Supabase
    if (path.startsWith('/auth/v1/')) {
      const targetUrl = `${env.SUPABASE_URL}${path}${url.search}`;
      const proxyHeaders = new Headers(request.headers);
      proxyHeaders.set('host', new URL(env.SUPABASE_URL).host);
      return fetch(new Request(targetUrl, {
        method: request.method,
        headers: proxyHeaders,
        body: request.body,
      }));
    }

    // Deep links & verification files (no /functions/v1 prefix)
    if (path.startsWith('/.well-known/') || path.startsWith('/product/') || path.startsWith('/products/') || path.startsWith('/store/') || path === '/referral' || path.startsWith('/referral/')) {
      return handleDeepLinks(request, env);
    }

    // API routes under /functions/v1/
    if (path.startsWith('/functions/v1/')) {
      const route = path.replace('/functions/v1/', '');

      // Share product — public, no auth required
      if (route === 'share-product' || route.startsWith('share-product/')) {
        return handleShareProduct(request, env, corsHeaders);
      }

      // Proxy send-email and delete-user to Supabase
      if (route === 'send-email' || route === 'delete-user') {
        const supabaseUrl = `${env.SUPABASE_URL}/functions/v1/${route}`;
        const proxyRequest = new Request(supabaseUrl, {
          method: request.method,
          headers: request.headers,
          body: request.body,
        });
        return fetch(proxyRequest);
      }

      switch (route) {
        case 'get-secrets':
          return handleGetSecrets(request, env, corsHeaders);
        case 'upload-to-r2':
          return handleR2UploadProxy(request, env, corsHeaders);
        case 'delete-r2-object':
          return handleDeleteR2Object(request, env, corsHeaders);
        case 'paystack':
        case 'paystack/initialize':
        case 'paystack/verify':
          return handlePaystack(request, env, corsHeaders);
        case 'send-sms':
          return handleSendSms(request, env, corsHeaders);
        case 'push-notifications':
          return handlePushNotifications(request, env, corsHeaders);
        default:
          return new Response(JSON.stringify({ error: 'Not found' }), {
            status: 404,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
      }
    }

    return new Response(JSON.stringify({ error: 'Not found' }), {
      status: 404,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  },
};
