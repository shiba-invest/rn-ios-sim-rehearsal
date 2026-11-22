# rn-ios-sim-rehearsal

A practice Expo / React Native app used to rehearse an iOS-simulator CI run on GitHub-hosted macOS runners
(Release simulator build, then Maestro UI flows).

- The app has one ID + password login screen and a home screen.
- It signs in with `amazon-cognito-identity-js` against a user pool that does not exist
  (`ap-northeast-1_FAKEPOOL0`, client `fakeclient0000000000000000`; both are made up).
  The service answers `ResourceNotFoundException`, which proves that the request went out and came back,
  so the app opens the home screen. No account, password or key is real.
- `.github/workflows/rehearsal.yml` runs Gate a → updates off → npm ci → prebuild → pods → Release simulator build (fixed names `ios/app.xcworkspace`, scheme `app`) → Gate b → simulator run (`.maestro/cm-run.sh`) → pass marker. Every step publishes `out/` to `upload/` only after `.maestro/cm-scrub.js`; only `upload/` becomes the artifact.
- `workflow_dispatch` takes a `fault` input for practice failures:
  - network block (`a`, `b`, `c-up`);
  - cold simulator (`d-cold`) and a short overall deadline (`d-cap`);
  - planted practice values that the scrub must replace or withhold (`e`).
- `rehearsal/fault.sh` holds the practice faults only; the run calls it through `FAULT_HOOK` when a fault is chosen.

MIT license (see LICENSE).
