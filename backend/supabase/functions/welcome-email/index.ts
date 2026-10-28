import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type WelcomeEvent = {
  id: number;
  attempts: number;
  delivered_at: string | null;
  event_type: string;
  payload: { full_name?: string; email?: string; registered_at?: string };
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return response(405, { error: 'Method not allowed' });

  const hookSecret = Deno.env.get('WELCOME_WEBHOOK_SECRET');
  if (!hookSecret || request.headers.get('authorization') !== `Bearer ${hookSecret}`) {
    return response(401, { error: 'Unauthorized' });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const resendKey = Deno.env.get('RESEND_API_KEY');
  const from = Deno.env.get('WELCOME_FROM');
  const appUrl = Deno.env.get('APP_URL');
  if (!supabaseUrl || !serviceKey || !resendKey || !from || !appUrl) {
    return response(500, { error: 'Email delivery is not configured' });
  }

  let requestBody: { record?: { id?: number }; batch?: boolean };
  try {
    requestBody = await request.json();
  } catch {
    return response(400, { error: 'Invalid event payload' });
  }
  if (!Number.isSafeInteger(requestBody.record?.id) && requestBody.batch !== true) {
    return response(400, { error: 'Provide an outbox record or request a pending batch' });
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  let query = admin
    .from('transactional_email_outbox')
    .select('id,attempts,delivered_at,event_type,payload')
    .is('delivered_at', null)
    .lte('next_attempt_at', new Date().toISOString());
  if (requestBody.record?.id) query = query.eq('id', requestBody.record.id);
  const { data, error } = await query.order('created_at').limit(requestBody.batch ? 25 : 1);
  if (error) return response(503, { error: 'Could not read pending email events' });
  if (!data?.length) {
    return requestBody.batch ? response(200, { processed: 0 }) : response(200, { processed: 0, duplicate: true });
  }

  let failed = 0;
  for (const row of data as WelcomeEvent[]) {
    if (row.event_type !== 'welcome' || !(await sendWelcome(row, admin, resendKey, from, appUrl))) {
      failed++;
    }
  }
  return failed > 0
    ? response(503, { processed: data.length, failed })
    : response(200, { processed: data.length });
});

async function sendWelcome(
  row: WelcomeEvent,
  admin: ReturnType<typeof createClient>,
  resendKey: string,
  from: string,
  appUrl: string,
): Promise<boolean> {
  const email = row.payload.email;
  if (!email) return recordFailure(admin, row);
  const name = row.payload.full_name?.trim() || 'learner';
  const registrationDate = row.payload.registered_at
    ? new Date(row.payload.registered_at).toLocaleDateString('en', { dateStyle: 'long', timeZone: 'UTC' })
    : 'today';
  const supportEmail = Deno.env.get('WELCOME_SUPPORT_EMAIL') ?? from;
  const safeName = escapeHtml(name);
  const safeEmail = escapeHtml(email);
  const safeAppUrl = escapeHtml(appUrl);
  const safeSupportEmail = escapeHtml(supportEmail);
  const html = `<!doctype html><html><body style="margin:0;background:#080b16;color:#f0f3ff;font-family:Arial,sans-serif;padding:32px 16px"><table role="presentation" width="100%" cellspacing="0" cellpadding="0"><tr><td align="center"><table role="presentation" width="600" style="max-width:600px;background:#12182b;border:1px solid #29344f;border-radius:22px;padding:36px"><tr><td><div style="font-size:13px;letter-spacing:2px;color:#8fa2ff;font-weight:bold">SKILLBRIDGE</div><h1 style="font-size:28px;margin:22px 0 12px;color:#f0f3ff">Welcome, ${safeName}!</h1><p style="line-height:1.7;color:#c0c9df">Your learning journey starts here. Find peers, share what you know, explore learning resources, and build skills together.</p><div style="background:#1a233a;border-radius:14px;padding:16px;margin:22px 0;color:#dce3ff"><p style="margin:4px 0">Account: ${safeEmail}</p><p style="margin:4px 0">Joined: ${escapeHtml(registrationDate)}</p></div><p style="line-height:1.7;color:#c0c9df">Use the separate verification email from SkillBridge to confirm your address before signing in. If you did not create this account, contact <a style="color:#53e0c1" href="mailto:${safeSupportEmail}">${safeSupportEmail}</a>.</p><p style="margin-top:28px"><a href="${safeAppUrl}" style="display:inline-block;background:#8298ff;color:#10162d;text-decoration:none;font-weight:bold;padding:13px 20px;border-radius:12px">Explore SkillBridge</a></p><p style="line-height:1.7;color:#c0c9df;margin-top:26px">Happy learning,<br>The SkillBridge Team</p></td></tr></table></td></tr></table></body></html>`;
  const text = `Welcome, ${name}!\n\nYour learning journey starts here. Find peers, share what you know, explore learning resources, and build skills together.\n\nAccount: ${email}\nJoined: ${registrationDate}\n\nUse the separate verification email from SkillBridge to confirm your address before signing in.\n\nExplore SkillBridge: ${appUrl}\n\nIf you did not create this account, contact ${supportEmail}.\n\nHappy learning,\nThe SkillBridge Team`;

  const mail = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${resendKey}`,
      'Content-Type': 'application/json',
      'Idempotency-Key': `skillbridge-welcome-${row.id}`,
    },
    body: JSON.stringify({ from, to: [email], subject: 'Welcome to SkillBridge — Your Learning Journey Starts Here!', html, text }),
  });
  if (!mail.ok) return recordFailure(admin, row);
  const { error } = await admin
    .from('transactional_email_outbox')
    .update({ delivered_at: new Date().toISOString(), attempts: row.attempts + 1 })
    .eq('id', row.id)
    .is('delivered_at', null);
  return !error;
}

async function recordFailure(admin: ReturnType<typeof createClient>, row: WelcomeEvent) {
  const delayMinutes = Math.min(5 * 2 ** row.attempts, 24 * 60);
  await admin
    .from('transactional_email_outbox')
    .update({
      attempts: row.attempts + 1,
      next_attempt_at: new Date(Date.now() + delayMinutes * 60_000).toISOString(),
    })
    .eq('id', row.id)
    .is('delivered_at', null);
  return false;
}

function escapeHtml(value: string) {
  return value.replace(/[&<>"']/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  })[character] ?? character);
}

function response(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
