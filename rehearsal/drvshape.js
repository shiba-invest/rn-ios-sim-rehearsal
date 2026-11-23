// Practice only (written so it can be copied into the driver piece as is).
// node rehearsal/drvshape.js <raw dir> <out file>: one line per driver-*.txt (one Maestro hierarchy output):
//   FACT driver-shape-<key> value=lines=<n> json=<n> at=<n> err=<n> other=<n> classes=<A,B|-> last3=<k,k,k> expect=- verdict=RECORD
// kinds: json (a hierarchy JSON line), at (a stack frame), err (a line with an error class name), other. Only counts,
// letters-only class names and kinds are printed: no screen text, no value, no ID, no digit from the file.
// node rehearsal/drvshape.js --selftest: positive control (class names and frames are found) and negative control (a
// value, an ID-like number and a screen text in the input never reach the output); exit 1 if either fails.
const fs = require('fs');
const path = require('path');
const CLS = /\b([A-Z][A-Za-z]*(?:Exception|Error|Timeout|Failure|Unreachable|Refused))\b/g;
function shape(key, text) {
  const L = text.split('\n').map((l) => l.replace(/\r$/, '').replace(/\x1b\[[0-9;]*[A-Za-z]/g, '').trim()).filter((l) => l);
  const n = { json: 0, at: 0, err: 0, other: 0 }; const cls = new Set(); const kinds = [];
  let inJson = L.length > 0 && /^[{[]/.test(L[0]);
  for (const t of L) {
    let k;
    if (inJson || /^[{}[\]"]/.test(t)) k = 'json';
    else if (/^at\s+[A-Za-z_$]/.test(t)) k = 'at';
    else if (t.match(CLS)) { k = 'err'; for (const m of t.matchAll(CLS)) cls.add(m[1]); }
    else k = 'other';
    n[k]++; kinds.push(k);
  }
  const c = [...cls].sort();
  return `FACT driver-shape-${key.replace(/[^A-Za-z-]/g, '_')} value=lines=${L.length} json=${n.json} at=${n.at} err=${n.err} other=${n.other} classes=${c.length ? c.join(',') : '-'} last3=${kinds.slice(-3).join(',') || '-'} expect=- verdict=RECORD`;
}
function selftest() {
  const sample = ['Running on iPhone 17 Pro', 'Waiting for the driver user=demo-7731 at 10.0.0.5:22087 screen "Sign in now"',
    'Exception in thread "main" maestro.cli.CliError: IOSDriverTimeoutException while starting', '\tat maestro.ios.XCTestDriverClient.start(XCTestDriverClient.kt:118)',
    '\tat maestro.cli.App.main(App.kt:9)', 'Caused by: java.net.ConnectException: Connection refused'].join('\n');
  const out = shape('warm', sample);
  const posWant = ['lines=6', 'at=2', 'err=2', 'classes=CliError,ConnectException,IOSDriverTimeoutException', 'last3=at,at,err'];
  const pos = posWant.map((w) => (out.includes(w) ? 1 : 0));
  const negBan = ['demo', '7731', '10.0.0.5', '22087', 'Sign in now', 'iPhone', '118', 'XCTestDriverClient'];
  const neg = negBan.map((w) => (out.includes(w) ? 1 : 0));
  const digits = out.replace(/(lines|json|at|err|other)=\d+/g, '').replace(/last3=/, '').replace(/driver-shape-\S+/, '').match(/\d/g);
  const j = shape('cold', '{\n  "attributes": {"text": "Hello 123"}\n}');
  const jok = j.includes('json=3') && !j.includes('Hello') && !j.includes('123') ? 1 : 0;
  console.log(out); console.log(j);
  console.log(`# drvshape selftest positive=${pos.join(',')} (each 1) negative=${neg.join(',')} (each 0) stray-digits=${digits ? digits.length : 0} json=${jok}`);
  if (pos.some((x) => !x) || neg.some((x) => x) || digits || !jok) process.exit(1);
}
const [dir, out] = process.argv.slice(2);
if (dir === '--selftest') { selftest(); process.exit(0); }
let files = [];
try { files = fs.readdirSync(dir).filter((f) => /^driver-.*\.txt$/.test(f)).sort(); } catch (e) { /* no raw dir */ }
const res = files.map((f) => shape(f.replace(/^driver-|\.txt$/g, ''), fs.readFileSync(path.join(dir, f), 'utf8')));
if (!files.length) res.push('FACT driver-shape value=no-raw-files expect=- verdict=RECORD');
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, res.join('\n') + '\n');
console.log(`drvshape files=${files.length}`);
