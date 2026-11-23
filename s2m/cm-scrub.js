








const fs = require('fs');
const path = require('path');
const [dir, held, countFile] = process.argv.slice(2);
const pw = process.env.LOGIN_PW || '';
const id0 = process.env.LOGIN_ID || '';
const id = id0.padStart(3, '0');
const tok = process.env.GH_STATUS_TOKEN || '';
if (!dir || !held || !countFile) { console.error('scrub: usage <dir> <withheld> <count file>'); process.exit(1); }
if (pw.length < 4 || id0.length < 1 || id.length < 3) { console.error('scrub: LOGIN_PW or LOGIN_ID missing or too short to search safely'); process.exit(1); }
if (!fs.existsSync(dir)) { console.log('scrub: no dir'); process.exit(0); }
const TEXT = /\.(log|txt|json|ya?ml|html|xml|csv|md)$/i;
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const idRe = new RegExp('(?<![0-9.:])(?:' + [...new Set([id, id0])].sort((a, b) => b.length - a.length).map(esc).join('|') + ')(?![0-9])', 'g');

const forms = [...new Set([pw, JSON.stringify(pw).slice(1, -1), ...(tok.length >= 8 ? [tok] : [])])];
const needles = forms.map((s) => Buffer.from(s, 'utf8'));
const countPw = (buf) => { let n = 0; for (const nd of needles) { let i = 0; while ((i = buf.indexOf(nd, i)) >= 0) { n++; i += nd.length; } } return n; };
const walk = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => {
  const p = path.join(d, e.name);
  return e.isDirectory() ? walk(p) : [p];
});
const files = walk(dir).sort();
let replaced = 0, withheld = 0, idT = 0, pwT = 0, bad = 0;
const lines = [];
for (const f of files) {
  const text = TEXT.test(f);
  if (text) {
    const s = fs.readFileSync(f, 'utf8');
    let t = s; for (const x of forms) t = t.split(x).join('***'); t = t.replace(idRe, '***');
    if (t !== s) { fs.writeFileSync(f, t); replaced++; }
  }
  const buf = fs.readFileSync(f);
  const nPw = countPw(buf);
  const nId = text ? (buf.toString('utf8').match(idRe) || []).length : 0;
  idT += nId; pwT += nPw;
  const rel = path.relative(dir, f);
  let mark = '';
  if (nId + nPw > 0) {
    try { const t = path.join(held, rel); fs.mkdirSync(path.dirname(t), { recursive: true }); fs.renameSync(f, t); withheld++; mark = ' WITHHELD (not uploaded)'; }
    catch (e) { bad++; mark = ' MOVE FAILED'; }
  }
  lines.push(`secret-count ${rel} id=${text ? nId : 'pixels'} pw=${nPw}${mark}`);
}
const total = `secret-count total files=${files.length} replaced=${replaced} id=${idT} pw=${pwT} withheld=${withheld}`;
lines.push(total);
fs.mkdirSync(path.dirname(countFile), { recursive: true });
fs.appendFileSync(countFile, lines.join('\n') + '\n');
console.log(total);
process.exit(bad === 0 ? 0 : 1);
