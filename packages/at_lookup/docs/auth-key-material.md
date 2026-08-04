# Key material and at_lookup

Why `AtLookUp` retains exactly one key, what it used to hold instead, and which
alternatives were tried and rejected getting here.

Shipped in at_lookup 4.0.0.

## What it used to look like

- **PKAM private key: connection state.** `AtLookUp.atChops` held an `AtChops`
  and `pkamAuthenticate` called `_atChops!.sign(...)`. A caller who never set
  `atChops` got a null dereference part way through the handshake, after `from`
  had already gone out.
- **Algorithm choice: two more mutable properties.** `signingAlgoType` and
  `hashingAlgoType`, settable independently of the key, were what the `pkam` verb
  was stamped with — so the verb could claim one algorithm while the signature was
  produced with another.
- **CRAM secret: per call, or state.** `cramAuthenticate(secret)`'s argument, or
  the `cramSecret` field.
- **Data-signature verification: no local material at all.** Hard-coded RSA
  SHA-256 against the public key the atServer serves for the signing atsign.

at_lookup owns the wire protocol and should own nothing else. A caller had to
construct an `AtChops` — a general crypto context carrying encryption keys the
handshake never touches — purely to authenticate, then set two algorithm enums
that could contradict the key it was handed. at_auth went further and used
`atLookUp.atChops` as its key store.

at_chops 4.0.0 forced the issue by deleting `AtChops`, `AtChopsKeys`,
`AtPkamKeyPair`, `AtSigningInput` and `PkamSigningAlgo` outright.

## What it looks like now

```dart
final atLookUp = AtLookUp.legacy(atSign, rootDomain, rootPort,
    pkamPrivateKey: key);   // or AtLookUp.pq(...) for an ML-DSA-65 APKAM key

await atLookUp.pkamAuthenticate();
await atLookUp.cramAuthenticate(cramSecret);
```

`AtLookUp.create` names each algorithm individually — `signingAlgo`,
`hashingAlgo`, `dataAlgo` — for a custom mix; the two factories fill them in.
Three properties replace the old six:

- **One decision, one place.** `signingAlgo` is a stateless at_chops
  `AtSignatureAlgorithm` and declares its own `signingAlgoType` and nullable
  `hashingAlgoType`, so the wire tokens come off the same object that produces the
  signature. A null `hashingAlgoType` means hashing is intrinsic to the scheme
  (ML-DSA-65, FIPS 204) and the `:hashingAlgo:` token is omitted.
- **One key, retained.** `pkamPrivateKey` is the only key material held. The CRAM
  secret stays an argument, and a data signature's public key arrives from the
  atServer with the data, so neither needs to be held.
- **Nothing settable after construction.** No `atChops`, no algorithm properties,
  no key setter. A different key is a different authenticated identity: construct
  a new `AtLookUp`.

## Why the key is retained

This is the one place key material stays, and it is deliberate.

`_isAuthRequired()` is true when the connection is merely *unavailable*, and
`createConnection()` silently rebuilds a dead socket — so one `executeVerb` call
recovers from an idle timeout (`outboundConnectionTimeout`, 10 minutes by
default) by reconnecting **and** re-running PKAM, invisibly. Nothing downstream
covers for losing that: every `UnAuthenticatedException` reference in at_client,
at_auth and at_onboarding_cli is a throw site or a one-shot onboarding flow.
There are **zero** re-auth handlers.

Re-signing a fresh challenge at an arbitrary later moment requires reaching
something signable, so keys strictly per call cannot work. What changed is the
*scope* of what is held: one signing key, not an `AtChops` full of encryption keys
that at_auth then reads back out as a key store.

Two properties keep it honest:

- The auth check in `_process` happens *before* anything is written, so a
  surfaced `UnAuthenticatedException` never leaves a verb half-sent — which is
  what makes it safe for a caller to retry an `update` or `notify`.
- `pkamAuthenticate` guards on a missing algorithm or key before
  `createConnection()`, so a misconfigured instance fails without leaving a `from`
  challenge unanswered.

## Rejected alternatives

Five shapes were built and reverted on 2026-08-04 before this one. Recorded so
they are not relitigated:

1. **Stateless algorithms injected, key per call.** The target the earlier design
   note proposed. Breaks transparent re-auth outright — see above.
2. **Keys per call plus an `onAuthRequired` callback.** at_lookup then holds a
   closure rather than a key, which is strictly less, but the closure has to be
   threaded through every construction site and needs a post-callback
   `_isAuthRequired()` re-check as a second failure mode.
3. **A keyed `AtSigner` in at_chops** (an algorithm bound to a key). Works, but
   the name was wrong and it sat awkwardly beside two loose callbacks for CRAM and
   verification.
4. **All three operations as callback typedefs with top-level defaults.** A
   closure can declare an algorithm it did not actually use, reintroducing the
   problem the wire-identity getters exist to close.
5. **Three interfaces bundled in an `AtLookUpCrypto`.** More types than the
   problem has.

Earlier still, an `AtLookUpSigner` strategy was built and reverted on 2026-07-31,
with `atChops` deprecated and bridged onto it. Its rejection reason —
consumers migrating twice, once onto a signer and again onto the real shape — no
longer applies now that this is the breaking change, but by then the simpler
answer was clear. Two findings from it carried over: **only PKAM depended on
state** (CRAM and verification always took their inputs per call, so this break is
narrower than the three properties suggested), and **a missing key should fail
before `from` goes out**.

Also rejected: separate `LegacyAtLookup`/`PqAtLookup` implementations. They would
have differed only in three constant values across ~700 lines of identical verb
and connection logic, `AtLookupImpl` is unexported so consumers cannot tell either
way, and PQ diverging behaviourally is out of scope — `docs/projects/pq/design.md`
is explicit that this is "a signature swap, not a KEM. Do not over-build."

## Not done yet

- **at_auth still uses `atLookUp.atChops` as its key store.**
  `AtEnrollmentImpl` reads the encryption and self-encryption keys off the lookup
  rather than taking them as parameters. Retiring at_lookup's PKAM key does not
  retire that; it needs its own change in at_auth.
- **Every handshake sends its own `from`.** at_java retains that challenge as
  per-connection single-use state (`AuthenticationCommands`,
  `AtCommandExecutorContext` in atsign-foundation/at_java) and lets whichever of
  PKAM or CRAM digests first consume it. Here, at_onboarding_cli already sends a
  `from` for proxy routing (`_sendFromCommandIfUsingProxy`) that the
  authentication after it cannot reuse. Deliberately out of scope — reshaping
  connection/auth state is a larger change than getting key material out.
- **at_client's stream path downcasts.** `at_client_impl.dart` reaches
  `messageListener` through `as AtLookupImpl`, which the unexported impl breaks.
  `messageListener` should not become interface surface; that path needs its own
  design.
