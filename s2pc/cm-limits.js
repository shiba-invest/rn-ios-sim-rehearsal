







const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');

const SH = ['cm-run.sh', 'cm-probe.sh', 'cm-gates.sh', 'netcheck.sh', 'cm-netwait.sh', 'cm-driver.sh', 'cm-driver-diag.sh', 'cm-probe-driver.sh', 'cm-screen.sh'];
const FLOWS = { 'trial-login.yaml': 'cm-run.sh:100', 'trial-home.yaml': 'cm-run.sh:84', 'trial-retry.yaml': 'cm-run.sh:109', 'trial-list.yaml': 'cm-run.sh:119' };



const JSRE = [['js-timer', /setTimeout\(\s*\(\)\s*=>.*?(?:abort\(\)|process\.exit\(|rej\().*?,\s*([0-9]+)\)/], ['js-within', /within\([^;]*?,\s*([0-9]+),\s*'/],
  ['js-signal', /AbortSignal\.timeout\(([0-9]+)\)/], ['js-opt', /\btimeout:\s*([0-9]+)\b/]];
const jsFiles = () => { try { return fs.readdirSync(__dirname).filter((f) => /\.js$/.test(f)).sort(); } catch (e) { return []; } };
function scanJs(place, l) { if (/^\s*\/\//.test(l)) return; for (const [cmd, re] of JSRE) { const m = l.match(re); if (m) add(place, cmd, +m[1] / 1000); } }
const rows = [];
const add = (place, cmd, limit) => rows.push({ place, cmd, limit: +limit });
const tok = (t) => path.basename(t.replace(/^["']+|["']+$/g, ''));
function scanLine(place, l) {
  const c = l.replace(/^\s+/, ''); if (c.startsWith('#') || /^\s*(lim|limf|rd|mt|cm_time|cm_left|cm_publish)\(\)/.test(c)) return;
  for (const m of l.matchAll(/(?:^|[\s;(&|{$'"])(lim|limf|rd) ([0-9]+) +(\S+)/g)) add(place, m[1] === 'rd' ? 'bash' : tok(m[3]), m[2]);
  const ct = place.startsWith('netcheck.sh:') && l.match(/\bcurl .*--max-time ([0-9]+)/); if (ct) add(place, 'curl', ct[1]);
  const mt = l.match(/(?:^|\s)(?:MT_LIMIT=([0-9]+) )?mt ["$a-z]/);
  if (mt && !/\bmt\(\)/.test(l)) add(place, 'maestro', mt[1] || 300);
}
const disk = (p) => { const f = path.join(ROOT, p); return fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : null; };
function scan(rd = disk) {
  rows.length = 0;
  const y = (rd('codemagic.yaml') || '').split('\n');
  for (let i = 0; i < y.length; i++) {
    const s = y[i].match(/^(\s*)script: \|\s*$/); if (!s) continue;
    const body = []; for (let j = i + 1; j < y.length && (y[j].trim() === '' || y[j].search(/\S/) > s[1].length); j++) body.push(y[j]);
    const tag = ((body.join('\n').match(/cm-lim\.sh step=(\S+?)[;\s]/) || [])[1]) || '?';
    body.forEach((l, k) => scanLine(`yaml-${tag}:${k + 1}`, l));
  }
  for (const f of SH) { const t = rd('.maestro/' + f); if (t !== null) t.split('\n').forEach((l, k) => scanLine(`${f}:${k + 1}`, l)); }
  for (const f of Object.keys(FLOWS)) { const t = rd('.maestro/' + f); if (t !== null) t.split('\n').forEach((l, k) => { const w = l.match(/^\s*timeout: ([0-9]+)\s*$/); if (w) add(`${f}:${k + 1}`, 'wait', +w[1] / 1000); }); }
  for (const f of jsFiles()) { const t = rd('.maestro/' + f); if (t !== null) t.split('\n').forEach((l, k) => scanJs(`${f}:${k + 1}`, l)); }
  const lim = (rd('.maestro/cm-lim.sh') || '').match(/cm_publish\(\)[\s\S]*?limf ([0-9]+) (\S+)/);
  if (lim) add('publish', tok(lim[2]), lim[1]);
  return rows.slice();
}
const key = (r) => `${r.place} ${r.cmd}`;
function readInv(rd = disk) {
  const t = rd('.maestro/cm-limits.txt'); if (t === null) return null;
  return t.split('\n').filter((l) => l.trim() && !l.startsWith('#') && !/^driver-(start|start-first|stall)-s\t/.test(l)).map((l) => {
    const [place, cmd, limit, max, ...src] = l.split('\t'); return { place, cmd, limit: +limit, max: max === '-' ? null : +max, src: src.join(' ') }; });
}
function measured(files) {
  const m = new Map();
  for (const f of files) {
    const st = fs.statSync(f); const list = st.isDirectory() ? fs.readdirSync(f).filter((x) => /lim-times.*\.txt$/.test(x)).map((x) => path.join(f, x)) : [f];
    for (const p of list) for (const l of fs.readFileSync(p, 'utf8').split('\n')) {
      const x = l.match(/^(\S+) limit=([0-9]+) took=([0-9]+) rc=([0-9]+) cmd=(\S+)$/); if (!x) continue;
      const k = `${x[1]} ${x[5]}`; const e = m.get(k) || { n: 0, max: 0, over: 0, cut: 0, files: new Set() };
      e.n++; e.max = Math.max(e.max, +x[3]); if (x[4] === '142') e.over++; e.limSeen = +x[2]; e.files.add(p); m.set(k, e);
    }
  }
  return m;
}

function coverage(rd = disk) {
  const c = scan(rd), i = readInv(rd); if (!i) return ['.maestro/cm-limits.txt missing'];
  const h = [], ii = new Map(i.map((r) => [key(r), r])), cc = new Map(c.map((r) => [key(r), r]));
  for (const r of c) { const x = ii.get(key(r)); if (!x) h.push(`limit not in cm-limits.txt: ${key(r)} ${r.limit}`); else if (x.limit !== r.limit) h.push(`limit ${key(r)}: code ${r.limit}, cm-limits.txt ${x.limit}`); }
  for (const r of i) if (!cc.has(key(r))) h.push(`cm-limits.txt row not in the code: ${key(r)}`);




  const outer = new Map();
  const callers = ['codemagic.yaml', ...SH.map((f) => '.maestro/' + f), '.maestro/cm-lim.sh'].map((f) => rd(f) || '').join('\n');
  for (const r of i) {
    const m = r.src.match(/\binside ([^\s;]+)/);
    if (!m) { if (/^js-/.test(r.cmd)) h.push(`${key(r)}: a js limit names no "inside <place>" (the shell limit around it)`); continue; }
    if (m[1] === '-') { const f = r.place.split(':')[0]; if (callers.includes(f)) h.push(`${key(r)}: says "inside -" but a build step runs ${f}`); continue; }
    for (const p of m[1].split(',')) outer.set(p, (outer.get(p) || 0) + r.limit);
  }
  for (const [p, sum] of outer) {
    const o = i.filter((r) => r.place === p); if (!o.length) { h.push(`inside ${p}: no such row`); continue; }
    const lim = Math.min(...o.map((r) => r.limit)); if (sum > lim) h.push(`inside ${p}: inner limits ${sum} s > its limit ${lim} s`);
  }
  return h;
}



function deadline(rd = disk) {
  const y = rd('codemagic.yaml') || ''; const w = y.split(/\n  (?=[a-z0-9-]+:\s*\n)/).find((s) => s.startsWith('ios-sim-verify:')) || '';
  return +((w.match(/CM_DEADLINE_SEC:\s*"([0-9]+)"/) || [])[1] || 0);
}
const verdict = (limit, max, over, dl) => max < 0 ? 'UNMEASURED' : (over ? 'OVER (rc 142)' : (limit >= 3 * Math.max(max, 1) ? 'ok' : (dl && limit >= dl ? 'ok (deadline)' : 'LOW')));

function low(rd = disk) {
  const i = readInv(rd); if (!i) return ['.maestro/cm-limits.txt missing']; const dl = deadline(rd); const h = [];
  if (!dl) h.push('codemagic.yaml: no CM_DEADLINE_SEC in ios-sim-verify (reader broken or missing)');
  for (const r of i) if (r.max !== null && verdict(r.limit, r.max, 0, dl) === 'LOW') h.push(`${key(r)}: limit ${r.limit} < 3 x ${r.max} = ${3 * r.max} and < the deadline ${dl}`);
  return h;
}
module.exports = { scan, coverage, deadline, verdict, low };
if (require.main === module) main();
function main() {
const [cmd, ...args] = process.argv.slice(2);
const code = scan(); const INV = path.join(__dirname, 'cm-limits.txt');
if (cmd === 'scan') { for (const r of code) console.log(`${r.place}\t${r.cmd}\t${r.limit}`); process.exit(0); }
const inv = readInv();
if (!inv) { console.log(`LIMITS FAIL: ${path.relative(ROOT, INV)} missing`); process.exit(1); }
const mm = measured(args);
if (cmd === 'fill') {
  const out = fs.readFileSync(INV, 'utf8').split('\n').map((l) => {
    if (!l.trim() || l.startsWith('#')) return l; const p = l.split('\t'); const e = mm.get(`${p[0]} ${p[1]}`);
    if (!e) return l; const old = p[3] === '-' ? 0 : +p[3];
    if (e.max >= old) { p[3] = String(e.max); p[4] = `${e.files.size} lim-times file(s), ${e.n} runs of it`; } return p.join('\t'); });
  fs.writeFileSync(INV, out.join('\n')); console.log(`filled from ${args.length} path(s)`); process.exit(0);
}
let bad = 0; const ci = new Map(code.map((r) => [key(r), r])), ii = new Map(inv.map((r) => [key(r), r]));
for (const r of code) { const i = ii.get(key(r)); if (!i) { console.log(`LIMITS not in the inventory: ${key(r)} limit ${r.limit}`); bad++; } else if (i.limit !== r.limit) { console.log(`LIMITS differs: ${key(r)} code ${r.limit} inventory ${i.limit}`); bad++; } }
for (const i of inv) if (!ci.has(key(i))) { console.log(`LIMITS in the inventory but not in the code: ${key(i)}`); bad++; }
for (const k of mm.keys()) if (!ii.has(k)) { console.log(`LIMITS measured but not in the inventory: ${k}`); bad++; }
let unm = 0, low = 0;
const DL = deadline();
console.log(`deadline ${DL} s (codemagic.yaml ios-sim-verify CM_DEADLINE_SEC)`);
console.log('place\tcommand\tlimit\tmeasured max\t3x\tverdict\tsource');
for (const i of inv) {
  const e = mm.get(key(i)); const max = Math.max(i.max ?? -1, e ? e.max : -1);
  const v = verdict(i.limit, max, e && e.over, DL);
  if (v === 'UNMEASURED') unm++; else if (!v.startsWith('ok')) low++;
  console.log(`${i.place}\t${i.cmd}\t${i.limit}\t${max < 0 ? '-' : max}\t${max < 0 ? '-' : 3 * max}\t${v}\t${e ? `${e.n} in the given files` : i.src}`);
}
for (const [f, at] of Object.entries(FLOWS)) {
  const ws = code.filter((r) => r.place.startsWith(f + ':')).reduce((a, r) => a + r.limit, 0); const m = ii.get(`${at} maestro`);
  const fits = m && m.max !== null && ws + m.max <= m.limit; if (!fits) low++;
  console.log(`WAITS ${f}: sum ${ws} + measured flow ${m && m.max !== null ? m.max : '-'} <= MT_LIMIT ${m ? m.limit : '-'} (${at}): ${fits ? 'ok' : 'LOW'}`); }
console.log(`LIMITS RESULT: rows=${inv.length} code-mismatch=${bad} unmeasured=${unm} low-or-over=${low}`);
process.exit(bad || unm || low ? 1 : 0);
}
