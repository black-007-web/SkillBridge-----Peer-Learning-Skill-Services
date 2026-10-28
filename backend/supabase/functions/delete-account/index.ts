import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return response(405, { error: 'Method not allowed' });

  const authorization = request.headers.get('authorization');
  const token = authorization?.replace(/^Bearer\s+/i, '');
  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!token || !url || !anonKey || !serviceKey) return response(401, { error: 'Sign in again to continue' });

  let body: { current_password?: string | null };
  try {
    body = await request.json();
  } catch {
    return response(400, { error: 'Invalid request' });
  }

  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser(token);
  const user = userData.user;
  if (userError || !user?.id || !user.email) return response(401, { error: 'Your session is invalid. Sign in again.' });

  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  if (typeof body.current_password === 'string' && body.current_password.length > 0) {
    const verifier = createClient(url, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: verified, error: passwordError } = await verifier.auth.signInWithPassword({
      email: user.email,
      password: body.current_password,
    });
    if (passwordError || verified.user?.id !== user.id) return response(401, { error: 'Current password is incorrect' });
  } else {
    const lastSignIn = user.last_sign_in_at ? new Date(user.last_sign_in_at).getTime() : 0;
    if (!lastSignIn || Date.now() - lastSignIn > 10 * 60 * 1000) {
      return response(401, { error: 'Reauthenticate within the last 10 minutes before deleting your account' });
    }
  }

  // All paths are scoped to the verified caller. A failed storage cleanup
  // stops deletion so a retry can finish safely without losing account access.
  const { data: objects, error: listError } = await admin.storage
    .from('avatars')
    .list(user.id, { limit: 1000 });
  if (listError) return response(503, { error: 'Could not clean up profile photos; retry deletion later' });
  const paths = (objects ?? []).map((object) => `${user.id}/${object.name}`);
  if (paths.length > 0) {
    const { error: removeError } = await admin.storage.from('avatars').remove(paths);
    if (removeError) return response(503, { error: 'Could not clean up profile photos; retry deletion later' });
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) return response(503, { error: 'Account deletion could not be completed; retry later' });
  return response(200, { deleted: true });
});

function response(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
