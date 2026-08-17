import { jwtVerify, createRemoteJWKSet } from 'jose';

export interface AuthResult {
  userId: string | null;
  isAuthenticated: boolean;
}

// Cache the JWKS set (jose handles TTL internally — 10 min from Supabase)
let jwks: ReturnType<typeof createRemoteJWKSet> | null = null;

function getJwks(supabaseUrl: string): ReturnType<typeof createRemoteJWKSet> {
  if (!jwks) {
    const url = new URL(`${supabaseUrl}/auth/v1/.well-known/jwks.json`);
    jwks = createRemoteJWKSet(url);
  }
  return jwks;
}

export async function verifyAuth(
  request: Request,
  env: Pick<Env, 'SUPABASE_URL' | 'SUPABASE_ANON_KEY' | 'SUPABASE_SERVICE_ROLE_KEY'>
): Promise<AuthResult> {
  const authHeader = request.headers.get('Authorization');
  if (!authHeader) {
    return { userId: null, isAuthenticated: false };
  }

  const token = authHeader.replace('Bearer ', '').trim();

  // Check if it's the anon key or service role key (not JWTs)
  if (token === env.SUPABASE_ANON_KEY) {
    return { userId: null, isAuthenticated: false };
  }
  if (env.SUPABASE_SERVICE_ROLE_KEY && token === env.SUPABASE_SERVICE_ROLE_KEY) {
    return { userId: null, isAuthenticated: true };
  }

  // Verify as JWT using Supabase's JWKS endpoint (ES256 asymmetric keys)
  try {
    const keySet = getJwks(env.SUPABASE_URL);
    const { payload } = await jwtVerify(token, keySet, {
      issuer: `${env.SUPABASE_URL}/auth/v1`,
    });
    return { userId: payload.sub || null, isAuthenticated: true };
  } catch {
    return { userId: null, isAuthenticated: false };
  }
}
