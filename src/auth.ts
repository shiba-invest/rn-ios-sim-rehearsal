// Practice sign-in against a pool that does not exist (made-up ids, no account, no secret).
// Cognito answers 400 ResourceNotFoundException for the unknown client: that answer proves the request
// left the simulator and came back, so the practice app treats it as "reached" and opens the home screen.
import { AuthenticationDetails, CognitoUser, CognitoUserPool } from 'amazon-cognito-identity-js';

const pool = new CognitoUserPool({
  UserPoolId: 'ap-northeast-1_FAKEPOOL0',
  ClientId: 'fakeclient0000000000000000',
});

export const AUTH_TIMEOUT_MS = 25000;

export class TimeoutError extends Error {
  code = 'NetworkError';
  constructor() {
    super('no answer within the time limit');
    this.name = 'TimeoutError';
  }
}

export type Outcome = 'reached' | 'signedIn';

export function signIn(id: string, pw: string): Promise<Outcome> {
  return new Promise<Outcome>((resolve, reject) => {
    let over = false;
    const timer = setTimeout(() => {
      over = true;
      console.log('[REHEARSAL] auth timeout');
      reject(new TimeoutError());
    }, AUTH_TIMEOUT_MS);
    const finish = (f: () => void) => {
      if (over) return;
      clearTimeout(timer);
      f();
    };
    try {
      const user = new CognitoUser({ Username: id, Pool: pool });
      user.setAuthenticationFlowType('USER_PASSWORD_AUTH');
      user.authenticateUser(new AuthenticationDetails({ Username: id, Password: pw }), {
        onSuccess: () => finish(() => resolve('signedIn')),
        onFailure: (err: { code?: string; name?: string }) =>
          finish(() => {
            const code = err?.code || err?.name || 'Unknown';
            console.log(`[REHEARSAL] auth answer code=${code}`);
            if (code === 'ResourceNotFoundException') resolve('reached');
            else reject(err);
          }),
      });
    } catch (e) {
      finish(() => reject(e));
    }
  });
}

export function messageFor(e: unknown): string {
  const code = (e as { code?: string })?.code;
  if (code === 'NetworkError') return 'ログインできませんでした。通信環境をご確認ください';
  return 'ログインできませんでした。もう一度お試しください';
}
