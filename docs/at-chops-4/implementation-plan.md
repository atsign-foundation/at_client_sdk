# implementation-plan.md — the at_chops 4.0.0 migration slices

Five slices, each a PR into the integration branch `xl/feat/at-chops-4`
([D3](decisions.md#d3-one-integration-branch-one-pr-per-slice-then-the-integration-pr-into-trunk)).
Slice 0 is this PR, direct into trunk.

0. **Workspace rejoin** (this PR). Rejoin `packages/at_chops` to the root
   workspace, move every at_chops constraint in the workspace to
   `^4.0.0-rc.1`, and record this plan and [`decisions.md`](decisions.md).
   Nothing else changes; the dependents do not analyse clean until their own
   slice lands.
1. **at_lookup.** Remove the deprecated atChops credential ladder; the
   injected `AtAuthenticator` becomes the only authentication path. Version
   bump to 4.0.0-rc.1 ([D1](decisions.md#d1-at_lookup-drops-the-deprecated-atchops-credential-ladder)).
2. **at_auth.** Move onto at_chops 4's stateless algorithms directly; continue
   its own 4.0.0 rc track.
3. **at_client.** `AtChops` becomes the deprecated, inert, final shim
   ([D2](decisions.md#d2-at_client-keeps-atchops-as-a-deprecated-inert-shim-the-package-stays-on-3x)).
   Every call site that built an algorithm implementation through the facade
   moves to the stateless at_chops 4 calls. at_client stays on 3.x.
4. **Remaining consumers.** at_client_flutter and at_onboarding_cli pick up
   whatever the at_client slice's inert shim does not already cover for them.

Each slice's PR gates on: `dart pub get` at the root; in the slice's own
package, `dart analyze --fatal-infos`,
`dart format --output=none --set-exit-if-changed .`, `dart test`. The last
slice's PR, once every dependent analyses clean, becomes ready to fold
`xl/feat/at-chops-4` into trunk through this PR.
