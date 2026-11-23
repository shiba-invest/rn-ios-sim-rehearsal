





const crypto = require('crypto');
const SHA = '0000000000000000000000000000000000000000000000000000000000000000';
function record(env) {
  const b = String(env.E2E_DEV_LOGINS_B64 || ''); let parse = 'fail', keys = 0, same = 'no';
  if (b && /^[A-Za-z0-9_-]+$/.test(b)) {
    try {
      const o = JSON.parse(Buffer.from(b, 'base64url').toString('utf8'));
      if (o && typeof o === 'object' && !Array.isArray(o)) {
        parse = 'ok'; keys = Object.keys(o).length;
        const l = String(env.E2E_0003_LOGIN || ''), p = String(env.E2E_0003_PASSWORD || '');
        same = l && p && o.E2E_0003_CAREGIVER_LOGIN === l && o.E2E_0003_CAREGIVER_PASSWORD === p ? 'yes' : 'no';
      }
    } catch (e) { parse = 'fail'; }
  }
  const sha = b ? crypto.createHash('sha256').update(b, 'utf8').digest('hex') : '';
  const line = `logins-blob set=${b ? 'yes' : 'no'} chars=${b.length} sha-match=${sha === SHA ? 'yes' : 'no'} parse=${parse} keys=${keys} caregiver-pair-same=${same}`;

  return /^logins-blob set=(yes|no) chars=[0-9]+ sha-match=(yes|no) parse=(ok|fail) keys=[0-9]+ caregiver-pair-same=(yes|no)$/.test(line) ? line : 'logins-blob record shape broken';
}
module.exports = { record, SHA };
if (require.main === module) { try { console.log(record(process.env)); } catch (e) { console.log('logins-blob record failed'); } process.exit(0); }
