# Getting key material out of at_lookup

Why `AtLookUp` holds key material and algorithm choices as connection state, what
replaces it, and why the obvious intermediate fix was rejected.

Status: nothing has changed in at_lookup. A signer strategy was built and reverted
in full (below); at_lookup is on 3.6.0 exactly as trunk has it. This is the plan,
not a description of shipped code.

## Where the material lives today

- **PKAM private key: connection state.** `AtLookUp.atChops` holds an `AtChops`
  and `AtLookupImpl.pkamAuthenticate` calls `_atChops!.sign(...)` — see
  `lib/src/at_lookup_impl.dart`. A caller that never set `atChops` gets a null
  dereference part way through the handshake, after `from` has been sent.
- **Algorithm choice: two more properties.** `AtLookUp.signingAlgoType` and
  `hashingAlgoType`, settable independently of the key, are what the `pkam` verb
  is stamped with.
- **CRAM secret: per call, or state.** `cramAuthenticate(secret)`'s argument, or
  `AtLookupImpl.cramSecret`.
- **Data-signature verification: no local material at all.**
  `lookup(verifyData: true)` verifies with RSA SHA-256 against the public key the
  atServer serves for the signing atsign.

at_lookup owns the wire protocol and should own nothing else. Today a caller must
construct an `AtChops` — a general crypto context carrying encryption keys the
handshake never touches — purely to authenticate, then set two algorithm enums
that can contradict the key it was handed. Three independently settable properties
for one decision, and at_lookup cannot tell whether they agree.

## The target shape

Key material and algorithms become **arguments**, and the algorithm parameters are
typed as at_chops' abstract interfaces — so at_lookup retains no crypto state,
makes no algorithm choice, and gains no new algorithm without a change:

```dart
await atLookUp.pkamAuthenticate(
  signatureAlgorithm: signatureAlgorithm, // at_chops AtSignatureAlgorithm
  secretKey: apkamSecretKey,              // Uint8List, per call
  enrollmentId: enrollmentId,
);

await atLookUp.cramAuthenticate(
  secret: cramSecret,
  hashingAlgorithm: SHA512HashingAlgo(),  // AtHashingAlgorithm<List<int>, String>
);
```

`AtSignatureAlgorithm` is the interface to depend on: already stateless by design
(`signBytes(message, {required secretKey})`,
`verifyBytes(message, {required signature, required publicKey})`, key material by
named parameter so call sites cannot transpose byte arrays), and what at_chops v4
keeps. `AtSigningAlgorithm` — the one `RsaSigningAlgo` implements — is
`@Deprecated('Removed in v4. Use AtSignatureAlgorithm instead.')` and holds its key
in the constructor, the same mistake as `atChops` one layer down. Don't build on it.

For CRAM, `AtHashingAlgorithm<List<int>, String>` fits the digest exactly:
at_lookup passes `utf8.encode('$secret$challenge')` and writes the returned hex
onto the verb, without knowing that SHA-512 is what the atServer expects.

## Prerequisites in at_chops

The target signature cannot be written yet. In dependency order:

1. **RSA needs an `AtSignatureAlgorithm` implementation.** `RsaSigningAlgo`
   (at_chops `lib/src/algorithm/signing/rsa.dart`) implements only the deprecated
   stateful interface, while `MlDsa65PureDartAlgo` already implements the stateless
   one. Until RSA does too, an at_lookup API typed on `AtSignatureAlgorithm`
   excludes the algorithm every atServer verifies today.
2. **The wire tokens need a home.** The `pkam` verb carries
   `signingAlgo:<name>:hashingAlgo:<name>`, today from `signingAlgoType.name` /
   `hashingAlgoType.name`. Neither abstract interface exposes a name, so either the
   algorithm classes gain one — best, because the declaration then travels with the
   implementation and the verb cannot claim one algorithm while the signature used
   another — or the caller passes tokens alongside, re-creating today's
   two-things-that-can-disagree problem per call.
3. **Public keys need one representation.** `verifyBytes` takes a `Uint8List`
   public key; the atServer serves a PEM `String`. Who owns that conversion belongs
   in at_chops, not improvised here.

## Rejected: a signer strategy as a bridge

A prototype (2026-07-31) added `AtLookUpSigner` — `sign`, `signingAlgo`,
`hashingAlgo`, `cramDigest(secret, challenge)`, `verify(data, signature,
publicKey)` — behind one `AtLookUp.signer`, with `atChops` deprecated and bridged
onto it internally so existing callers kept working, plus implementations exported
from at_auth.

Reverted. The interface's only reason to exist is the state it works around, so it
dies with the same breaking change that fixes the problem: consumers would migrate
twice — onto a signer, then onto keys-per-call — for one release of benefit.
Deprecating `atChops` in favour of something with a one-release lifetime is worse
than leaving it alone until the replacement is the real one. Two findings carry
over: **only PKAM depends on state** (CRAM and verification take their inputs per
call, so the breaking change is narrower than the three properties suggest), and
**a missing key should fail before `from` goes out** rather than mid-handshake.

## Also on the list

- at_lookup still calls the deprecated at_chops wrappers `PkamSigningAlgo` and
  `AtPkamKeyPair.create` (`lib/src/at_lookup_impl.dart`,
  `lib/src/monitor_client.dart`). `RsaSigningAlgo` / `RsaKeyPair` are the current
  equivalents — byte-identical, same RSA SHA-256 primitives — and the swap needs
  `at_chops: ^3.4.1`. Worth doing on its own, ahead of the above.
- `AtEnrollmentImpl` in at_auth reads `atLookUp.atChops` for the encryption and
  self-encryption keys, so `atChops` is at_lookup's enrollment crypto handle as
  well as its PKAM key holder. Retiring the PKAM use does not retire that.
- `MonitorClient` takes a raw PEM private key and runs its own `from`/`pkam`
  handshake, duplicating `pkamAuthenticate`. It wants the same arguments as above.
- Every handshake sends its own `from`. at_java retains that challenge as
  per-connection single-use state (`AuthenticationCommands`,
  `AtCommandExecutorContext` in atsign-foundation/at_java) and lets whichever of
  PKAM or CRAM digests first consume it. Here, at_onboarding_cli already sends a
  `from` for proxy routing (`_sendFromCommandIfUsingProxy`) that the
  authentication after it cannot reuse.
