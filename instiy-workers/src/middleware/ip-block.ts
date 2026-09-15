// Blocklist check for worker routes. Looks up blocked_ips via the service
// role with a 60s in-memory cache per IP; fails OPEN when the lookup errors
// (an unavailable database must not take the whole API down). Only ever
// called with server-derived IPs (CF-Connecting-IP), never client claims.

interface BlockCheck {
  blocked: boolean;
  reason: string;
}

const cache = new Map<string, BlockCheck & { at: number }>();
const CACHE_TTL_MS = 60_000;

export async function isIpBlocked(
  request: Request,
  env: Pick<Env, 'SUPABASE_URL' | 'SUPABASE_SERVICE_ROLE_KEY'>
): Promise<BlockCheck> {
  const ip =
    request.headers.get('CF-Connecting-IP') ||
    request.headers.get('X-Forwarded-For')?.split(',')[0]?.trim() ||
    '';
  if (!ip) return { blocked: false, reason: '' };

  const hit = cache.get(ip);
  if (hit && Date.now() - hit.at < CACHE_TTL_MS) {
    return { blocked: hit.blocked, reason: hit.reason };
  }

  const allowAll: BlockCheck = { blocked: false, reason: '' };
  try {
    const key = env.SUPABASE_SERVICE_ROLE_KEY || '';
    const res = await fetch(
      `${env.SUPABASE_URL}/rest/v1/blocked_ips?select=reason&ip_address=eq.${encodeURIComponent(ip)}`,
      { headers: { apikey: key, Authorization: `Bearer ${key}` } }
    );
    if (!res.ok) return allowAll; // fail open
    const rows = (await res.json()) as { reason?: string }[];
    const result: BlockCheck =
      rows.length > 0
        ? { blocked: true, reason: (rows[0].reason as string) || '' }
        : allowAll;
    if (cache.size > 5000) cache.clear();
    cache.set(ip, { ...result, at: Date.now() });
    return result;
  } catch {
    return allowAll;
  }
}

export function blockedResponse(
  reason: string,
  corsHeaders: Record<string, string>
): Response {
  return new Response(JSON.stringify({ error: 'ip_blocked', reason }), {
    status: 403,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
