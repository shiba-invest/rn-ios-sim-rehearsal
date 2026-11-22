// Practice only. node rehearsal/steps.js <console file> <lines already printed>: prints the NEW step lines of one
// Maestro console as "<n> <kind> <status>" only. The kind comes from a fixed list; arguments, texts on the screen and
// typed values are never printed. A line that matches no kind is counted as "other" with no text.
const fs = require('fs');
const [file, done0] = process.argv.slice(2);
let s = ''; try { s = fs.readFileSync(file, 'utf8'); } catch (e) { process.exit(0); }
const KINDS = [['Running on', 'device'], ['> Flow', 'flow-start'], ['Launch app', 'launchApp'], ['Assert that', 'assertVisible'],
  ['Wait for animation', 'waitForAnimation'], ['Run flow', 'runFlow'], ['Tap on', 'tapOn'], ['Erase', 'eraseText'],
  ['Input text', 'inputText'], ['Press', 'pressKey'], ['Take screenshot', 'takeScreenshot'], ['Set orientation', 'setOrientation'],
  ['Hide keyboard', 'hideKeyboard'], ['Scroll', 'scroll']];
const lines = s.split('\n').map((l) => l.replace(/\r$/, '').replace(/\x1b\[[0-9;]*[A-Za-z]/g, '')).filter((l) => l.trim());
const done = Number(done0) || 0;
const out = [];
lines.forEach((l, i) => {
  if (i < done) return;
  const t = l.trim();
  const k = KINDS.find(([p]) => t.startsWith(p));
  const st = (t.match(/\.\.\. (COMPLETED|FAILED|SKIPPED|WARNED)$/) || [])[1] || (/\.\.\.$/.test(t) ? 'RUNNING' : '-');
  out.push(`${i + 1} ${k ? k[1] : 'other'} ${st}`);
});
if (out.length) console.log(out.join('\n'));
console.error(lines.length);
