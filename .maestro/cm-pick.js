const RT = process.env.CM_SIM_RUNTIME || 'com.apple.CoreSimulator.SimRuntime.iOS-26-5';
const NAME = process.env.CM_IPHONE_NAME || 'iPhone 17 Pro';
let j;
try { j = JSON.parse(require('fs').readFileSync(0, 'utf8')); } catch (e) { console.error('pick: simctl JSON unreadable'); process.exit(1); }
const devs = (j.devices && j.devices[RT]) || null;
if (!devs) { console.error(`pick: runtime ${RT} not installed (have: ${Object.keys(j.devices || {}).join(' ')})`); process.exit(1); }
const hit = devs.filter((d) => d.isAvailable !== false && d.name === NAME);
if (hit.length !== 1) { console.error(`pick: ${hit.length} available "${NAME}" on ${RT}, expected exactly 1`); process.exit(1); }
console.log(`SIM_RUNTIME=${RT}`);
console.log(`IPHONE_UDID=${hit[0].udid}`);
console.log(`IPHONE_NAME=${NAME}`);
console.log(`MATCHES=${hit.length}`);
