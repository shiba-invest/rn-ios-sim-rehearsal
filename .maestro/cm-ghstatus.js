



const { execSync } = require('child_process');
const [ctx = 'codemagic/stage1-probe', state = 'pending', desc = 'stage 1 probe'] = process.argv.slice(2);
const TOKEN = process.env.GH_STATUS_TOKEN;
const REPO = process.env.CM_REPO_SLUG || '';
let SHA = process.env.CM_COMMIT;
try { SHA = SHA || execSync('git rev-parse HEAD').toString().trim(); } catch (e) { SHA = ''; }
(async () => {
  if (!TOKEN) { console.log('ghstatus skipped=token-missing'); return; }
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(REPO)) { console.log('ghstatus skipped=no-repo'); return; }
  if (!/^[0-9a-f]{40}$/.test(SHA)) { console.log('ghstatus skipped=no-commit'); return; }
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), 20000);
  try {
    const r = await fetch(`https://api.github.com/repos/${REPO}/statuses/${SHA}`, {
      method: 'POST', signal: ac.signal,
      headers: { Authorization: `Bearer ${TOKEN}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'ci-status' },
      body: JSON.stringify({ state, context: ctx, description: desc.slice(0, 140) }),
    });
    console.log(`ghstatus http=${r.status} context=${ctx} state=${state}`);
  } catch (e) {
    console.log(`ghstatus http=000 error=${e.name === 'AbortError' ? 'Timeout20s' : String(e.cause?.code || e.name).replace(/[^A-Za-z_]/g, '')}`);
  } finally { clearTimeout(t); }
})();
