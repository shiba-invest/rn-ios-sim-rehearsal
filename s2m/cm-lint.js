





const cp = require('child_process'), fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const git = (a) => cp.execFileSync('git', ['-C', ROOT, ...a], { encoding: 'utf8', maxBuffer: 64 << 20 });
function reader(ref) {
  if (!ref) return (p) => { try { return fs.readFileSync(path.join(ROOT, p), 'utf8'); } catch { return null; } };
  return (p) => { try { return cp.execFileSync('git', ['-C', ROOT, 'show', `${ref}:${p}`], { encoding: 'utf8', maxBuffer: 64 << 20, stdio: ['ignore', 'pipe', 'ignore'] }); } catch { return null; } };
}
function collect(ref) {
  const rd = reader(ref);
  let entry = 'codemagic.yaml'; let txt = rd(entry);
  if (txt === null) { entry = '.github/workflows/ios-sim-trial.yml'; txt = rd(entry); }
  if (txt === null) throw new Error('no CI entry file at ' + (ref || 'working tree'));
  const files = new Map([[entry, txt]]); const todo = [entry];
  const fl = rd('.maestro/cm-flows.txt');
  if (fl !== null) for (const l of fl.split('\n')) { const m = l.match(/^\s*[^#\s]\S*\s+(\S+\.yaml)\s/); if (m && rd('.maestro/' + m[1]) !== null && !files.has('.maestro/' + m[1])) { files.set('.maestro/' + m[1], rd('.maestro/' + m[1])); todo.push('.maestro/' + m[1]); } }
  while (todo.length) {
    const f = todo.pop(); const t = files.get(f);
    const refs = new Set();
    const tc = t.split('\n').filter((l) => !/^\s*(#|\/\/)/.test(l)).join('\n');
    for (const m of tc.matchAll(/\.maestro\/[A-Za-z0-9_.\/-]+\.(?:sh|js|yaml|json)/g)) refs.add(m[0]);
    if (/\.ya?ml$/.test(f) && f.startsWith('.maestro/'))
      for (const m of tc.matchAll(/runFlow:\s*(?:\n\s*file:\s*)?["']?([A-Za-z0-9_.\/-]+\.yaml)/g)) refs.add(path.posix.join(path.posix.dirname(f), m[1]));
    for (const m of tc.matchAll(/(?:^|\s)"?([A-Za-z0-9_-]+\.yaml)"?(?=\s|$|\|)/gm)) if (f.startsWith('.maestro/') || f === entry) { const p = '.maestro/' + m[1]; if (rd(p) !== null) refs.add(p); }
    for (const r of refs) if (!files.has(r)) { const c = rd(r); if (c !== null) { files.set(r, c); todo.push(r); } }
  }
  return { entry, files, cm: entry === 'codemagic.yaml', rd };
}
const lines = (files, re) => { const out = []; for (const [f, t] of files) t.split('\n').forEach((l, i) => { if (re(f, l)) out.push(`${f}:${i + 1}: ${l.trim().slice(0, 140)}`); }); return out; };
const code = (l) => !/^\s*(#|\/\/)/.test(l);
const ok = (l, id) => l.includes('lint-ok:' + id);





function timeTotal(w, files, hasDl, dl) {


  const unroll = (t) => t.replace(/for \w+ in ([^;\n]+); do([^\n]*?); done/g, (z, ws, b) => b.repeat(ws.trim().split(/\s+/).length))
    .replace(/for \w+ in ([^;\n]+); do[ \t]*\n([\s\S]*?)\n\s*done/g, (z, ws, b) => b.repeat(ws.trim().split(/\s+/).length));
  const body = (t) => t.split('\n').filter((l) => !/^\s*#/.test(l) && !/^\s*(lim|limf|rd|mt|cm_time|cm_left|cm_publish)\(\)/.test(l)).join('\n');
  const texts = [unroll(body(w))];
  for (const m of w.matchAll(/bash (\.maestro\/[a-z0-9-]+\.sh)/g)) texts.push(unroll(body(files.get(m[1]) || '')));
  let lim = 0, nLim = 0, fix = 0, nFix = 0, sl = 0;
  for (const t of texts) {
    for (const x of t.matchAll(/(?:^|[\s;(&|{$'"])(lim|limf|rd) ([0-9]+) /gm)) { if (x[1] === 'lim') { lim += +x[2]; nLim++; } else { fix += +x[2]; nFix++; } }
    for (const x of t.matchAll(/MT_LIMIT=([0-9]+) mt /g)) { lim += +x[1] - 300; }
    for (const x of t.matchAll(/(?:^|[\s;])mt ["$a-z]/gm)) { lim += 300; nLim++; }
    for (const x of t.matchAll(/(?:^|[\s;])sleep ([0-9]+)/gm)) sl += +x[1];
  }
  const pt = ((files.get('.maestro/cm-lim.sh') || '').match(/\ncm_quiet\(\)[\s\S]*$/) || [''])[0];
  const pl = [...pt.matchAll(/limf ([0-9]+) /g)].map((x) => +x[1]); const pub1 = pl.length ? pl.reduce((a, b) => a + b + 5, 0) : 999; const np = Math.max(1, (w.match(/trap cm_publish EXIT/g) || []).length); const pub = pub1 * np;




  const guard = /DEADLINE: step [^\n]* not started/.test(files.get('.maestro/cm-lim.sh') || '');
  if (hasDl && guard) {
    const parts = w.split(/\n    publishing:/); const steps = parts[0].split(/\n      - name:/).slice(1);
    const cost = (txt, seen) => { let f = 0, n = 0, s = 0; const t = unroll(body(txt));
      for (const x of t.matchAll(/(?:^|[\s;(&|{$'"])(limf|rd) ([0-9]+) /gm)) { f += +x[2]; n++; }
      for (const x of t.matchAll(/(?:^|[\s;])sleep ([0-9]+)/gm)) s += +x[1];
      for (const m of t.matchAll(/bash (\.maestro\/[a-z0-9-]+\.sh)/g)) if (!seen.has(m[1])) { seen.add(m[1]); const c = cost(files.get(m[1]) || '', seen); f += c.f; n += c.n; s += c.s; }
      return { f, n, s }; };
    let worst = 0, wi = '?';
    for (const st of steps) { const c = cost(st, new Set()); const v = c.f + 5 * c.n + c.s; if (v > worst) { worst = v; wi = st.split('\n')[0].trim().split(' - ')[0]; } }
    const pc = cost(parts[1] || '', new Set()); const pv = pc.f + 5 * pc.n + pc.s;
    const total = dl + 5 + worst + pub1 + pv + 5 * steps.length;
    return { total, text: `deadline ${dl} + last cut 5 + the step crossing it (worst: ${wi}, fixed limits + 5 each + sleeps = ${worst}) + publish 1 x ${pub1} + publishing ${pv} + ${steps.length} steps x 5 at the guard` };
  }
  if (hasDl) { const total = dl + 5 + fix + 5 * nFix + pub; return { total, text: `deadline ${dl} + last cut 5 + ${nFix} fixed limits ${fix} + ${5 * nFix} + publish ${np} x ${pub1}` }; }
  const total = lim + fix + sl + 5 * (nLim + nFix) + pub;
  return { total, text: `${nLim + nFix} limits ${lim + fix} + sleeps ${sl} + kill grace ${5 * (nLim + nFix)} + publish ${np} x ${pub1} (quiet + scrub + status, +5 each)` };
}
const flow = (f) => f.startsWith('.maestro/') && /\.yaml$/.test(f);
const ITEMS = [
  { id: 'abs-screenshot', run: 'run 1 (12e1450)', control: '12e1450',
    why: 'Maestro takeScreenshot with an absolute or ${OUT} path wrote outside the test output; run 1 had no screenshots',
    check: ({ files }) => lines(files, (f, l) => flow(f) && code(l) && /takeScreenshot:\s*["']?(\/|\$\{)/.test(l)) },
  { id: 'personal-mode-form', run: 'run 1 (12e1450)', control: '12e1450',
    why: 'the phone opens in personal mode; the ID/password form must be opened first (when visible "ID・パスワードでログイン")',
    check: ({ files }) => { const h = []; for (const [f, t] of files) if (flow(f) && /inputText:\s*\$\{LOGIN_ID\}/.test(t) && !/visible:\s*"ID・パスワードでログイン"/.test(t)) h.push(`${f}: types LOGIN_ID without opening the ID/password form`); return h; } },
  { id: 'boot-before-build', run: 'run 2 (9baff16)', control: '9baff16',
    why: 'run 2: cold boot took 7m15s after the build and the driver was not ready; the iPhone must boot before the build',
    check: ({ entry, files }) => { const t = files.get(entry); const b = t.search(/simctl boot\b/); const x = t.search(/xcodebuild -workspace[^\n]*-scheme/); return (b >= 0 && x >= 0 && b < x) ? [] : [`${entry}: simctl boot at ${b}, xcodebuild build at ${x} (boot must come first)`]; } },
  { id: 'caps-bounded', run: 'run 4 (74588a8)', control: '74588a8',
    why: 'run 4 hit the 60-minute job cap mid-flow with no artifact; every long command needs its own cap inside one deadline',
    check: ({ cm, entry, files }) => {
      const h = [];
      if (cm) {
        const y = files.get(entry);
        const heavy = /\b(npm ci|pod install|expo prebuild|xcodebuild -workspace|maestro"? --device|maestro[^\n]* test |simctl bootstatus|get\.maestro\.mobile\.dev|curl -fsSL -o |unzip -q)/;
        h.push(...lines(files, (f, l) => code(l) && heavy.test(l) && !/\b(lim|limf|rd)\s+("?\$\{?[A-Z_]+(:-[0-9]+)?\}?"?|[0-9]+)\s/.test(l) && !/^\s*(echo |- name:)/.test(l)));
        for (const w of y.split(/\n  (?=[a-z0-9-]+:\s*\n)/).slice(1)) {
          const mb = w.match(/max_build_duration:\s*([0-9]+)/), dl = w.match(/CM_DEADLINE_SEC:\s*"([0-9]+)"/);
          if (mb && dl && +dl[1] > +mb[1] * 60 - 300) h.push(`${entry}: ${w.split(':')[0]} CM_DEADLINE_SEC ${dl[1]} leaves under 300 s of ${mb[1]} min for clean-up and publishing`);
          if (mb) { const t = timeTotal(w, files, !!dl, dl ? +dl[1] : 0); const cap = +mb[1] * 60;
            console.log(`TIME ${w.split(':')[0]}: ${t.text} = ${t.total} s; max_build_duration ${mb[1]} min = ${cap} s; room ${cap - t.total} s (needs >= 120)`);
            if (t.total > cap - 120) h.push(`${entry}: ${w.split(':')[0]} worst case ${t.total} s > max_build_duration ${cap} s - 120 s (${t.text})`);

            const note = (w.match(/max_build_duration:[^\n]*?worst case ([0-9]+) s/) || [])[1];
            if (note !== undefined && +note !== t.total) h.push(`${entry}: ${w.split(':')[0]} max_build_duration note says worst case ${note} s, lint counts ${t.total} s`);
            if (note === undefined && /ios-env-probe/.test(w.split(':')[0])) h.push(`${entry}: ios-env-probe max_build_duration line has no "worst case N s" note`); }
        }
        if (!/CM_DEADLINE_SEC/.test(y)) h.push(`${entry}: no deadline`);
      } else {
        const y = files.get(entry); const job = +((y.match(/^    timeout-minutes:\s*([0-9]+)/m) || [])[1] || 0);
        const steps = y.split(/\n      - name:/).slice(1);
        const nocap = steps.filter((s) => /\n        run:/.test(s) && !/\n        timeout-minutes:/.test(s)).length;
        const sum = steps.reduce((a, s) => a + +((s.match(/\n        timeout-minutes:\s*([0-9]+)/) || [])[1] || 0), 0);
        if (nocap) h.push(`${entry}: ${nocap} run steps without timeout-minutes`);
        if (sum > job) h.push(`${entry}: step caps ${sum} min > job cap ${job} min`);
      }
      return h; } },
  { id: 'no-js-swap', run: 'runs 4-6 (74588a8, 2fcb59f, 7728b28)', control: '2fcb59f',
    why: 'runs 4-6 swapped the JS (export:embed into the .app); run 5 failed on the swap path. Build the real JS only',
    check: ({ files }) => lines(files, (f, l) => code(l) && (/export:embed/.test(l) || /(>|cp\s[^\n]*|writeFileSync\([^\n]*)main\.jsbundle/.test(l))) },
  { id: 'no-qr-patch', run: 'runs 6-8 (7728b28, a963ed2, ebf314a)', control: '7728b28',
    why: 'runs 6-8 patched app code in CI (ci-qr-patch.js); CI may only turn expo-updates off in app.json',
    check: ({ files }) => lines(files, (f, l) => code(l) && (/ci-qr-patch/.test(l) || /sed -i[^\n]*\b(src|app)\//.test(l) || /writeFileSync\(['"](src|app)\//.test(l))) },
  { id: 'cap-too-small', run: 'run 7 (a963ed2)', control: 'a963ed2',
    why: "run 7: the env step was killed by timeout-minutes: 1 (job log line 315). No cap under 10 s, no GitHub step cap under 3 min",
    check: ({ files }) => lines(files, (f, l) => code(l) && (/timeout-minutes:\s*[12]\s*$/.test(l) || /\b(lim|limf|rd)\s+([0-9]|[0-9]?[0-9]?)\s/.test(l) && +l.match(/\b(?:lim|limf|rd)\s+([0-9]+)\s/)?.[1] < 10)) },
  { id: 'login-net-diag', run: 'run 8 (ebf314a)', control: 'ebf314a',
    why: 'run 8: the login failed with a network error and nothing recorded why or tried again; netcheck + one resubmit required',
    check: ({ files }) => { const all = [...files.values()].join('\n'); const h = []; if (!/netcheck\.sh/.test(all)) h.push('no netcheck.sh call'); if (![...files.keys()].some((f) => /retry/.test(f))) h.push('no retry flow reached'); return h; } },
  { id: 'login-net-wait', run: '[B] a-look GitHub Actions 45069836554: the pre-login netcheck said http=000, "|| true" went on, the login flow ran into its limit', control: '57e6215',
    why: 'head 2d (commander 2026-11-23): the code line before mt login is the net wait (cm-netwait.sh under lim, GATE net FAIL + exit 1, no "|| true"); netcheck.sh counts only an http= code as reached',
    check: ({ files }) => { const h = []; const r = (files.get('.maestro/cm-run.sh') || '').split('\n').filter((l) => code(l));
      const i = r.findIndex((l) => /(^|[\s;])mt login /.test(l)); const p = i > 0 ? r[i - 1] : '';
      if (i < 0) h.push('cm-run.sh: no mt login line'); else if (!/lim [0-9]+ bash \.maestro\/cm-netwait\.sh/.test(p) || !/GATE net FAIL/.test(p) || !/exit 1/.test(p) || /\|\| true/.test(p)) h.push('cm-run.sh: the line before mt login is not the net wait gate: ' + p.trim().slice(0, 90));
      const n = (files.get('.maestro/netcheck.sh') || '').split('\n').filter((l) => code(l) && l.trim()); if (/^exit 0$/.test((n[n.length - 1] || '').trim())) h.push('netcheck.sh: ends in exit 0 (no http code counted as reached)');
      return h; } },
  { id: 'failed-step-record', run: 'commander 2026-11-23 (head 2d): a failed flow left no record of the step it ended on', control: 'synthetic',
    why: 'cm-steps.js prints only kind / step number / result / seconds (no text, value or ID); every label in the trial flows is cm-<a-z0-9->; cm-run.sh mt() runs it after a failed flow; its lines are KEEP lines',
    synth: () => ({ files: new Map([['.maestro/cm-steps.js', "out.push(`failed-step flow ${fl} step ${i + 1} ${t}`);"], ['.maestro/cm-run.sh', 'mt() {\n}\n'], ['.maestro/trial-x.yaml', '    label: Login button\n']]) }),
    check: ({ files }) => { const h = []; const s = files.get('.maestro/cm-steps.js');
      const OKX = new Set(['fl', 'i + 1', 'last + 1', 'r.kind', 'r.st', 'rows[last].kind', 'rows[last].st', 'sec(i)', 'sec(last)', 'ss', 'rows.length', 'nOther', "cls ? '; classes ' + cls : ''", "/^[a-z0-9-]{1,20}$/.test(flow || '') ? flow : 'x'"]);
      if (!s) h.push('.maestro/cm-steps.js not reached from the CI entry'); else for (const m of s.matchAll(/\$\{([^}]*(?:\{[^}]*\}[^}]*)*)\}/g)) if (!OKX.has(m[1].trim())) h.push('cm-steps.js prints ${' + m[1].slice(0, 40) + '} (only kind, step, result, seconds)');
      for (const [f, t] of files) if (/^\.maestro\/trial-[a-z0-9-]+\.yaml$/.test(f)) t.split('\n').forEach((l, i) => { const m = l.match(/^\s*label:\s*(.*?)\s*$/); if (m && !/^cm-[a-z0-9-]{2,40}$/.test(m[1])) h.push(`${f}:${i + 1}: label is not cm-<a-z0-9-> (${m[1].length} chars)`); });
      const r = files.get('.maestro/cm-run.sh') || ''; const mt = (r.match(/\nmt\(\) \{[\s\S]*?\n\}/) || [''])[0];
      if (!/\[ "\$r" = 0 \] \|\| (?:SR=\$\()?lim [0-9]+ node \.maestro\/cm-steps\.js/.test(mt)) h.push('cm-run.sh mt(): no failed-step record after a failed flow');
      const st = files.get('.maestro/cm-s2-status.js'); if (st && !/const KEEP = [^\n]*failed-step flow/.test(st)) h.push('cm-s2-status.js: failed-step lines are not KEEP lines');
      return h; } },
  { id: 'logins-blob-record', run: 'commander 2026-11-23 (head 2d): E2E_DEV_LOGINS_B64 holds all 39 dev values; stage 2 records it, never uses it', control: 'synthetic',
    why: 'cm-blob.js prints one fixed-shape line (counts, yes/no) and no error text; gate a calls it with a fallback (never a stop); cm-lim.sh takes the blob out of every stage 2 step environment; its line is a KEEP line',
    synth: () => ({ files: new Map([['.maestro/cm-blob.js', 'console.log(o.E2E_SUPER_PASSWORD); console.log(e.message);'], ['codemagic.yaml', '          node .maestro/cm-blob.js || exit 1\n'], ['.maestro/cm-lim.sh', 'export -n GH_STATUS_TOKEN\n']]) }),
    check: ({ files }) => { const h = []; const s = files.get('.maestro/cm-blob.js');
      if (!s) h.push('.maestro/cm-blob.js not reached from the CI entry'); else { const OK = new Set(['record(process.env)', "'logins-blob record failed'"]);
        for (const m of s.matchAll(/console\.(?:log|error|warn)\(([^;]*?)\);/g)) if (!OK.has(m[1].trim())) h.push('cm-blob.js prints ' + m[1].slice(0, 40) + ' (only the record line)');
        if (/process\.std(out|err)\.write|fs\.write/.test(s)) h.push('cm-blob.js writes outside console.log'); }
      const y = files.get('codemagic.yaml') || ''; const c = y.split('\n').filter((l) => code(l) && l.includes('cm-blob.js'));
      if (c.length !== 1) h.push('codemagic.yaml: cm-blob.js called ' + c.length + ' times (want 1, gate a)');
      c.forEach((l) => { if (!/\) \|\| BL="logins-blob [^"]*"; cm_say "\$BL"/.test(l)) h.push('codemagic.yaml: cm-blob.js without the record fallback: ' + l.trim().slice(0, 80)); });
      if (!/export -n [^\n]*E2E_DEV_LOGINS_B64/.test(files.get('.maestro/cm-lim.sh') || '')) h.push('cm-lim.sh: E2E_DEV_LOGINS_B64 stays in the stage 2 step environment'); if (!/unset GH_STATUS_TOKEN E2E_DEV_LOGINS_B64/.test(files.get('.maestro/cm-probe.sh') || '')) h.push('cm-probe.sh: E2E_DEV_LOGINS_B64 stays in the stage 1 environment');
      const st = files.get('.maestro/cm-s2-status.js'); if (st && !/const KEEP = [^\n]*logins-blob /.test(st)) h.push('cm-s2-status.js: logins-blob is not a KEEP line');
      return h; } },
  { id: 'stage1-list-reads', run: 'commander 2026-11-23: head 2d part 1 (813c31e) was built beside head 1e/1f and had no list-data read and a 30 s cognito-auth', control: '813c31e',
    why: 'the stage 1 piece (cm-probe.sh) keeps the head 1e reads: cognito-auth = rd 60 node cm-auth.js with the list.txt file (sign-in 20 + reads 30), then fact list-data from that file; cm-auth.js writes the list-data line',
    check: ({ files }) => { const h = []; const p = files.get('.maestro/cm-probe.sh');
      if (!p) return ['.maestro/cm-probe.sh not reached from the CI entry'];
      const L = p.split('\n').filter((l) => code(l));
      if (!L.some((l) => /fact cognito-auth "\$\(rd 60 'node \.maestro\/cm-auth\.js "'"\$P"'\/list\.txt"'\)"/.test(l))) h.push('cm-probe.sh: no cognito-auth read = rd 60 node .maestro/cm-auth.js "$P/list.txt" (head 1e)');
      if (!L.some((l) => /^fact list-data "\$\{GD:-/.test(l))) h.push('cm-probe.sh: no fact list-data line (head 1e)');
      if (!L.some((l) => /^GD=\$\(sed -n 's\/\^list-data \/\/p' "\$P\/list\.txt"/.test(l))) h.push('cm-probe.sh: list-data is not read from $P/list.txt (head 1e)');
      const a = files.get('.maestro/cm-auth.js'); if (!a || !/list-data /.test(a)) h.push('cm-auth.js: no list-data line written (head 1e)');
      return h; } },
  { id: 'screen-press-checked', run: 'E section 25 at 632614ee1: trial-list.yaml:49 opened the record with no check after it (a false pass)', control: '57e6215',
    why: 'every tapOn / pressKey Enter in the Codemagic trial flows is followed (next command at the same or an outer level) by a check of the screen it leads to (extendedWaitUntil / assertVisible / assertNotVisible), or is a field press followed by inputText / pressKey; else lint-ok with the reason',
    check: ({ files }) => { const h = [];
      for (const [f, t] of files) { if (!/^\.maestro\/trial-(login|home|retry|list)\.yaml$/.test(f)) continue;
        const ls = t.split('\n'); const cmd = ls.map((l, i) => ({ i, m: l.match(/^(\s*)- ([A-Za-z]+)/) })).filter((x) => x.m && !/^\s*#/.test(ls[x.i]));
        cmd.forEach((c, k) => { const kind = c.m[2]; const ind = c.m[1].length;
          if (kind !== 'tapOn' && !(kind === 'pressKey' && /Enter/.test(ls[c.i]))) return; if (ok(ls[c.i], 'screen-press-checked')) return;
          const nx = cmd.slice(k + 1).find((d) => d.m[1].length <= ind); const nk = nx ? nx.m[2] : 'end of flow';
          const good = ['extendedWaitUntil', 'assertVisible', 'assertNotVisible'].includes(nk) || (kind === 'tapOn' && ['inputText', 'pressKey'].includes(nk));
          if (!good) h.push(`${f}:${c.i + 1}: ${kind} then ${nk} (no check of the screen it leads to)`); }); }
      return h; } },
  { id: 'hidekeyboard-optional', run: 'run 9 prep (2720465, found on the emulator before run 9)', control: '2720465',
    why: 'hideKeyboard throws when the keyboard stays up on iOS; it must be optional and iOS-only',
    check: ({ files }) => lines(files, (f, l) => flow(f) && code(l) && /^\s*-\s*hideKeyboard\s*$/.test(l)) },
  { id: 'first-item', run: "B's GitHub Actions free rehearsal 1 (schemes[0] = EASClient); same form in runs 1-9", control: 'ebf314a',
    why: 'never take the first or last entry of a list or a glob; name it and check it is there exactly once',
    check: ({ files }) => lines(files, (f, l) => code(l) && !ok(l, 'first-item') &&
      (/sed -n ['"]?(1|\$)p/.test(l) || /\b(head|tail)\s+(-1\b|-n\s*1\b)/.test(l) || /\[0\]/.test(l) || /\.find\(/.test(l) || /ls -d [^|;]*\*[^|;]*\|/.test(l))) },
  { id: 'early-reader', run: "B's GitHub Actions free rehearsal 2 (xcodebuild -version | grep -q: SIGPIPE under pipefail failed a good check); runs 1-9 had | head -1", control: 'synthetic+ebf314a',
    why: 'a reader that stops early (grep -q/-m, head, awk exit, sed q) after a pipe kills the writer under pipefail; take the whole output into a variable or file first',
    check: ({ files }) => lines(files, (f, l) => code(l) && !ok(l, 'early-reader') && /\.(sh|yaml|yml)$/.test(f) &&
      /\|\s*(\{\s*)?(grep\s+(-[a-zA-Z]*[qm]|[^|]*\s-[a-zA-Z]*[qm]\b)|head\b|awk\b[^|]*\bexit\b|sed\b[^|]*[0-9$]q\b)/.test(l)) },
  { id: 'artifacts-scrubbed', run: '[L] commander 2026-11-22: B practice found the typed password in maestro commands.json / maestro.log', control: '06ce89c',
    why: 'artifacts may name only upload/, which only cm_publish fills after cm-scrub.js; a cancel before the scrub then uploads nothing new',
    check: ({ entry, files }) => { const y = files.get(entry) || ''; if (!/^codemagic\.yaml$/.test(entry)) return [];
      const h = []; let inA = false; y.split('\n').forEach((l, i) => { if (/^\s*artifacts:\s*$/.test(l)) { inA = true; return; }
        if (inA) { const m = l.match(/^\s*-\s*(\S+)/); if (m) { if (!/^upload\//.test(m[1])) h.push(`${entry}:${i + 1}: artifact ${m[1]} is not under upload/`); } else inA = false; } });
      return h; } },
  { id: 'grep-count-guard', run: '[L] pipefail: a 0-hit grep ends the step (draft RESULT §31)', control: 'synthetic',
    why: 'under pipefail, grep with 0 hits returns 1; every counting grep must be { grep ... || true; } or end with || true',
    check: ({ files }) => lines(files, (f, l) => code(l) && /\.(sh|yaml|yml)$/.test(f) && /\bgrep\b[^|]*\|\s*wc -l/.test(l) && !/\|\|\s*true/.test(l)) },
  { id: 'no-secret-echo', run: '[L] values never printed', control: 'synthetic',
    why: 'the login values must never reach a log: no echo/printf of them, no set -x',
    check: ({ files }) => lines(files, (f, l) => code(l) && (/(echo|printf)[^\n]*\$\{?(LOGIN_PW|LOGIN_ID|E2E_0003_PASSWORD|E2E_0003_LOGIN|GH_STATUS_TOKEN)\b/.test(l) || /^\s*set -[a-z]*x/.test(l))) },
  { id: 'no-fault-hook', run: '[L] commander 2026-11-22: the practice fault hook must never be set on Codemagic', control: 'synthetic',
    why: 'cm-run.sh calls FAULT_HOOK only when it is set (practice); codemagic.yaml must not name it at all',
    check: ({ entry, files }) => (/codemagic\.yaml$/.test(entry) ? lines(new Map([[entry, files.get(entry) || '']]), (f, l) => /FAULT_HOOK/.test(l)) : []) },
  { id: 'values-flows-files', run: '[L] commander 2026-11-22: values and flows moved out of the sh', control: '4983b26',
    why: 'cm-gates.sh bundle needs .maestro/cm-values.txt (>=1 "1" line, >=1 "0"/"0re" line, each "<kind> <one word>"); cm-run.sh needs .maestro/cm-flows.txt naming trial-list.yaml',
    check: ({ cm, rd }) => { if (!cm) return []; const h = [];
      const v = rd('.maestro/cm-values.txt'); if (v === null) h.push('.maestro/cm-values.txt missing'); else {
        const ls = v.split('\n').map((l) => l.replace(/\r$/, '')).filter((l) => l.trim() && !/^\s*#/.test(l));
        ls.forEach((l, i) => { if (!/^(1|0|0re) \S+$/.test(l)) h.push(`cm-values.txt line ${i + 1}: not "<1|0|0re> <one word>"`); });
        if (!ls.some((l) => /^1 /.test(l))) h.push('cm-values.txt: no "1" line'); if (!ls.some((l) => /^0(re)? /.test(l))) h.push('cm-values.txt: no "0"/"0re" line'); }
      const fl = rd('.maestro/cm-flows.txt'); if (fl === null) h.push('.maestro/cm-flows.txt missing');
      else if (!/^list trial-list\.yaml \S/m.test(fl)) h.push('cm-flows.txt: no "list trial-list.yaml <text>" line');
      return h; } },
  { id: 's1-covers', run: '[L] A 2026-11-22: stage 1 had no java read; stage 2 gate toolchain stops on java != 17', control: '4983b26',
    why: 'every fail message of the stage 2 early gates (cm-gates.sh toolchain, yaml gate a) has a row in .maestro/cm-s1-covers.txt naming the stage 1 fact (cm-probe.sh) that read it first, or pinned:<why>',
    check: ({ cm, rd }) => { if (!cm) return []; const h = []; const cv = rd('.maestro/cm-s1-covers.txt'); if (cv === null) return ['.maestro/cm-s1-covers.txt missing'];
      const rows = cv.split('\n').map((l) => l.replace(/\r$/, '')).filter((l) => l.trim() && !l.startsWith('#')).map((l) => l.split('\t'));
      const g = rd('.maestro/cm-gates.sh') || '', y = rd('codemagic.yaml') || '', p = rd('.maestro/cm-probe.sh') || '';
      const tc = (g.match(/\ntoolchain\)([\s\S]*?)\n  ;;/) || [])[1] || '';
      const need = [...[...tc.matchAll(/fail "([^"]+)"/g)].map((m) => ['gates-toolchain', m[1]]), ...[...y.matchAll(/GATE a FAIL: ([^"]+)"/g)].map((m) => ['yaml-a', m[1]])];
      if (!need.length) h.push('no stage 2 early gate fail messages found (reader broken)');
      for (const [pl, msg] of need) { const r = rows.find((x) => x[0] === pl && msg.startsWith(x[1])); if (!r) { h.push(`${pl} "${msg}": no row in cm-s1-covers.txt`); continue; }
        const k = r[2] || ''; if (k.startsWith('pinned:') && k.length > 12) continue;
        const reach = k.match(/^reach-(.+)$/);
        if (reach ? !new RegExp('for u in [^\\n]*https://' + reach[1].replace(/\./g, '\\.') + '/').test(p) : !new RegExp('^\\s*fact ' + k + ' ', 'm').test(p)) h.push(`${pl} "${msg}": stage 1 fact ${k} not in cm-probe.sh`); }
      return h; } },
  { id: 'nounset-safe', run: '[L] commander 2026-11-22: dc3bb99 cm-probe.sh:23 \${#E2E_0003_LOGIN} under set -u ended the probe (rc=127) with no fact read when the value is not set', control: 'dc3bb99',
    why: 'in every .maestro script under set -u (and cm-lim.sh, sourced into them) each $NAME / \${NAME} / \${#NAME} is assigned in that script or cm-lim.sh, or read with a default (\${NAME:-...}); single-quoted text (perl, bash -c, awk) is not this shell',
    check: ({ files }) => { const h = []; const SAFE = new Set(['PWD', 'PPID', 'UID', 'IFS', 'PATH', 'BASH_SOURCE', 'BASH_LINENO', 'FUNCNAME', 'LINENO', 'RANDOM', 'SECONDS', 'OPTIND']);


      const clean = (t) => { let o = '', st = 0; for (let i = 0; i < t.length; i++) { const c = t[i];
        if (st === 1) { o += c === '\n' ? c : ' '; if (c === "'") st = 0; continue; }
        if (st === 3) { if (c === '\n') { st = 0; o += c; } else o += ' '; continue; }
        if (c === '\\') { o += c + (t[i + 1] || ''); i++; continue; }
        if (st === 2) { o += c; if (c === '"') st = 0; continue; }
        if (c === "'") { st = 1; o += ' '; continue; } if (c === '"') { st = 2; o += c; continue; }
        if (c === '#' && (i === 0 || /\s/.test(t[i - 1]))) { st = 3; o += ' '; continue; } o += c; } return o; };
      const defs = (t) => { const d = new Set(); for (const m of t.matchAll(/(?:^|[\s;(&|{])(?:local |export |readonly )?([A-Za-z_]\w*)=/gm)) d.add(m[1]);
        for (const m of t.matchAll(/(?:^|[\s;(&|{])(?:local|for|read(?: -[a-z]+)*)\s+([A-Za-z_][A-Za-z0-9_ ]*)/gm)) for (const x of m[1].split(/\s+/)) if (x && x !== 'in') d.add(x); return d; };
      const lim = clean(files.get('.maestro/cm-lim.sh') || ''); const limDefs = defs(lim);
      for (const [fn, raw] of files) { if (!/\.sh$/.test(fn)) continue; if (!/^set -[a-z]*u/m.test(raw) && !/cm-lim\.sh$/.test(fn)) continue;
        const t = clean(raw); const d = new Set([...defs(t), ...limDefs]);
        t.split('\n').forEach((l, i) => { for (const m of l.matchAll(/\$\{(#?)([A-Za-z_]\w*)([^}]*)\}|\$([A-Za-z_]\w*)/g)) { const n = m[2] || m[4]; if (SAFE.has(n) || d.has(n)) continue;
          if (m[2] && !m[1] && /^:?[-=+?]/.test(m[3])) continue; h.push(fn + ':' + (i + 1) + ': ' + m[0] + ' is read under set -u but never assigned here and has no default' + (/cm-(gates|run).sh$/.test(fn) ? ' [known: stage 2 only, fixed in head 2]' : '')); } });


        const gone = new Set(); t.split('\n').forEach((l, i) => { const lead = /^\S/.test(l);
          for (const m of l.matchAll(/\$\{(#?)([A-Za-z_]\w*)([^}]*)\}|\$([A-Za-z_]\w*)/g)) { const n = m[2] || m[4]; if (!gone.has(n)) continue;
            if (m[2] && !m[1] && /^:?[-=+?]/.test(m[3])) continue; h.push(fn + ':' + (i + 1) + ': ' + m[0] + ' is read under set -u after a top-level unset with no new assignment'); }
          for (const m of l.matchAll(/(?:^|[\s;(&|{])(?:local |export |readonly )?([A-Za-z_]\w*)=/g)) gone.delete(m[1]);
          const u = lead && l.match(/(?:^|;\s*)unset\s+((?:[A-Za-z_]\w*\s*)+)/); if (u) for (const x of u[1].trim().split(/\s+/)) gone.add(x); }); }
      return h; } },
  { id: 'no-node-e', run: '[B] GitHub Actions 45028159737 + 10: bash 3.2 brace-expanded a double-quoted node -e in cm-probe.sh, sim-runtimes and iphone-17-pro-count MISSING in 11 of 11', control: 'dc3bb99',
    why: 'no "node -e" in any .maestro .sh or in codemagic.yaml: JS lives in .js files (macOS /bin/bash 3.2 splits {a,b} inside it; bash 5 on this PC does not, so only B on the Mac would see it)',
    check: ({ files }) => { const h = []; for (const [fn, t] of files) if (/\.sh$/.test(fn) || fn === 'codemagic.yaml') t.split('\n').forEach((l, i) => { if (/\bnode -e\b/.test(l) && !/^\s*#/.test(l)) h.push(fn + ':' + (i + 1) + ': node -e'); }); return h; } },
  { id: 'tags-disjoint', run: '[L] commander 2026-11-22: only tag pushes start a build; a stage 1 tag must never start stage 2', control: 'synthetic',
    why: 'each workflow lists only the tag event and its own tag pattern; no pattern matches the other workflow\'s tag (cm-stage1-x vs cm-stage2-x)',
    synth: () => ({ cm: true, rd: (p) => p === 'codemagic.yaml' ? 'workflows:\n  one:\n    triggering:\n      events:\n        - tag\n      tag_patterns:\n        - pattern: "cm-stage*"\n  two:\n    triggering:\n      events:\n        - tag\n        - push\n      tag_patterns:\n        - pattern: "cm-stage2-*"\n' : null }),
    check: ({ cm, rd }) => { if (!cm) return []; const h = []; const y = rd('codemagic.yaml') || '';
      const ws = y.split(/\n  (?=[a-z0-9-]+:\s*\n)/).slice(1).map((w) => ({ name: w.split(':')[0], ev: (w.match(/events:\s*\n((?:\s+- \S+\s*(?:#[^\n]*)?\n)+)/) || [])[1] || '', pats: [...w.matchAll(/- pattern: "([^"]+)"/g)].map((m) => m[1]) }));
      const re = (p) => new RegExp('^' + p.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.') + '$');
      for (const w of ws) { const ev = [...w.ev.matchAll(/- (\S+)/g)].map((m) => m[1]); if (ev.join(',') !== 'tag') h.push(`${w.name}: events [${ev.join(',')}], expected only tag`); if (w.pats.length !== 1) h.push(`${w.name}: ${w.pats.length} tag patterns, expected 1`); }
      for (const a of ws) for (const b of ws) if (a !== b) for (const pa of a.pats) for (const pb of b.pats) { const sample = pb.replace(/\*/g, 'x'); if (re(pa).test(sample)) h.push(`${a.name} pattern ${pa} matches ${b.name}'s tag ${sample}`); }
      if (ws.length < 2) h.push('fewer than 2 workflows read (reader broken)');
      return h; } },
  { id: 'limits-inventory', run: '[B] GitHub Actions 45019189745 / 45020862644 (limits set at the desk, cut real work)', control: '4983b26',
    why: 'every time limit in the yaml and the .maestro scripts has a row in .maestro/cm-limits.txt with the same limit (measured max + source, or "-"); cm-limits.js check then judges >= 3x (head 2d: limits-3x lints it)',
    check: ({ cm, rd }) => cm ? require('./cm-limits.js').coverage(rd) : [] },
  { id: 'limits-3x', run: '[L] A, E on head 2c e4aba57: cm-limits.js read the deadline 1866 (cm-lim.sh default), the run uses 4800; xcodebuild 2780 < 3 x 1389 passed as "ok (deadline)"', control: 'e4aba57',
    why: 'every measured row of cm-limits.txt is >= 3x its measured max, or >= the ios-sim-verify CM_DEADLINE_SEC in codemagic.yaml (lim is cut there)',
    check: ({ cm, rd }) => cm ? require('./cm-limits.js').low(rd) : [] },
];
function lint(ref, only) {
  const c = collect(ref); const res = [];
  for (const it of ITEMS) if (!only || only === it.id) res.push({ id: it.id, hits: it.check(c) });
  return { c, res };
}
const arg = process.argv[2];
if (arg === '--controls') {
  let bad = 0;
  const synth = { 'grep-count-guard': '  N=$(grep -o -F "$v" "$B" | wc -l)', 'no-secret-echo': '  echo "id=$LOGIN_ID"',
    'early-reader': '  xcodebuild -version | grep -q "Xcode 26.6" || fail "xcode"' };
  for (const it of ITEMS) {
    let hits = [], pass = true;
    for (const ctl of it.control.split('+')) {
      const h = ctl === 'synthetic' ? (it.synth ? it.check(it.synth()) : it.id === 'no-fault-hook' ? it.check({ entry: 'codemagic.yaml', files: new Map([['codemagic.yaml', '      vars:\n        FAULT_HOOK: "x.sh"']]) })
        : it.check({ entry: 'x', files: new Map([['.maestro/x.sh', synth[it.id]]]) })) : lint(ctl, it.id).res[0].hits;
      if (!h.length) pass = false; hits = hits.concat(h);
    }
    if (!pass) bad++;
    console.log(`CONTROL ${it.id} on ${it.control}: ${pass ? 'HIT (control ok)' : 'NO HIT (control broken)'} n=${hits.length}${hits[0] ? ' first: ' + hits[0] : ''}`);
  }
  console.log(`controls ${ITEMS.length - bad}/${ITEMS.length} hit`); process.exit(bad ? 1 : 0);
}
const { c, res } = lint(arg);
console.log(`lint ${arg || 'working tree'} entry=${c.entry} files=${c.files.size}: ${[...c.files.keys()].join(' ')}`);
let n = 0;
for (const r of res) { n += r.hits.length; console.log(`${r.hits.length ? 'HIT ' : 'ok  '} ${r.id} (${ITEMS.find((i) => i.id === r.id).run}) n=${r.hits.length}`); for (const h of r.hits) console.log('     ' + h); }
console.log(`lint total hits=${n}`); process.exit(n ? 1 : 0);
