-- WebRTC call signaling over Supabase Realtime private channels.
-- Private channels authorize broadcast messages via RLS on realtime.messages.
-- Both callers are authenticated app users, so allow authenticated role
-- read/write; anonymous clients are denied by the absence of a policy.

alter publication supabase_realtime add table realtime.messages;

create policy "authenticated users can exchange call signals"
on realtime.messages
for all
to authenticated
using (true)
with check (true);
