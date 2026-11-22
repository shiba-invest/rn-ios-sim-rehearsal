
















const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const out = (s) => console.log('s2-status ' + s);
const codes = {}; const jobs = []; let held = 0; let retried = 0; let RFW = 'none';
const counts = () => { const ok = codes['201'] || 0; const other = Object.entries(codes).filter(([k]) => k !== '201').map(([k, n]) => k + 'x' + n).join(',') || 'none'; return `statuses=${jobs.length} http201=${ok} other=${other} retried=${retried} not-sent-secret-left=${held} repo-from=${RFW}`; };
const hard = setTimeout(() => { out(counts() + ' stopped=35s-total'); process.exit(0); }, 35000);
const done = () => { clearTimeout(hard); process.exit(0); };
try { main(); } catch (e) { out('error=' + String(e && e.name || 'Error').replace(/[^A-Za-z_]/g, '')); done(); }

function main() {
  const dir = process.argv[2]; const causes = process.argv[3] || '';
  const BM = 'b=' + String(process.env.CM_BUILD_ID || 'none').replace(/[^A-Za-z0-9]/g, '').slice(0, 6) + ' ';
  const TOKEN = process.env.GH_STATUS_TOKEN || '';
  const { repo: REPO, from: RF } = require('./cm-repo.js').repoSlug();
  let SHA = process.env.CM_COMMIT || '';
  try { SHA = SHA || execSync('git rev-parse HEAD', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(); } catch (e) { SHA = ''; }
  if (!/^cm-stage2-/.test(process.env.CM_TAG || '')) { out('skipped=tag-not-cm-stage2'); return done(); }
  if (!TOKEN) { out('skipped=token-missing'); return done(); }
  RFW = RF;
  if (!REPO) { out('skipped=no-repo repo-from=none'); return done(); }
  if (!/^[0-9a-f]{40}$/.test(SHA)) { out('skipped=no-commit'); return done(); }
  if (!dir || !fs.existsSync(dir)) { out('skipped=no-upload-dir'); return done(); }


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
  const scrub = (s) => { let t = s.replace(poolRe, '***'); if (mark) t = t.split(mark).join('***'); for (const x of forms) t = t.split(x).join('***'); if (idRe) t = t.replace(idRe, '***'); return t; };
  const left = (s) => /ap-northeast-1_[A-Za-z0-9]+/.test(s) || /ap-northeast-\S{0,8}_[A-Za-z0-9]{4,}/.test(s) || (mark && s.includes(mark)) || forms.some((x) => s.includes(x)) || (idRe ? (s.match(idRe) || []).length > 0 : false);


  const BMS = scrub(BM);
  const KEEP = /^(GATE |DEADLINE|pass-check |PASS not written|step [a-z]+ rc=|pool=|iphone rc=|flow [a-z0-9-]+ rc=|login-shots-kept-outside=)/;
  const seen = new Set(); const lines = [];
  const files = [causes || path.join(dir, 'logs/causes.txt'), ...['logs/a-toolchain.log', 'logs/env.log', 'logs/b-bundle.log', 'iphone/result.txt'].map((f) => path.join(dir, f))];
  for (const f of files) {
    let t = ''; try { t = fs.readFileSync(f, 'utf8'); } catch (e) { continue; }
    for (const l0 of t.split('\n')) { const l = l0.replace(/\r$/, '').trim(); if (!KEEP.test(l) || seen.has(l)) continue; seen.add(l); lines.push(l); }
  }
  const key = (l) => { let m;
    if ((m = l.match(/^GATE ([a-z]+)/))) return 'gate-' + m[1];
    if ((m = l.match(/^step ([a-z]+) rc=/))) return 'step-' + m[1];
    if ((m = l.match(/^flow ([a-z0-9-]+) rc=/))) return 'flow-' + m[1];
    if (/^DEADLINE/.test(l)) return 'deadline';
    if (/^pass-check |^PASS not written/.test(l)) return 'pass-check';
    if (/^pool=/.test(l)) return 'env-pool';
    if (/^iphone rc=/.test(l)) return 'iphone';
    return 'login-shots-kept-outside'; };
  const rank = (l) => /^pass-check |^PASS not written/.test(l) ? 0
    : (/FAIL|^DEADLINE/.test(l) || /\brc=(?!0\b)[0-9]+/.test(l) || (/^GATE /.test(l) && !/^GATE [a-z]+ ok\b/.test(l))) ? 1 : 2;
  lines.forEach((l, i) => {
    const c = 'codemagic/s2/' + String(i + 1).padStart(2, '0') + '-' + key(l);


    const t = scrub(l); if (left(t)) { held++; return; }
    let d = BMS + t; if (d.length > 140) d = d.slice(0, 137) + '...';


    if (left(t.slice(0, 137 - BMS.length))) { held++; return; } jobs.push({ c, d, r: rank(l) }); });
  jobs.sort((a, b) => a.r - b.r); jobs.splice(24);
  if (!jobs.length) { out(counts() + ' no-cause-lines'); return done(); }

  let i = 0;
  const send = async (j) => { const ac = new AbortController(); const t = setTimeout(() => ac.abort(), 15000);
    let k;
    try {
      const r = await fetch(`https://api.github.com/repos/${REPO}/statuses/${SHA}`, { method: 'POST', signal: ac.signal,
        headers: { Authorization: `Bearer ${TOKEN}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'ci-status' },
        body: JSON.stringify({ state: 'success', context: j.c, description: j.d }) });
      k = String(r.status);
    } catch (e) { k = e && e.name === 'AbortError' ? 'timeout15s' : '000'; }
    finally { clearTimeout(t); }
    return k; };
  const one = async (j) => { let k = await send(j);
    if (k !== '201') { retried++; await new Promise((r) => setTimeout(r, 2000)); k = await send(j); }
    codes[k] = (codes[k] || 0) + 1; };
  const worker = async () => { while (i < jobs.length) { const j = jobs[i++]; await one(j); } };
  Promise.all(Array.from({ length: Math.min(2, jobs.length) }, worker)).then(() => { out(counts()); done(); }, () => { out('error=send'); done(); });
}
