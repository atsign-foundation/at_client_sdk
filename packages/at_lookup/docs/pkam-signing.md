# PKAM challenge signing — direction and decisions

Signer implementations live in at_auth — see
[`at_auth/docs/pkam-signing.md`](../../at_auth/docs/pkam-signing.md).

## Direction

`at_lookup` should own the wire protocol and nothing else. Until now it
also held PKAM key material (`AtLookUp.atChops`) and the algorithm choice
(`signingAlgoType` / `hashingAlgoType`) — three properties a caller could
set inconsistently, for a decision `at_lookup` has no business making.

The direction is to reduce that to one question: *can you sign this
challenge?* `AtPkamSigner` declares it; the consumer implements it.
`at_lookup` sends `from`, asks the signer for signature bytes,
base64-encodes them onto the `pkam` verb, and stamps the algorithms the
signer declares. No key material, no algorithm policy.

```dart
atLookUp.pkamSigner = signer; // AtChops no longer needed for auth
await atLookUp.pkamAuthenticate();
```

## Decisions

**The interface lives here, implementations live in at_auth.** The
consumer of the strategy declares what it needs; the owner of the keys
supplies it (at_auth).

**`sign` returns raw bytes, typed `FutureOr<Uint8List>`.** Base64 stays in
the one place that writes the verb. `FutureOr` so a keychain- or
hardware-backed signer needs no wrapper — sync and async implementations
both fit.

**The signer declares its own `signingAlgo` / `hashingAlgo`.** Bundling
the declaration with the implementation means the verb can't claim one
algorithm while the signature used another.

**A missing signer throws before connecting.** `pkamAuthenticate` resolves
the signer first and throws `UnAuthenticatedException`, where the
absent-`atChops` case previously null-dereferenced mid-handshake.

## Not done yet

- `at_auth`, `at_client` (`RemoteSecondary`) and `at_onboarding_cli` all
  still set `atLookUp.atChops` and authenticate through the bridge.
  Migrating them is the prerequisite for removing the deprecated members
  in the next major.
- `AtLookUp` is an `abstract interface class`, so adding `pkamSigner`
  breaks an external hand-written `implements AtLookUp` — arguably more
  than the minor bump says. Nothing in-repo is affected (mocktail mocks
  aren't).
- `AtLookUp` is impending on a major bump to help neutralize the atChops handover between seams.

## Reference

- `lib/src/auth/at_pkam_signer.dart` — the interface
- `lib/src/at_lookup_impl.dart` — handshake, signer resolution, bridge
- `test/at_lookup_test.dart` — precedence and fallback tests
