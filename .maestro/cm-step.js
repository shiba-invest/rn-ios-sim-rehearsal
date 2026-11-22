





const fs = require('fs');
const path = require('path');
const [what, a1, a2] = process.argv.slice(2);
const root = process.cwd();
if (what === 'eas-dev-env') {
  const e = JSON.parse(fs.readFileSync(path.join(root, 'eas.json'), 'utf8')).build['preview-dev'].env;
  const m = (fs.readFileSync(path.join(__dirname, 'cm-pool.txt'), 'utf8').match(/^dev-pool-mark (\S+)\s*$/m) || [])[1] || '';
  if (!m || !String(e.EXPO_PUBLIC_USER_POOL_ID || '').includes(m)) { console.error('eas-dev-env: preview-dev pool is not the dev pool'); process.exit(1); }
  for (const [k, v] of Object.entries(e)) console.log(k + '=' + v);
} else if (what === 'updates-off') {
  const f = path.join(root, 'app.json');
  const a = JSON.parse(fs.readFileSync(f, 'utf8'));
  a.expo.updates = Object.assign({}, a.expo.updates, { enabled: false });
  fs.writeFileSync(f, JSON.stringify(a, null, 2));
} else if (what === 'scheme-once') {
  const s = JSON.parse(fs.readFileSync(a1, 'utf8')).workspace.schemes;
  console.log('schemes=' + s.join(','));
  if (s.filter((x) => x === a2).length !== 1) { const g = 'GATE build FAIL: scheme ' + a2 + ' not listed exactly once'; console.log(g);


    try { fs.appendFileSync(require('path').join(process.env.CM_ROOT || '.', 'out/logs/causes.txt'), g + String.fromCharCode(10)); } catch (e) { /* the log line stays */ }
    process.exit(1); }
} else { console.error('cm-step: unknown ' + String(what)); process.exit(1); }
