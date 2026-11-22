# rn-ios-sim-rehearsal

A practice Expo / React Native app used to rehearse an iOS-simulator CI run on GitHub-hosted macOS runners
(Release simulator build, then Maestro UI flows).

- The app has one ID + password login screen and a home screen.
- It signs in with `amazon-cognito-identity-js` against a user pool that does not exist
  (`ap-northeast-1_FAKEPOOL0`, client `fakeclient0000000000000000`; both are made up).
  The service answers `ResourceNotFoundException`, which proves that the request went out and came back,
  so the app opens the home screen. No account, password or key is real.
- `.github/workflows/rehearsal.yml` runs Gate a → prebuild → pods → Release simulator build → Gate b → simulator run → secret sweep → artifacts.
- `workflow_dispatch` takes a `fault` input for practice failures:
  - network block (`a`, `b`, `c-up`);
  - slow or short boot (`d-cold`, `d-cap`);
  - log cap and planted-secret sweep (`e`).

MIT license (see LICENSE).
