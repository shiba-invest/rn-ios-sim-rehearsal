








const https = require('https');
const PAGES = {
  codemagic: { url: 'https://status.codemagic.io/summary.json', kind: 'instatus' },
  github: { url: 'https://www.githubstatus.com/api/v2/status.json', kind: 'statuspage' },
  npm: { url: 'https://status.npmjs.org/api/v2/status.json', kind: 'statuspage' },
  aws: { url: 'https://health.aws.amazon.com/public/currentevents', kind: 'aws' },
};
const only = (process.argv.find((a) => a.startsWith('--only=')) || '').slice(7) ||
  (process.argv.includes('--only') ? process.argv[process.argv.indexOf('--only') + 1] : '');
const names = only ? only.split(',') : Object.keys(PAGES);
const get = (url, tries = 3) => new Promise((resolve) => {
  const once = (n) => {
    const req = https.get(url, { timeout: 20000, headers: { 'user-agent': 'status-check' } }, (res) => {
      const parts = []; res.on('data', (d) => parts.push(d));
      res.on('end', () => resolve({ code: res.statusCode, body: Buffer.concat(parts) }));
    });
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', (e) => (n > 1 ? setTimeout(() => once(n - 1), 3000) : resolve({ code: 0, err: e.message })));
  };
  once(tries);
});
const decode = (b) => { // the AWS feed is UTF-16 BE with a BOM (fe ff), read on this PC 2026-11-22 [L]
  if (b[0] === 0xfe && b[1] === 0xff) { const s = Buffer.from(b.slice(2)); s.swap16(); return s.toString('utf16le'); }
  if (b[0] === 0xff && b[1] === 0xfe) return b.slice(2).toString('utf16le');
  return b.toString('utf8'); };
(async () => {
  let bad = 0;
  for (const n of names) {
    const p = PAGES[n]; if (!p) { console.log(`STATUS ${n} unknown page name -> outage`); bad++; continue; }
    const r = await get(p.url);
    if (r.code !== 200) { console.log(`STATUS ${n} http=${r.code}${r.err ? ' ' + r.err : ''} -> unreadable = outage`); bad++; continue; }
    try {
      const j = JSON.parse(decode(r.body));
      if (p.kind === 'statuspage') {
        const ind = j.status && j.status.indicator;
        const ok = ind === 'none';
        console.log(`STATUS ${n} indicator=${ind} "${j.status && j.status.description}" -> ${ok ? 'ok' : 'INCIDENT'}`);
        if (!ok) bad++;
      } else if (p.kind === 'instatus') {
        const st = j.page && j.page.status; const inc = (j.activeIncidents || []).length, mnt = (j.activeMaintenances || []).length;
        const ok = st === 'UP' && !inc && !mnt;
        console.log(`STATUS ${n} page.status=${st} active-incidents=${inc} active-maintenances=${mnt} -> ${ok ? 'ok' : 'INCIDENT'}`);
        if (!ok) bad++;
      } else {

        const ev = (Array.isArray(j) ? j : []).filter((e) => /ap-northeast-1|tokyo|global/i.test(`${e.arn} ${e.region_name}`));
        console.log(`STATUS ${n} events-total=${Array.isArray(j) ? j.length : 'not-a-list'} ap-northeast-1-relevant=${ev.length} -> ${ev.length ? 'INCIDENT' : 'ok'}`);
        for (const e of ev) console.log(`  ${e.service_name || e.service} ${e.region_name || e.region} ${String(e.summary || '').slice(0, 120)}`);
        if (ev.length || !Array.isArray(j)) bad++;
      }
    } catch (e) { console.log(`STATUS ${n} body not JSON -> unreadable = outage`); bad++; }
  }
  console.log(bad ? `STATUS RESULT: ${bad} page(s) not clear -> do not push the tag (障害が出ていれば、走らせない)` : 'STATUS RESULT: all clear');
  process.exit(bad ? 1 : 0);
})();
