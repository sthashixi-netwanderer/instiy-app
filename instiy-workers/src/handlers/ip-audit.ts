import { verifyAuth } from '../middleware/auth';
import { isIpBlocked } from '../middleware/ip-block';

const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

interface SessionAuditBody {
  eventType?: string;
  platform?: string;
  osVersion?: string;
  deviceModel?: string;
  appVersion?: string;
}

function svcHeaders(env: Env): Record<string, string> {
  const key = env.SUPABASE_SERVICE_ROLE_KEY || '';
  return { apikey: key, Authorization: `Bearer ${key}` };
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// Records one audit event for the caller (identified by IP + optional JWT)
// and reports whether that IP is blocked. The client NEVER supplies its own
// IP — CF-Connecting-IP, request.cf country and the User-Agent header are
// all read server-side. Device fields come from the app payload.
export async function handleSessionAudit(
  request: Request,
  env: Env,
  _corsHeaders: Record<string, string>
): Promise<Response> {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (request.method !== 'POST') {
    return json({ error: 'method_not_allowed' }, 405);
  }

  let body: SessionAuditBody = {};
  try {
    body = (await request.json()) as SessionAuditBody;
  } catch {
    // empty body is fine — falls through to a 'session' event
  }
  const eventType = body.eventType === 'login' ? 'login' : 'session';

  const auth = await verifyAuth(request, env);
  const ip =
    request.headers.get('CF-Connecting-IP') ||
    request.headers.get('X-Forwarded-For')?.split(',')[0]?.trim() ||
    '';
  const userAgent = request.headers.get('User-Agent') || '';
  const cf = (request as Request & { cf?: { country?: string } }).cf;
  const country = cf?.country || null;

  const { blocked, reason } = await isIpBlocked(request, env);

  // Insert with a 6h dedup window on (ip, user, type, user-agent) so retry
  // loops can't flood the table. Audit failures never break the response.
  let recorded = false;
  if (ip) {
    try {
      const since = new Date(Date.now() - 6 * 60 * 60 * 1000).toISOString();
      const userFilter = auth.userId
        ? `user_id=eq.${encodeURIComponent(auth.userId)}`
        : 'user_id=is.null';
      const uaFilter = userAgent
        ? `&user_agent=eq.${encodeURIComponent(userAgent)}`
        : '';
      const dupUrl =
        `${env.SUPABASE_URL}/rest/v1/ip_events?select=id&limit=1` +
        `&ip_address=eq.${encodeURIComponent(ip)}` +
        `&event_type=eq.${eventType}` +
        `&${userFilter}${uaFilter}` +
        `&created_at=gte.${since}`;
      const dupRes = await fetch(dupUrl, { headers: svcHeaders(env) });
      const dups = dupRes.ok ? ((await dupRes.json()) as unknown[]) : [];
      if (dups.length === 0) {
        const insRes = await fetch(`${env.SUPABASE_URL}/rest/v1/ip_events`, {
          method: 'POST',
          headers: {
            ...svcHeaders(env),
            'Content-Type': 'application/json',
            Prefer: 'return=minimal',
          },
          body: JSON.stringify({
            ip_address: ip,
            user_id: auth.userId,
            event_type: eventType,
            user_agent: userAgent,
            platform: body.platform ?? null,
            os_version: body.osVersion ?? null,
            device_model: body.deviceModel ?? null,
            app_version: body.appVersion ?? null,
            country,
          }),
        });
        recorded = insRes.ok;
      }
    } catch {
      // swallow — see comment above
    }
  }

  return json({ ip, blocked, reason, country, recorded }, 200);
}
