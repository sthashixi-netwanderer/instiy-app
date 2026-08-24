-- Migration: notify a seller's followers (in-app + email) when the seller
-- lists a new product.
--
-- Previously this ran from the Flutter client after createProduct() — it only
-- fired if the app stayed online, and depended on client RLS to read follower
-- emails. Moving it to an AFTER INSERT trigger makes delivery reliable no
-- matter which client (app, admin panel, future web) creates the product.
--
-- Delivery mirrors become_seller (20260823140000): pg_net POST to the send-email
-- Edge Function with the x-notify-secret server-to-server credential, and the
-- in-app notification insert rides the existing on_notification_created push
-- fan-out.

CREATE OR REPLACE FUNCTION public.notify_seller_followers_new_product()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_seller_name TEXT;
  v_url TEXT;
  v_anon_key TEXT;
  v_notify_secret TEXT;
  v_request_id BIGINT;
  v_thumb TEXT;
  v_title TEXT;
  v_subject TEXT;
  v_html TEXT;
  v_deep_link TEXT;
  v_price TEXT;
  v_follower RECORD;
  v_followers_count INT;
BEGIN
  -- Only announce publicly available listings (drafts/sold rows are skipped
  -- by the WHEN clause; this guards other statuses inserted later).
  IF NEW.status <> 'available' THEN
    RETURN NEW;
  END IF;

  -- Store name: business profile brand first, then the seller's own name.
  SELECT COALESCE(
           NULLIF(btrim(bp.business_name), ''),
           NULLIF(btrim(u.full_name), ''),
           'A seller you follow'
         )
    INTO v_seller_name
  FROM public.users u
  LEFT JOIN public.business_profiles bp ON bp.seller_id = u.id
  WHERE u.id = NEW.seller_id;

  SELECT count(*) INTO v_followers_count
  FROM public.seller_follows f
  WHERE f.seller_id = NEW.seller_id;

  IF v_followers_count = 0 THEN
    RETURN NEW;
  END IF;

  -- 1. In-app notifications (batched; the on_notification_created trigger
  --    fans them out as pushes).
  INSERT INTO public.notifications (user_id, title, body, type, data)
  SELECT f.follower_id,
         v_seller_name || ' listed a new product',
         NEW.title,
         'new_product',
         jsonb_build_object('product_id', NEW.id, 'seller_id', NEW.seller_id)
  FROM public.seller_follows f
  WHERE f.seller_id = NEW.seller_id;

  -- 2. Emails via the send-email Edge Function (server-to-server).
  SELECT value INTO v_url FROM public._push_trigger_config WHERE key = 'supabase_functions_url';
  SELECT value INTO v_anon_key FROM public._push_trigger_config WHERE key = 'anon_key';
  SELECT value INTO v_notify_secret FROM public._push_trigger_config WHERE key = 'notify_secret';

  IF v_url IS NULL OR v_anon_key IS NULL OR v_notify_secret IS NULL THEN
    RAISE LOG 'notify_seller_followers: _push_trigger_config not set';
    RETURN NEW;
  END IF;

  -- Cover image: seller-picked thumbnail, else the first listing image.
  v_thumb := COALESCE(
    NULLIF(btrim(NEW.thumbnail_url), ''),
    CASE WHEN array_length(NEW.image_urls, 1) > 0 THEN btrim(NEW.image_urls[1]) END
  );

  -- Minimal HTML escaping for seller-controlled strings.
  v_title := replace(replace(replace(NEW.title, '&', '&amp;'), '<', '&lt;'), '>', '&gt;');
  v_seller_name := replace(replace(replace(v_seller_name, '&', '&amp;'), '<', '&lt;'), '>', '&gt;');

  -- Deep link format the app + worker both parse: /products/<slug>-<uuid>.
  v_deep_link := 'https://instiy.com/products/' || NEW.slug || '-' || NEW.id;
  v_price := 'GH&cent; ' || to_char(NEW.price, 'FM999,999,990.00');
  v_subject := v_seller_name || ' just listed a new product';

  FOR v_follower IN
    SELECT f.follower_id AS id, u.email AS email, u.full_name AS name
    FROM public.seller_follows f
    JOIN public.users u ON u.id = f.follower_id
    WHERE f.seller_id = NEW.seller_id
      AND u.email IS NOT NULL AND btrim(u.email) <> ''
  LOOP
    v_html :=
      $html$<!DOCTYPE html>
<html>
<head>
  <title>$html$ || v_subject || $html$</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #6c47ff, #8B5CF6); padding: 32px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 20px; }
    .body { padding: 24px; }
    .product-card { background: #f5f5f4; border-radius: 12px; padding: 16px; margin: 16px 0; text-align: center; }
    .product-title { font-size: 16px; font-weight: 600; color: #1c1917; margin: 8px 0 4px; }
    .product-price { font-size: 20px; font-weight: 700; color: #6c47ff; }
    .btn { display: inline-block; background: linear-gradient(135deg, #6c47ff, #8B5CF6); color: white; text-decoration: none; padding: 14px 32px; border-radius: 10px; font-weight: 600; font-size: 15px; margin: 16px 0; }
    .footer { padding: 16px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>New Listing!</h1>
    </div>
    <div class="body">
      <p>Hi $html$ || COALESCE(NULLIF(btrim(v_follower.name), ''), 'there') || $html$,</p>
      <p><strong>$html$ || v_seller_name || $html$</strong>, who you follow, just listed a new product:</p>
      <div class="product-card">$html$ ||
        CASE WHEN v_thumb IS NOT NULL THEN
          '<img src="' || v_thumb || '" alt="' || v_title || '" style="width: 100%; max-width: 400px; border-radius: 12px; margin: 16px 0;" />'
        ELSE '' END ||
      $html$
        <div class="product-title">$html$ || v_title || $html$</div>
        <div class="product-price">$html$ || v_price || $html$</div>
      </div>
      <div style="text-align: center;">
        <a href="$html$ || v_deep_link || $html$" class="btn">View Product</a>
      </div>
    </div>
    <div class="footer">
      <p>Instiy — Student Marketplace</p>
    </div>
  </div>
</body>
</html>$html$;

    SELECT net.http_post(
      url := v_url || '/functions/v1/send-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_anon_key,
        'x-notify-secret', v_notify_secret
      ),
      body := jsonb_build_object(
        'to', btrim(v_follower.email),
        'subject', v_subject,
        'html', v_html
      )
    ) INTO v_request_id;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_seller_followers_new_product ON public.products;
CREATE TRIGGER trg_notify_seller_followers_new_product
  AFTER INSERT ON public.products
  FOR EACH ROW
  WHEN (NEW.status = 'available')
  EXECUTE FUNCTION public.notify_seller_followers_new_product();
