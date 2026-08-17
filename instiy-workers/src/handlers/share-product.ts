const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

export async function handleShareProduct(request: Request, env: Env, _corsHeaders: Record<string, string>): Promise<Response> {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const url = new URL(request.url);

    // Parse ID from query params or path segments
    let productId = url.searchParams.get('id');

    if (!productId) {
      const pathSegments = url.pathname.split('/').filter(Boolean);
      const index = pathSegments.indexOf('share-product');
      if (index !== -1 && pathSegments.length > index + 1) {
        productId = pathSegments[index + 1];
      }
    }

    if (!productId) {
      return new Response('Product ID is required', { status: 400 });
    }

    // Fetch product details via Supabase REST API
    const productRes = await fetch(
      `${env.SUPABASE_URL}/rest/v1/products?id=eq.${productId}&select=title,description,price,thumbnail_url,image_urls`,
      {
        headers: {
          apikey: env.SUPABASE_ANON_KEY,
          Authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
        },
      }
    );

    const products = await productRes.json() as Array<{ title?: string; description?: string; price?: number; thumbnail_url?: string; image_urls?: string[] }>;
    if (!products || products.length === 0) {
      return new Response('Product not found', { status: 404 });
    }

    const product = products[0];
    const title = product.title;
    const priceStr = `GH¢ ${Number(product.price).toFixed(2)}`;
    const description = product.description || 'Check out this product on Instiy!';

    let imageUrl = product.thumbnail_url;
    if (!imageUrl && product.image_urls && product.image_urls.length > 0) {
      imageUrl = product.image_urls[0];
    }
    if (!imageUrl) {
      imageUrl = 'https://media.instiy.com/assets/instiy-logo.png';
    }

    const userAgent = request.headers.get('user-agent') || '';
    const isAndroid = /android/i.test(userAgent);

    const appDeepLink = `io.supabase.instiy://product/${productId}`;
    const redirectUrl = isAndroid
      ? `intent://product/${productId}#Intent;scheme=io.supabase.instiy;package=com.instiy;S.browser_fallback_url=https%3A%2F%2Fplay.google.com%2Fstore%2Fapps%2Fdetails%3Fid%3Dcom.instiy;end;`
      : `io.supabase.instiy://product/${productId}`;

    const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title} | Instiy</title>
  <meta name="description" content="${priceStr} - ${description}">
  <meta property="og:type" content="website">
  <meta property="og:title" content="${title}">
  <meta property="og:description" content="${priceStr} - ${description}">
  <meta property="og:image" content="${imageUrl}">
  <meta property="og:url" content="${request.url}">
  <meta property="twitter:card" content="summary_large_image">
  <meta property="twitter:title" content="${title}">
  <meta property="twitter:description" content="${priceStr} - ${description}">
  <meta property="twitter:image" content="${imageUrl}">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=Outfit:wght@600;700;800&display=swap" rel="stylesheet">
  <style>
    body{margin:0;padding:0;min-height:100vh;font-family:'Inter',sans-serif;background:radial-gradient(circle at 10% 20%,rgba(108,71,255,0.08) 0%,transparent 40%),radial-gradient(circle at 90% 80%,rgba(108,71,255,0.05) 0%,transparent 50%),#FAFAF9;display:flex;flex-direction:column;justify-content:center;align-items:center;color:#1C1917;overflow-x:hidden}
    .card{background:rgba(255,255,255,0.85);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);border:1px solid rgba(200,192,184,0.4);border-radius:24px;padding:24px;width:90%;max-width:400px;box-shadow:0 20px 40px rgba(0,0,0,0.06),0 1px 3px rgba(0,0,0,0.02);text-align:center;box-sizing:border-box;animation:floatIn 0.6s cubic-bezier(0.16,1,0.3,1) forwards}
    .product-image-container{position:relative;width:100%;padding-bottom:100%;border-radius:16px;overflow:hidden;margin-bottom:20px;background-color:#F5F5F4;border:1px solid rgba(200,192,184,0.2)}
    .product-image{position:absolute;top:0;left:0;width:100%;height:100%;object-fit:cover;transition:transform 0.6s cubic-bezier(0.16,1,0.3,1)}
    .product-image-container:hover .product-image{transform:scale(1.05)}
    .price-badge{position:absolute;bottom:12px;right:12px;background-color:#6C47FF;color:#FFFFFF;padding:8px 14px;border-radius:99px;font-weight:600;font-size:15px;box-shadow:0 4px 12px rgba(108,71,255,0.3)}
    .product-title{font-family:'Outfit',sans-serif;font-size:22px;font-weight:700;margin:0 0 8px 0;color:#1C1917;line-height:1.3;text-align:left}
    .product-desc{font-size:14px;color:#78716C;margin:0 0 24px 0;line-height:1.5;text-align:left;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
    .loader-wrapper{display:flex;align-items:center;justify-content:center;gap:10px;margin-bottom:20px}
    .spinner{animation:rotate 2s linear infinite;width:20px;height:20px}
    .spinner .path{stroke:#6C47FF;stroke-linecap:round;animation:dash 1.5s ease-in-out infinite}
    .loader-text{font-size:14px;font-weight:500;color:#78716C}
    .btn-open{display:block;width:100%;padding:16px;background-color:#6C47FF;color:#FFFFFF;text-decoration:none;border-radius:12px;font-weight:600;font-size:16px;box-sizing:border-box;transition:all 0.3s ease;animation:pulse 2s infinite}
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
      var productId = "${productId}";
      var redirectUrl = "io.supabase.instiy://product/" + productId;
      if (isAndroid) {
        redirectUrl = "intent://product/" + productId + "#Intent;scheme=io.supabase.instiy;package=com.instiy;S.browser_fallback_url=https%3A%2F%2Fplay.google.com%2Fstore%2Fapps%2Fdetails%3Fid%3Dcom.instiy;end;";
      }
      var link = document.createElement('a');
      link.href = redirectUrl;
      link.click();
    });
  </script>
</head>
<body>
  <div class="card">
    <div class="product-image-container">
      <img src="${imageUrl}" alt="${title}" class="product-image" onerror="this.src='https://media.instiy.com/assets/instiy-logo.png'">
      <div class="price-badge">${priceStr}</div>
    </div>
    <h1 class="product-title">${title}</h1>
    <p class="product-desc">${description}</p>
    <div class="loader-wrapper">
      <svg class="spinner" viewBox="0 0 50 50">
        <circle class="path" cx="25" cy="25" r="20" fill="none" stroke-width="5"></circle>
      </svg>
      <div class="loader-text">Opening in Instiy...</div>
    </div>
    <a href="${redirectUrl}" class="btn-open">Open App</a>
  </div>
</body>
</html>`;

    return new Response(html, {
      status: 200,
      headers: {
        ...corsHeaders,
        'Content-Type': 'text/html; charset=utf-8',
      },
    });
  } catch (error) {
    console.error('Function error:', error);
    return new Response('Internal Server Error', { status: 500 });
  }
}
