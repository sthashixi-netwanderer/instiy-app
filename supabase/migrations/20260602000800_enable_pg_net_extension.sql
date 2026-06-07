-- Enable pg_net extension for HTTP requests from database triggers
-- This is required by the send_push_notification() trigger which uses net.http_post()

CREATE EXTENSION IF NOT EXISTS pg_net SCHEMA extensions;
