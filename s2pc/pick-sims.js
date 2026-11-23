
const j = JSON.parse(require('fs').readFileSync(0, 'utf8'));
const rts = Object.keys(j.devices).filter((k) => /iOS-\d+/.test(k)).sort((a, b) => {
  const v = (s) => s.match(/iOS-(\d+)-(\d+)/).slice(1).map(Number);
  const [a1, a2] = v(a), [b1, b2] = v(b);
  return b1 - a1 || b2 - a2;
});
for (const rt of rts) {
  const ds = j.devices[rt].filter((d) => d.isAvailable);
  const ph = ds.find((d) => /^iPhone \d+( Pro)?$/.test(d.name)) || ds.find((d) => /^iPhone/.test(d.name));
  const pad = ds.find((d) => /^iPad Air/.test(d.name)) || ds.find((d) => /^iPad/.test(d.name));
  if (ph && pad) {
    console.log(`SIM_RUNTIME=${rt}`);
    console.log(`IPHONE_UDID=${ph.udid}`);
    console.log(`IPHONE_NAME=${ph.name}`);
    console.log(`IPAD_UDID=${pad.udid}`);
    console.log(`IPAD_NAME=${pad.name}`);
    process.exit(0);
  }
}
console.error('no iPhone+iPad pair');
process.exit(1);
