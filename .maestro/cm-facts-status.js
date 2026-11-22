










const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const out = (s) => console.log('facts-status ' + s);
const codes = {}; const jobs = []; let held = 0;
const counts = () => { const ok = codes['201'] || 0; const other = Object.entries(codes).filter(([k]) => k !== '201').map(([k, n]) => k + 'x' + n).join(',') || 'none'; return `statuses=${jobs.length} http201=${ok} other=${other} not-sent-secret-left=${held}`; };
const hard = setTimeout(() => { out(counts() + ' stopped=60s-total'); process.exit(0); }, 60000);
const done = () => { clearTimeout(hard); process.exit(0); };
try { main(); } catch (e) { out('error=' + String(e && e.name || 'Error').replace(/[^A-Za-z_]/g, '')); done(); }

function main() {
  const file = process.argv[2];
  const TOKEN = process.env.GH_STATUS_TOKEN || '';
  const REPO = process.env.CM_REPO_SLUG || '';
  let SHA = process.env.CM_COMMIT || '';
  try { SHA = SHA || execSync('git rev-parse HEAD', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(); } catch (e) { SHA = ''; }
  if (!/^cm-stage1-/.test(process.env.CM_TAG || '')) { out('skipped=tag-not-cm-stage1'); return done(); }
  if (!TOKEN) { out('skipped=token-missing'); return done(); }
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(REPO)) { out('skipped=no-repo'); return done(); }
  if (!/^[0-9a-f]{40}$/.test(SHA)) { out('skipped=no-commit'); return done(); }
  if (!file || !fs.existsSync(file)) { out('skipped=no-facts-file'); return done(); }


  const pw = process.env.E2E_0003_PASSWORD || '';
  const id0 = process.env.E2E_0003_LOGIN || '';
  const id = id0 ? id0.padStart(3, '0') : '';
  const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const pwForms = pw ? [...new Set([pw, JSON.stringify(pw).slice(1, -1)])] : [];
  const forms = [...pwForms, ...(TOKEN.length >= 8 ? [TOKEN] : [])].filter((s) => s.length >= 1);
  const ids = [...new Set([id, id0])].filter(Boolean).sort((a, b) => b.length - a.length);
  const idRe = ids.length ? new RegExp('(?<![0-9.:])(?:' + ids.map(esc).join('|') + ')(?![0-9])', 'g') : null;
  let mark = '';
  try { mark = (fs.readFileSync(path.join(__dirname, 'cm-pool.txt'), 'utf8').match(/^dev-pool-mark (\S+)\s*$/m) || [])[1] || ''; } catch (e) { mark = ''; }
  const poolRe = /ap-northeast-1_[A-Za-z0-9]+/g;
  const scrub = (s) => { let t = s; for (const x of forms) t = t.split(x).join('***'); if (idRe) t = t.replace(idRe, '***'); t = t.replace(poolRe, '***'); if (mark) t = t.split(mark).join('***'); return t; };
  const left = (s) => forms.some((x) => s.includes(x)) || (idRe ? (s.match(idRe) || []).length > 0 : false) || (mark && s.includes(mark)) || /ap-northeast-1_[A-Za-z0-9]+/.test(s);


  const L = fs.readFileSync(file, 'utf8').split('\n').map((l) => l.replace(/\r$/, ''));
  L.forEach((l, i) => {
    let ctx, desc;
    const f = l.match(/^FACT (\S+) value=(.*) expect=.* verdict=(MATCH|DIFF|RECORD|MISSING)$/);
    if (f) { ctx = 'codemagic/s1/' + String(i + 1).padStart(2, '0') + '-' + f[1].replace(/[^A-Za-z0-9_.-]/g, '_').slice(0, 60); desc = 'verdict=' + f[3] + ' value=' + f[2]; }
    else if (/^PROBE summary /.test(l)) { ctx = 'codemagic/s1/99-summary'; desc = l.slice('PROBE summary '.length); }
    else return;
    desc = scrub(desc);
    const P = 140, MAXP = 6; const pieces = [];
    if (desc.length <= P) pieces.push(desc);
    else {
      for (let k = 0; k < MAXP && k * P < desc.length; k++) pieces.push(desc.slice(k * P, (k + 1) * P));
      if (desc.length > P * MAXP) { const keep = P * (MAXP - 1); const rest = desc.slice(keep); let tail = rest; let tag = '';
        for (let n = 0; n < 3; n++) { tag = '...+' + (rest.length - (P - tag.length)) + ' chars'; tail = rest.slice(0, P - tag.length) + tag; }
        pieces[MAXP - 1] = tail; }
    }
    pieces.forEach((d, k) => { const c = pieces.length === 1 ? ctx : ctx + '-' + String.fromCharCode(97 + k);
      if (left(d)) { held++; return; } jobs.push({ c, d }); });
  });

  let i = 0;
  const one = async (j) => { const ac = new AbortController(); const t = setTimeout(() => ac.abort(), 20000);
    let k;
    try {
      const r = await fetch(`https://api.github.com/repos/${REPO}/statuses/${SHA}`, { method: 'POST', signal: ac.signal,
        headers: { Authorization: `Bearer ${TOKEN}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'ci-status' },
        body: JSON.stringify({ state: 'success', context: j.c, description: j.d }) });
      k = String(r.status);
    } catch (e) { k = e && e.name === 'AbortError' ? 'timeout20s' : '000'; }
    finally { clearTimeout(t); }
    codes[k] = (codes[k] || 0) + 1; };
  const worker = async () => { while (i < jobs.length) { const j = jobs[i++]; await one(j); } };
  Promise.all(Array.from({ length: Math.min(6, jobs.length) }, worker)).then(() => {
    out(counts()); done();
  }, () => { out('error=send'); done(); });
}
