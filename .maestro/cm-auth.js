







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
(async () => {
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
  } catch (e) {
    out(`http=000 error=${e.name === 'AbortError' ? 'Timeout20s' : String(e.cause?.code || e.name).replace(/[^A-Za-z_]/g, '')} ms=${Date.now() - t0}`);
  } finally { clearTimeout(t); }
})();
