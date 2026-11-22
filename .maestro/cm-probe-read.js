




const fs = require('fs'), os = require('os');
const [what, arg] = process.argv.slice(2);
const sims = () => { try { return JSON.parse(fs.readFileSync(arg, 'utf8')).devices || {}; } catch (e) { return null; } };
try {
  if (what === 'runtimes') { const d = sims(); console.log(d ? Object.keys(d).map((k) => k.split('.').pop()).join(' ') : 'sims.json unreadable'); }
  else if (what === 'count') { const d = sims(); const l = d ? d['com.apple.CoreSimulator.SimRuntime.iOS-26-5'] || [] : null;
    console.log(l ? 'n=' + l.filter((x) => x.name === 'iPhone 17 Pro' && x.isAvailable !== false).length : 'sims.json unreadable'); }
  else if (what === 'memory') console.log('total_gb=' + (os.totalmem() / 2 ** 30).toFixed(1) + ' free_gb=' + (os.freemem() / 2 ** 30).toFixed(1) + ' cpus=' + os.cpus().length);
  else if (what === 'skew') { const d = Date.parse(arg || ''); console.log(isNaN(d) ? 'no-date' : String(Math.round((Date.now() - d) / 1000))); }
  else console.log('unknown read ' + String(what));
} catch (e) { console.log('read failed'); }
