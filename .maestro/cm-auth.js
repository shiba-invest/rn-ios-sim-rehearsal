











const env = require('../eas.json').build['preview-dev'].env;
let mark = '';
try { mark = ((require('fs').readFileSync(require('path').join(__dirname, 'cm-pool.txt'), 'utf8').match(/^dev-pool-mark (\S+)\s*$/m)) || [])[1] || ''; } catch (e) { mark = ''; }
const id = process.env.E2E_0003_LOGIN;
const pw = process.env.E2E_0003_PASSWORD;
const out = (s) => console.log(`auth ${s}`);


const msgKind = (m) => { const s = String(m || '');
  return /attempts exceeded/i.test(s) ? 'locked-after-failures' : /incorrect username or password/i.test(s) ? 'wrong-id-or-password'
    : /disabled/i.test(s) ? 'user-disabled' : /not exist/i.test(s) ? 'no-such-user' : s ? 'other' : 'none'; };
const ws = (v) => (typeof v === 'string' && v !== v.trim() ? 'yes' : 'no');
const listOut = process.argv[2] || '';
const putGohan = (s) => { if (listOut) { try { require('fs').writeFileSync(listOut, 'list-data ' + s + '\n'); } catch (e) { /* stage 1 only records */ } } };










async function listData(tok) {
  const g0 = Date.now();
  const reads = []; const w = { role: 'unread', homes: 'unread', contract: 'unread', inc: 'unread', hit: 'unread' };
  const line = () => putGohan(`role=${w.role} homes=${w.homes} contract=${w.contract} first-in-contract=${w.inc} first-hit-month-offset=${w.hit} reads=${!reads.length ? 'none' : reads.every((x) => /:200(x7)?$/.test(x)) ? 'ok' : reads.join(',')} ms=${Date.now() - g0}`);
  const base = { core: env.EXPO_PUBLIC_API_BASE_URL, kaimono: env.EXPO_PUBLIC_KAIMONO_API_BASE_URL, meal: env.EXPO_PUBLIC_MEAL_API_BASE_URL };
  let prodMarks = [];
  try { prodMarks = require('fs').readFileSync(require('path').join(__dirname, 'cm-values.txt'), 'utf8').split('\n').map((l) => l.match(/^0 (\S+)\s*$/)).filter(Boolean).map((m) => m[1]); } catch (e) { prodMarks = []; }
  for (const [k, v] of Object.entries(base)) {
    if (!v || !/^https:\/\//.test(String(v))) { reads.push(k + ':no-base'); line(); return; }
    if (!prodMarks.length || prodMarks.some((m) => String(v).includes(m))) { reads.push(k + ':' + (prodMarks.length ? 'prod-mark' : 'no-marks')); line(); return; }
  }
  const all = new AbortController(); const tAll = setTimeout(() => all.abort(), 30000);
  const get = async (step, b, p) => {
    const ac = new AbortController(); const t = setTimeout(() => ac.abort(), 10000); const off = () => ac.abort(); all.signal.addEventListener('abort', off);
    try {
      const r = await fetch(String(b).replace(/\/+$/, '') + p, { method: 'GET', signal: ac.signal, headers: { authorization: tok, 'cache-control': 'no-store' } });
      let j = null; try { j = await r.json(); } catch (e) { j = null; }
      return { step, code: r.status, j };
    } catch (e) { return { step, code: e.name === 'AbortError' ? 'timeout' : '000', j: null }; }
    finally { clearTimeout(t); all.signal.removeEventListener('abort', off); }
  };
  const ok = (r) => { reads.push(r.step + ':' + r.code); return r.code === 200 && r.j; };
  try {
    const [me, gh, ct] = await Promise.all([get('me', base.core, '/staff/me'), get('homes', base.kaimono, '/group-homes'), get('contract', base.kaimono, '/group-homes/contract')]);
    if (ok(me)) w.role = me.j.role === 'user' ? 'caregiver' : me.j.role === 'admin' ? 'admin' : 'other';
    const hl = ok(gh) && Array.isArray(gh.j.groupHomes) ? gh.j.groupHomes : null; if (hl) w.homes = hl.length;
    const cl = ok(ct) && Array.isArray(ct.j.groupHomes) ? ct.j.groupHomes : null; if (cl) w.contract = cl.length;
    if (!hl || !cl) { line(); return; }
    const first = hl.length ? hl[0].id : null;
    w.inc = first != null && cl.some((g) => g.id === first) ? 'true' : 'false';
    const target = w.inc === 'true' ? first : (cl.length ? cl[0].id : null);
    if (target == null) { w.hit = 'none'; reads.push('photos:no-home'); line(); return; }
    const j = new Date(Date.now() + 9 * 3600 * 1000); const y = j.getUTCFullYear(), m = j.getUTCMonth();
    const ym = (k) => { const d = new Date(Date.UTC(y, m - k, 1)); return d.getUTCFullYear() + '-' + String(d.getUTCMonth() + 1).padStart(2, '0'); };
    const rs = await Promise.all([0, 1, 2, 3, 4, 5, 6].map((k) => get('m' + k, base.meal, `/admin/gh/${encodeURIComponent(target)}/meal-photos?month=${ym(k)}`)));
    const codes = [...new Set(rs.map((r) => r.code))];
    reads.push('photos:' + (codes.length === 1 ? codes.join('') + 'x7' : rs.map((r) => r.code).join('/')));
    if (rs.some((r) => r.code !== 200 || !Array.isArray(r.j))) { line(); return; }
    const k = rs.findIndex((r) => r.j.some((rec) => Array.isArray(rec && rec.photos) && rec.photos.length > 0));
    w.hit = k < 0 ? 'none' : String(k); line();
  } finally { clearTimeout(tAll); }
}
(async () => {
  putGohan('skipped=no-sign-in (see cognito-auth)');
  if (!mark) { out('skipped=no-dev-pool-mark-in-cm-pool.txt'); return; }
  if (!String(env.EXPO_PUBLIC_USER_POOL_ID || '').includes(mark)) { out('skipped=not-the-dev-pool'); return; }
  if (!id || !pw) { out(`skipped=value-missing id-set=${id ? 'yes' : 'no'} pw-set=${pw ? 'yes' : 'no'}`); return; }
  out(`id-edge-whitespace=${ws(id)} pw-edge-whitespace=${ws(pw)} id-digits-only=${/^[0-9]+$/.test(id) ? 'yes' : 'no'}`);
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), 20000);
  const t0 = Date.now();
  try {
    const r = await fetch(`https://cognito-idp.${env.EXPO_PUBLIC_AWS_REGION}.amazonaws.com/`, {
      method: 'POST',
      signal: ac.signal,
      headers: { 'Content-Type': 'application/x-amz-json-1.1', 'X-Amz-Target': 'AWSCognitoIdentityProviderService.InitiateAuth' },
      body: JSON.stringify({ AuthFlow: 'USER_PASSWORD_AUTH', ClientId: env.EXPO_PUBLIC_USER_POOL_CLIENT_ID,
        AuthParameters: { USERNAME: id.padStart(3, '0'), PASSWORD: pw } }),
    });
    let j = {};
    try { j = await r.json(); } catch (e) { j = {}; }
    const kind = j.AuthenticationResult ? 'result=AuthenticationResult'
      : j.ChallengeName ? `result=challenge-${String(j.ChallengeName).replace(/[^A-Z_]/g, '')}`
      : `error=${String(j.__type || 'none').split('#').pop().replace(/[^A-Za-z]/g, '')} kind=${msgKind(j.message)}`;
    out(`http=${r.status} ${kind} ms=${Date.now() - t0}`);
    const tok = j.AuthenticationResult && j.AuthenticationResult.IdToken; j = null;
    if (listOut && tok) { clearTimeout(t); try { await listData(tok); } catch (e) { putGohan('error=' + String(e && e.name || 'Error').replace(/[^A-Za-z]/g, '')); } }
  } catch (e) {
    out(`http=000 error=${e.name === 'AbortError' ? 'Timeout20s' : String(e.cause?.code || e.name).replace(/[^A-Za-z_]/g, '')} ms=${Date.now() - t0}`);
  } finally { clearTimeout(t); }
})();
