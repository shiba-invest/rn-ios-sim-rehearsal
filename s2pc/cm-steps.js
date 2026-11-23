







const fs = require('fs');
const KINDS = [['Running on', 'device'], ['> Flow', 'flow-start'], ['Launch app', 'launchApp'], ['Assert that', 'assertVisible'],
  ['Wait for animation', 'waitForAnimation'], ['Run flow', 'runFlow'], ['Tap on', 'tapOn'], ['Erase', 'eraseText'],
  ['Input text', 'inputText'], ['Press', 'pressKey'], ['Take screenshot', 'takeScreenshot'], ['Set orientation', 'setOrientation'],
  ['Hide keyboard', 'hideKeyboard'], ['Scroll', 'scroll'], ['Repeat', 'repeat']];
const LABEL = /^(cm-[a-z0-9-]{2,40})(?:\.\.\.|\s|$)/;
function summarize(text, flow, end) {
  const fl = /^[a-z0-9-]{1,20}$/.test(String(flow)) ? flow : 'x';
  const rows = [];
  for (const raw of String(text).split('\n')) {
    const m = raw.replace(/\r/g, '').replace(/\x1b\[[0-9;]*[A-Za-z]/g, '').match(/^([0-9]{9,11}) (.*)$/); if (!m) continue;
    const t = m[2].trim(); if (!t) continue;
    const lb = t.match(LABEL); const k = KINDS.find(([p]) => t.startsWith(p));
    const kind = lb ? lb[1] : (k ? k[1] : 'other');
    const st = (t.match(/\.\.\. ?(COMPLETED|FAILED|SKIPPED|WARNED)$/) || [])[1] || (/\.\.\.$/.test(t) ? 'RUNNING' : '-');
    rows.push({ at: +m[1], kind, st, lab: !!lb, cls: kind === 'other' ? (t.match(/\b[A-Za-z]{2,40}(?:Exception|Error|Timeout|Failure|Unreachable)\b/) || []).slice(0, 1) : [] });
  }
  const ran = rows.filter((r) => r.st !== '-' && r.kind !== 'device' && r.kind !== 'flow-start').length; const nOther = rows.filter((r) => r.kind === 'other').length; const cls = [...new Set(rows.flatMap((r) => r.cls))].slice(0, 3).join(',');
  if (!ran) return [`failed-step flow ${fl} zero-step: no step ran (${rows.length} console lines, ${nOther} unidentified${cls ? '; classes ' + cls : ''})`];
  const out = []; const e = Number(end) || (rows.length ? rows[rows.length - 1].at : 0);
  const sec = (i) => Math.max(0, (rows[i].st === 'RUNNING' && i === rows.length - 1 ? e : rows[i].at) - (i > 0 ? rows[i - 1].at : rows[i].at));
  let last = -1; for (let i = rows.length - 1; i >= 0; i--) if (rows[i].st === 'FAILED' || rows[i].st === 'RUNNING') { last = i; break; }
  rows.forEach((r, i) => { if (r.lab && (r.st === 'WARNED' || r.st === 'SKIPPED') && i !== last) out.push(`failed-step flow ${fl} step ${i + 1} ${r.kind} ${r.st} ${sec(i)} s (fell through, went on)`); });
  if (last >= 0 && rows[last].st === 'RUNNING') { const ss = Math.max(0, (last + 1 < rows.length ? rows[last + 1].at : e) - rows[last].at); out.push(`failed-step flow ${fl} stalled-step: ${last + 1} ${rows[last].kind} RUNNING ${ss}s`); }
  else if (last >= 0) out.push(`failed-step flow ${fl} step ${last + 1} ${rows[last].kind} ${rows[last].st} ${sec(last)} s`);
  else out.push(`failed-step flow ${fl}: no FAILED or RUNNING step in ${rows.length} step lines`);
  return out;
}
module.exports = { summarize, KINDS };
if (require.main === module) {
  const [file, flow, end] = process.argv.slice(2); let s = ''; const fl = /^[a-z0-9-]{1,20}$/.test(flow || '') ? flow : 'x';
  try { s = fs.readFileSync(file, 'utf8'); } catch (e) { console.log(`failed-step flow ${fl} zero-step: no console`); process.exit(0); }
  console.log(summarize(s, flow, end).join('\n'));
}
