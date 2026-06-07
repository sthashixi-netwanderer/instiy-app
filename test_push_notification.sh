#!/bin/bash
# Test push notification pipeline
# Usage: ./test_push_notification.sh

set -e

PROJECT_REF="wqasatrxqinkfaafgnli"
SUPABASE_URL="https://${PROJECT_REF}.supabase.co"
ANON_KEY=$(grep supabaseAnonKey lib/config/app_config.dart | sed "s/.*'\(.*\)'.*/\1/")
Q="supabase db query --linked -o json"

echo "=== Push Notification Pipeline Test ==="
echo ""

# 1. Check if edge function is deployed
echo "[1/6] Checking edge function deployment..."
FUNC_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "${SUPABASE_URL}/functions/v1/push-notifications" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${ANON_KEY}" \
  -d '{"record":{"user_id":"00000000-0000-0000-0000-000000000000","title":"test","body":"test","type":"test"}}')

if [ "$FUNC_STATUS" = "200" ] || [ "$FUNC_STATUS" = "400" ] || [ "$FUNC_STATUS" = "404" ]; then
  echo "  OK Edge function reachable (HTTP $FUNC_STATUS)"
else
  echo "  FAIL Edge function returned HTTP $FUNC_STATUS"
fi

# 2. Check pg_net extension
echo ""
echo "[2/6] Checking pg_net extension..."
PG_NET=$($Q "SELECT extname FROM pg_extension WHERE extname = 'pg_net';" 2>&1 || echo "FAIL")
if echo "$PG_NET" | grep -q "pg_net"; then
  echo "  OK pg_net extension is enabled"
else
  echo "  FAIL pg_net extension NOT found"
fi

# 3. Check trigger exists
echo ""
echo "[3/6] Checking send_push_notification trigger..."
TRIGGER=$($Q "SELECT tgname FROM pg_trigger WHERE tgname = 'trigger_send_push_notification';" 2>&1 || echo "FAIL")
if echo "$TRIGGER" | grep -q "trigger_send_push_notification"; then
  echo "  OK Trigger exists on notifications table"
else
  echo "  FAIL Trigger NOT found"
fi

# 4. Check trigger function exists
echo ""
echo "[4/6] Checking send_push_notification function..."
FUNC=$($Q "SELECT proname FROM pg_proc WHERE proname = 'send_push_notification';" 2>&1 || echo "FAIL")
if echo "$FUNC" | grep -q "send_push_notification"; then
  echo "  OK Trigger function exists"
else
  echo "  FAIL Trigger function NOT found"
fi

# 5. Check config table
echo ""
echo "[5/6] Checking _push_trigger_config table..."
CONFIG=$($Q "SELECT key FROM public._push_trigger_config ORDER BY key;" 2>&1 || echo "FAIL")
if echo "$CONFIG" | grep -q "supabase_url"; then
  echo "  OK Config table has supabase_url"
else
  echo "  FAIL supabase_url NOT configured"
fi
if echo "$CONFIG" | grep -q "anon_key"; then
  echo "  OK Config table has anon_key"
else
  echo "  FAIL anon_key NOT configured"
fi

# 6. Check user_push_tokens table and token count
echo ""
echo "[6/6] Checking user_push_tokens table..."
TOKENS=$($Q "SELECT COUNT(*) as count FROM public.user_push_tokens;" 2>&1 || echo "FAIL")
if echo "$TOKENS" | grep -q "count"; then
  COUNT=$(echo "$TOKENS" | grep -oP '\d+' | head -1)
  echo "  OK user_push_tokens table exists ($COUNT tokens stored)"
else
  echo "  FAIL user_push_tokens table NOT found or query failed"
fi

# 7. Check edge function secrets
echo ""
echo "[7/6] Checking edge function secrets..."
SECRETS=$(supabase secrets list 2>&1)
if echo "$SECRETS" | grep -q "FCM_SERVICE_ACCOUNT_KEY"; then
  echo "  OK FCM_SERVICE_ACCOUNT_KEY is set"
else
  echo "  FAIL FCM_SERVICE_ACCOUNT_KEY NOT set"
fi

# 8. Test end-to-end: insert a test notification for a real user
echo ""
echo "[8/6] End-to-end test: inserting a test notification..."
E2E=$($Q "INSERT INTO public.notifications (user_id, title, body, type) SELECT id, 'Push Test', 'Testing push notification pipeline', 'test' FROM public.users LIMIT 1 RETURNING id, user_id;" 2>&1 || echo "FAIL")
if echo "$E2E" | grep -q "id"; then
  echo "  OK Test notification inserted"
  echo "  Check if pg_net fired the HTTP request..."
  # Check pg_net request queue
  sleep 2
  REQUESTS=$($Q "SELECT id, status_code, error_msg FROM net._http_response ORDER BY id DESC LIMIT 1;" 2>&1 || echo "FAIL")
  echo "  pg_net response: $REQUESTS"
else
  echo "  FAIL Could not insert test notification: $E2E"
fi

echo ""
echo "=== Test Complete ==="
