# PKAM signers — direction and decisions

Status: landed in at_auth 3.3.0. Migration incomplete.

The `AtPkamSigner` interface and the handshake that consumes it live in
at_lookup — see
[`at_lookup/docs/pkam-signing.md`](../../at_lookup/docs/pkam-signing.md)
for why the split falls where it does.

## Direction

`at_auth` owns key material and algorithm policy; `at_lookup` owns the
wire. So `at_auth` supplies the thing that can sign a PKAM challenge, and
`at_lookup` stops holding an `AtChops` for authentication purposes.

```dart
atLookUp.pkamSigner = RsaPkamSigner(atKeys.apkamPrivateKey);
await atLookUp.pkamAuthenticate();
```

This is also the seam post-quantum signing goes through. Changing the
algorithm becomes a different signer rather than a change to the
handshake, which is what makes `MlDsaPkamSigner` possible to develop
without touching `at_lookup`.

## Decisions

**`RsaPkamSigner(privateKey)` takes the PEM private key, not an `AtKeys`.**
The signer's whole job is one key and one algorithm (RSA-2048 / SHA-256,
what atServers verify today). Passing `AtKeys` would drag key selection
and enrollment awareness into a signing primitive; the caller already
knows which key it means (`atKeys.apkamPrivateKey`).

**`MlDsaPkamSigner` is `@experimental` and its `hashingAlgo` throws.**
ML-DSA-65 signing works; the wire semantics don't. The `pkam` verb's
`hashingAlgo` field has no meaningful value for ML-DSA — hashing is
intrinsic to the scheme — and RSA-vs-ML-DSA selection policy is
undecided. 

**Both signers are exported from the `at_auth` barrel.** They are the
public hand-off to `at_lookup`, not internals — a caller cannot wire
authentication without them.

## Not done yet

- `at_auth` itself has not migrated. `AtAuthImpl` and
  `AtEnrollmentImpl` still set and read `atLookUp.atChops`, so at_auth
  authenticates through at_lookup's deprecated-path bridge while shipping
  the replacement. Same for `at_client` (`RemoteSecondary`) and
  `at_onboarding_cli`.
- ML-DSA PKAM needs the `hashingAlgo` wire question settled on the
  atServer side, plus an algorithm-selection policy, before
  `MlDsaPkamSigner` can be wired up.

## Reference

- `lib/src/auth/pkam_signers.dart` — `RsaPkamSigner`, `MlDsaPkamSigner`
- `lib/at_auth.dart` — barrel export
