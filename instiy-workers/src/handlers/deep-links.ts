const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

// Android App Links verification
// https://developer.android.com/training/app-links/verify-android-applinks
// Set the ANDROID_CERT_SHA256 var (comma-separated for multiple fingerprints,
// e.g. upload + play signing keys) to enable verified app links:
//   wrangler secret put ANDROID_CERT_SHA256   (or add to [vars] in wrangler.toml)
// Get it with: keytool -list -v -keystore your-key.keystore -alias your-alias
// Or from Google Play Console → Setup → App signing.
function getAssetLinks(env: Env): object[] {
  const fingerprints = (env.ANDROID_CERT_SHA256 || '')
    .split(',')
    .map((f) => f.trim())
    .filter((f) => f.length > 0);

  return [
    {
      relation: ['delegate_permission/common.handle_all_urls'],
      target: {
        namespace: 'android_app',
        package_name: 'com.instiy',
        ...(fingerprints.length > 0 ? { sha256_cert_fingerprints: fingerprints } : {}),
      },
    },
  ];
}

// iOS Universal Links verification
// https://developer.apple.com/documentation/xcode/supporting-associated-domains
// Set the APPLE_TEAM_ID var to your Apple Developer Team ID to enable
// universal links. The app also needs the applinks:instiy.com associated
// domain entitlement in Xcode.
function getAppleAppSiteAssociation(env: Env): object {
  const teamId = env.APPLE_TEAM_ID || 'TEAM_ID';
  return {
    applinks: {
      apps: [],
      details: [
        {
          appID: `${teamId}.com.instiy`,
          paths: ['/product/*', '/products/*', '/store/*'],
        },
      ],
    },
  };
}

// Product landing page — renders OG tags for social previews, then redirects to app
function getProductLandingHtml(productId: string, product: { title: string; description?: string; price: number; thumbnail_url?: string; image_urls?: string[] }, origin: string): string {
  const title = product.title || 'Product';
  const priceStr = 'GH\u00a2 ' + Number(product.price).toFixed(2);
  const description = product.description || 'Check out this product on Instiy';
  let imageUrl = product.thumbnail_url || '';
  if (!imageUrl && product.image_urls && product.image_urls.length > 0) {
    imageUrl = product.image_urls[0];
  }
  if (!imageUrl) {
    imageUrl = `${origin}/functions/v1/share-product?id=${productId}`;
  }

  // Escape for HTML attributes
  const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

  return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta property="og:title" content="${esc(title)} - Instiy">
    <meta property="og:description" content="${esc(description)} | ${esc(priceStr)}">
    <meta property="og:image" content="${esc(imageUrl)}">
    <meta property="og:type" content="product">
    <meta property="og:url" content="${origin}/product/${productId}">
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="${esc(title)} - Instiy">
    <meta name="twitter:description" content="${esc(description)} | ${esc(priceStr)}">
    <meta name="twitter:image" content="${esc(imageUrl)}">
    <title>${esc(title)} - Instiy</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #FAFAF9; display: flex; justify-content: center; align-items: center; min-height: 100vh; padding: 20px; }
        .card { max-width: 400px; background: white; border-radius: 16px; box-shadow: 0 4px 20px rgba(0,0,0,0.08); overflow: hidden; }
        .image-container { width: 100%; aspect-ratio: 1; background: #F5F5F4; }
        .image-container img { width: 100%; height: 100%; object-fit: cover; }
        .info { padding: 20px; }
        .price { font-size: 24px; font-weight: 700; color: #1C1917; margin-bottom: 8px; }
        .title { font-size: 18px; font-weight: 600; color: #1C1917; margin-bottom: 8px; line-height: 1.3; }
        .description { font-size: 14px; color: #78716C; line-height: 1.5; margin-bottom: 16px; }
        .brand { display: inline-block; background: #F5F5F4; color: #57534E; padding: 4px 12px; border-radius: 20px; font-size: 12px; font-weight: 500; }
    </style>
</head>
<body>
    <div class="card">
        <div class="image-container">
            <img src="${esc(imageUrl)}" alt="${esc(title)}" onerror="this.style.display='none'">
        </div>
        <div class="info">
            <div class="price">${esc(priceStr)}</div>
            <div class="title">${esc(title)}</div>
            <div class="description">${esc(description)}</div>
            <div class="brand">Instiy</div>
        </div>
    </div>
    <script>
        (function() {
            var isAndroid = /Android/i.test(navigator.userAgent);
            var isIOS = /iPhone|iPad|iPod/i.test(navigator.userAgent);
            var productId = "${productId}";
            var deepLink = "io.supabase.instiy://product/" + productId;

            if (isAndroid) {
                var intent = "intent://product/" + productId + "#Intent;scheme=io.supabase.instiy;package=com.instiy;S.browser_fallback_url=" + encodeURIComponent(window.location.href) + ";end;";
                var link = document.createElement("a");
                link.href = intent;
                link.style.display = "none";
                document.body.appendChild(link);
                link.click();
            } else if (isIOS) {
                var link = document.createElement("a");
                link.href = deepLink;
                link.style.display = "none";
                document.body.appendChild(link);
                link.click();
            }
        })();
    </script>
</body>
</html>`;
}

function getStoreLandingHtml(sellerId: string, storeName: string, origin: string, bannerUrl?: string, description?: string): string {
  const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const hasBanner = !!bannerUrl;
  // Always emit og:image — fall back to logo so cards never appear blank
  const ogImage = hasBanner ? bannerUrl! : 'https://media.instiy.com/assets/instiy-logo.png';
  const twitterCard = hasBanner ? 'summary_large_image' : 'summary';
  const desc = description || ('Check out ' + storeName + ' on Instiy');

  const androidRedirect = 'intent://store/' + sellerId + '#Intent;scheme=io.supabase.instiy;package=com.instiy;S.browser_fallback_url=https%3A%2F%2Fplay.google.com%2Fstore%2Fapps%2Fdetails%3Fid%3Dcom.instiy;end;';
  const iosRedirect = 'io.supabase.instiy://store/' + sellerId;

  return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${esc(storeName)} - Instiy</title>
    <meta name="description" content="${esc(desc)}">
    <meta property="og:type" content="profile">
    <meta property="og:title" content="${esc(storeName)} - Instiy">
    <meta property="og:description" content="${esc(desc)}">
    <meta property="og:image" content="${esc(ogImage)}">
    <meta property="og:url" content="${esc(origin)}/store/${esc(sellerId)}">
    <meta name="twitter:card" content="${twitterCard}">
    <meta name="twitter:title" content="${esc(storeName)} - Instiy">
    <meta name="twitter:description" content="${esc(desc)}">
    <meta name="twitter:image" content="${esc(ogImage)}">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=Outfit:wght@600;700;800&display=swap" rel="stylesheet">
    <style>
        *{margin:0;padding:0;box-sizing:border-box}
        body{font-family:'Inter',sans-serif;background:radial-gradient(circle at 10% 20%,rgba(108,71,255,0.08) 0%,transparent 40%),radial-gradient(circle at 90% 80%,rgba(108,71,255,0.05) 0%,transparent 50%),#FAFAF9;display:flex;flex-direction:column;justify-content:center;align-items:center;min-height:100vh;padding:20px;color:#1C1917;overflow-x:hidden}
        .card{background:rgba(255,255,255,0.85);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);border:1px solid rgba(200,192,184,0.4);border-radius:24px;width:90%;max-width:400px;box-shadow:0 20px 40px rgba(0,0,0,0.06),0 1px 3px rgba(0,0,0,0.02);overflow:hidden;animation:floatIn 0.6s cubic-bezier(0.16,1,0.3,1) forwards}
        .banner-wrap{width:100%;aspect-ratio:2/1;background:#F5F5F4;overflow:hidden}
        .banner-wrap img{width:100%;height:100%;object-fit:cover;transition:transform 0.6s cubic-bezier(0.16,1,0.3,1)}
        .banner-wrap:hover img{transform:scale(1.03)}
        .info{padding:24px;text-align:center}
        .store-name{font-family:'Outfit',sans-serif;font-size:22px;font-weight:700;color:#1C1917;margin-bottom:8px;line-height:1.3}
        .store-desc{font-size:14px;color:#78716C;line-height:1.5;margin-bottom:20px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
        .loader-wrapper{display:flex;align-items:center;justify-content:center;gap:10px;margin-bottom:16px}
        .spinner{animation:rotate 2s linear infinite;width:20px;height:20px}
        .spinner .path{stroke:#6C47FF;stroke-linecap:round;animation:dash 1.5s ease-in-out infinite}
        .loader-text{font-size:14px;font-weight:500;color:#78716C}
        .btn-open{display:block;width:100%;padding:16px;background-color:#6C47FF;color:#fff;text-decoration:none;border-radius:12px;font-weight:600;font-size:16px;box-sizing:border-box;transition:all 0.3s ease;animation:pulse 2s infinite;text-align:center}
        .btn-open:hover{background-color:#5833E6;transform:translateY(-2px)}
        .btn-open:active{transform:translateY(0)}
        @keyframes floatIn{from{opacity:0;transform:translateY(20px)}to{opacity:1;transform:translateY(0)}}
        @keyframes pulse{0%,100%{transform:scale(1);box-shadow:0 4px 14px rgba(108,71,255,0.4)}50%{transform:scale(1.02);box-shadow:0 6px 20px rgba(108,71,255,0.6)}}
        @keyframes rotate{100%{transform:rotate(360deg)}}
        @keyframes dash{0%{stroke-dasharray:1,150;stroke-dashoffset:0}50%{stroke-dasharray:90,150;stroke-dashoffset:-35}100%{stroke-dasharray:90,150;stroke-dashoffset:-124}}
    </style>
    <script>
        document.addEventListener("DOMContentLoaded", function() {
            var isAndroid = /Android/i.test(navigator.userAgent);
            var redirectUrl = isAndroid ? "${androidRedirect}" : "${iosRedirect}";
            var link = document.createElement('a');
            link.href = redirectUrl;
            link.click();
        });
    </script>
</head>
<body>
    <div class="card">
        <div class="banner-wrap">
            <img src="${esc(ogImage)}" alt="${esc(storeName)}" onerror="this.parentElement.style.display='none'">
        </div>
        <div class="info">
            <div class="store-name">${esc(storeName)}</div>
            <div class="store-desc">${esc(desc)}</div>
            <div class="loader-wrapper">
                <svg class="spinner" viewBox="0 0 50 50">
                    <circle class="path" cx="25" cy="25" r="20" fill="none" stroke-width="5"></circle>
                </svg>
                <div class="loader-text">Opening in Instiy...</div>
            </div>
            <a href="${androidRedirect}" class="btn-open">Open App</a>
        </div>
    </div>
</body>
</html>`;
}


export async function handleDeepLinks(request: Request, env: Env): Promise<Response> {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const url = new URL(request.url);
  const path = url.pathname;

  // Android assetlinks.json
  if (path === '/.well-known/assetlinks.json') {
    return new Response(JSON.stringify(getAssetLinks(env), null, 2), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
    });
  }

  // iOS apple-app-site-association
  if (path === '/.well-known/apple-app-site-association' || path === '/apple-app-site-association') {
    return new Response(JSON.stringify(getAppleAppSiteAssociation(env), null, 2), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
    });
  }

  // Product landing page: /product/:id (legacy) or /products/:slug-id (SEO)
  const legacyProductMatch = path.match(/^\/product\/([a-f0-9-]+)$/);
  const seoProductMatch = path.match(/^\/products\/(.+)$/);
  const productMatch = legacyProductMatch || seoProductMatch;

  if (productMatch) {
    let productId = productMatch[1];
    // For SEO format /products/slug-uuid, extract the UUID from the end
    if (seoProductMatch) {
      const uuidMatch = productId.match(/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/);
      if (uuidMatch) {
        productId = uuidMatch[1];
      }
    }
    try {
      const productRes = await fetch(
        `${env.SUPABASE_URL}/rest/v1/products?id=eq.${productId}&select=title,description,price,thumbnail_url,image_urls`,
        {
          headers: {
            apikey: env.SUPABASE_ANON_KEY,
            Authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
          },
        }
      );
      if (productRes.ok) {
        const products = await productRes.json() as Array<{ title: string; description?: string; price: number; thumbnail_url?: string; image_urls?: string[] }>;
        if (products && products.length > 0) {
          const html = getProductLandingHtml(productId, products[0], url.origin);
          return new Response(html, {
            headers: { ...corsHeaders, 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'public, max-age=86400' },
          });
        }
      }
    } catch {
      // Fall through to redirect
    }
    // Fallback: redirect to app
    return new Response(null, {
      status: 302,
      headers: { ...corsHeaders, Location: `io.supabase.instiy://product/${productId}` },
    });
  }

  // Store landing page: /store/:sellerId
  // The URL contains the seller's user ID, so we query by seller_id not by the profile's own id.
  const storeMatch = path.match(/^\/store\/([a-f0-9-]+)$/);
  if (storeMatch) {
    const sellerId = storeMatch[1];
    try {
      const storeRes = await fetch(
        `${env.SUPABASE_URL}/rest/v1/business_profiles?seller_id=eq.${sellerId}&select=business_name,banner_url,description`,
        {
          headers: {
            apikey: env.SUPABASE_ANON_KEY,
            Authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
          },
        }
      );
      if (storeRes.ok) {
        const stores = await storeRes.json() as Array<{ business_name: string; banner_url?: string; description?: string }>;
        const store = stores && stores.length > 0 ? stores[0] : null;
        const storeName = store?.business_name || 'Store';
        const html = getStoreLandingHtml(sellerId, storeName, url.origin, store?.banner_url, store?.description);
        return new Response(html, {
          headers: { ...corsHeaders, 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'public, max-age=3600' },
        });
      }
    } catch {
      // Fall through to redirect
    }
    return new Response(null, {
      status: 302,
      headers: { ...corsHeaders, Location: `io.supabase.instiy://store/${sellerId}` },
    });
  }

  return new Response('Not Found', { status: 404 });
}
