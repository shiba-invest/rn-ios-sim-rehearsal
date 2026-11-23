




const { execSync } = require('child_process');
const OK = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
function repoSlug() {
  const e = process.env.CM_REPO_SLUG || '';
  if (OK.test(e)) return { repo: e, from: 'env' };
  let u = '';
  try { u = execSync('git remote get-url origin', { stdio: ['ignore', 'pipe', 'ignore'], timeout: 5000 }).toString().trim(); } catch (x) { u = ''; }
  const m = u.match(/github\.com[:/]+([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+?)(?:\.git)?\/?$/);
  u = '';
  if (m && OK.test(m[1] + '/' + m[2])) return { repo: m[1] + '/' + m[2], from: 'remote' };
  return { repo: '', from: 'none' };
}
module.exports = { repoSlug };
