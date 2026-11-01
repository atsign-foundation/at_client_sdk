# Trusted connections — implementation plan

**Status:** proposal, not started.
**Scope:** the fully-evicted, unauthenticated web-app case. A client still holding a working
APKAM key already has OTP-free paths. The device-secrecy read gate rides the same primitive and
is phased separately — see *The second use site*.
**Vocabulary:** the *connection* is what becomes trusted; the *device* is what gets registered.
`trustedDevice` stays the metadata key for that reason — it names a device registration, not a
connection state.

---

## What we are building

A web app's `.atKeys` live in browser IndexedDB, which is evictable. Recovery today is a new
APKAM enrollment, which needs a new OTP conveyed to the device by a human.

Register a **device-bound credential** on the enrollment record at enrollment time. On
re-enrollment the device signs a server-issued challenge with it; a verified signature waives
the OTP. Any device without a registered credential is challenged as today.

**A fingerprint is an identifier, not a secret** — anything the page can read, an observer can
replay. The waiver is a signature over a server challenge, never a stored-string comparison.
Two concrete instances behind one adapter: a device-bound **WebAuthn passkey** (consumer), and
an **OIDC assertion** from the tenant's IdP (enterprise). An ambient fingerprint is not a third.

## What exists today

| Step | Mechanism |
| --- | --- |
| Enrollment | `enroll:request` with an OTP obtained from an already-enrolled app |
| Approval | `enroll:approve` on a connection holding `__manage` (`enrollment_approver.dart:12-17`) |
| Eviction | no keys, no APKAM private key; recovery is a **new enrollment** needing a **new OTP** |
| Recovery today | the approver re-seals the default encryption private key and the self-encryption key onto the new record (`enrollment_approver.dart:52-72`) — data access is already restored, so this is a UX change, not a new capability |

**OTP-free enrollment already exists on authenticated connections** — `FirstEnrollmentRequest`
builds an `enroll:request` with no OTP (`enrollment_submitter.dart:72-85`), and
`AtSelfEnrollmentRequest` adds a fresh enrollment with no `otp` in the builder at all, executed
`auth: true` (`enrollment_submitter.dart:580-606`). This extends those semantics to a
connection that can no longer authenticate.

**A waiver removes the OTP, not the approval.** `enroll:approve` still needs `__manage`, so
unless the surviving device auto-approves, a human still taps *approve* on device 2. See
**Open, blocking**.

## Credential requirements

| Requirement | Consequence if dropped |
| --- | --- |
| **Device-bound** — sync explicitly disallowed | Consumer authenticators ship **synced** passkeys by default (iCloud Keychain, Google Password Manager); a synced credential propagates to other machines and to the vendor cloud, dissolving the per-device premise |
| **`userVerification: 'required'`** | A stolen unlocked device re-enrolls silently — **strictly weaker than the OTP path** |
| **Origin / RP ID verified server-side** | A credential asserted from any origin is accepted, and the non-replayability claim is void |

## Constraints

| ID | Constraint |
| --- | --- |
| **T1** | Trust is proven by a **credential**, never asserted by an identifier. Nothing the page can simply read may waive a challenge. |
| **T2** | Every waiver is bound to a **server-issued, single-use challenge**, and that challenge **carries** the binding to the `apkamPublicKey` being installed. The binding lives inside the challenge rather than in the signed message, because WebAuthn does not let a relying party choose the signed bytes — see *The exchange*. No stored-string comparison, no unbound signature. |
| **T3** | **No new verb.** Registration rides existing enrollment metadata. The challenge leg adds **one operation** to `enroll:` — an atServer grammar and handler change, explicitly negotiated. |
| **T4** | A waived enrollment is **still an enrollment** — same record, same namespace grants, same revocation path. The waiver replaces the OTP, not the approval model. |
| **T5** | Waiver is scoped to **(atSign, origin, authenticator)**. `appName` is self-declared and enforces nothing; per-app separation holds **only** where apps occupy distinct web origins, because a WebAuthn credential binds to an RP ID, not to an app name. |
| **T6** | Revoking an enrollment revokes **that record's registration**. No trust outlives the enrollment it was registered under. |
| **T7** | The credential must be device-bound, `uv` required, and origin-verified server-side — none of the three is optional. |
| **T8** | Zero vendor-specific IdP code in the core SDK — inherits `docs/projects/wasm/enterprise-identity.md` **E7**. |
| **T9** | A device credential is **never** a candidate for PKAM/APKAM verification. Separate metadata slot (`use: "device-assert"`), separate verifier, and never a member of the set `SigningAlgoType.strongestOf` chooses from (`algo_type.dart:36-56`). |
| **T10** | The registration records the credential's algorithm, and the verifier **refuses rather than falls back** on a mismatch — the discipline `strongestOf` documents, applied to a verifier that does not share its candidate set. |

## Post-quantum posture

`SigningAlgoType.strongestFirst` puts `mldsa65` first and says why: it is the only member Shor's
algorithm does not break (`algo_type.dart:15-42`). PKAM and APKAM can therefore be post-quantum
**today**. A device credential cannot, and that gap belongs to this feature, not to the platform.

| Lane | PQ escape hatch | Cost |
| --- | --- | --- |
| **Browser** — this plan's scope | **None.** The key lives in the authenticator and its algorithm menu belongs to the vendor | — |
| Enterprise / OIDC | **None.** Assertions are RS256 / ES256 today | — |
| Native desktop, iOS, Android | **Yes** — ML-DSA in a biometric-ACL Keychain or credential-store item | Loses hardware non-exportability; Secure Enclave is P-256 only, TPM is RSA/ECC |

The browser is the only lane with no path, and it is the lane the feature exists for. ML-DSA COSE
code points are registered; no shipping platform authenticator generates them. `alg` on the
registration entry is where one lands when they do — which is why the entry records the algorithm
instead of assuming ES256.

**Why P-256 is acceptable here and would not be in an encryption path.** A device assertion is an
authentication signature: forging one needs a CRQC *at the moment of the connection*, so there is
no harvest-now-decrypt-later exposure of the kind `ml_kem_768` and `x_wing` exist to close. What
**is** harvestable is the registered public key — long-lived, and returned wholesale to every
namespace co-member by `enroll:listns` (see **Open, blocking**). Exposure runs from CRQC-day to
rotation, not for the length of one connection, which makes per-caller projection of `metadata` a
post-quantum question and not only a privacy one.

**The containment is the tier boundary.** A broken device credential waives an OTP and, if the
second use site ships, reads device-secrecy public hidden keys. It never yields atKeys, because
what authenticates is still the APKAM keypair — which can be `mldsa65` now. **T9** is what keeps
that true: the moment a device credential joins the set `strongestOf` chooses from, a P-256 key
satisfies an authentication requirement, and the stack's posture drops to the weakest hardware key
any device happened to register.

## Registration shape

`EnrollParams.metadata` is "opaque, additive metadata the server stores verbatim on the
enrollment record and returns from discovery (`enroll:listns`)"
(`enroll_params.dart:109-113`). Register under a reserved key, in the vocabulary `apsk` and
`KeyPackage` already use (`enroll_params.dart:45-49`) rather than a parallel one:

```json
{
  "trustedDevice": {
    "v": 1,
    "keys": [
      {
        "v": 1,
        "kid": "<credential id>",
        "use": "device-assert",
        "alg": "es256",
        "pub": "<COSE key>",
        "rpId": "app.example.com",
        "uv": true,
        "status": "active",
        "createdAt": 1757400000
      }
    ]
  }
}
```

| Field | Why |
| --- | --- |
| `"v"` **per entry** as well as on the wrapper | makes "a reader skips entries it does not know" well-defined per credential, not only per list |
| `rpId` | **T5**/**T7** — the only enforceable scope boundary; recorded so the server can reject an assertion from another origin |
| `uv` | **T7** — records that the credential was registered with user verification required, so a later assertion without it is refusable |
| `status` (`active` \| `retired`, absent = active) | the convention `apsk` already reserves (`enroll_params.dart:59-61`) — retirement without deletion |
| `createdAt` | audit, and tie-breaking when a device re-registers |

**Size cap — an agreement to obtain, not a decision made here.** `apsk` is capped by the
atServer at **20KB encoded, refused rather than truncated** (`enroll_params.dart:72-74`).
`metadata` has no stated cap and is returned verbatim in **every** `enroll:listns` response,
so a COSE key set — and a future OIDC JWKS — bloats every namespace listing for every
co-member. Needs an equivalent cap agreed with the atServer team.

Registration itself costs **no `at_commons` grammar change and no atServer release**.

## The exchange

```mermaid
sequenceDiagram
  participant App as web app (evicted)
  participant S as atServer
  App->>S: enroll:challenge (new operation)
  alt server supports the operation
    S-->>App: nonce (single-use, short TTL, rate-limited)
  else unsupported / no answer within timeout
    S-->>App: error or timeout → fall back to OTP
  end
  App->>App: challenge = H(nonce, atSign, apkamPublicKey)
  App->>App: authenticator signs authData + SHA-256(clientDataJSON), uv required
  App->>S: enroll:request (apkamPublicKey, trustedDevice.assertion)
  S->>S: match kid → credential; recompute challenge; verify rpIdHash, uv, signature
  alt verified
    S-->>App: pending — no OTP required
  else not verified
    S-->>App: one indistinguishable error — OTP required
  end
```

**The challenge is `H(nonce|atSign|apkamPublicKey)`, and that derivation is frozen.** A nonce
that binds nothing else lets a relayed or page-resident attacker orchestrate the ceremony and
have the user's credential vouch for **an `apkamPublicKey` the attacker controls**. The protocol
already has the precedent — `enroll:update` requires `apkamPublicKeySignature` binding possession
to the key being installed (`enroll_params.dart:92-107`), frozen as a two-repo byte contract in
`apkam_possession_proof.dart:4-27`.

**But the binding cannot be applied the same way, and this is the one place the WebAuthn
transport dictates the design.** An authenticator does not sign bytes the relying party hands it;
it signs `authenticatorData ‖ SHA-256(clientDataJSON)`, a framing neither the client nor the
atServer controls. The only field a relying party injects is `challenge`. So the binding moves
*into* the challenge: the server issues a nonce, both sides derive
`H(nonce|atSign|apkamPublicKey)` by the same frozen rule, and the server rejects any assertion
whose `clientDataJSON.challenge` does not equal its own recomputation against the
`apkamPublicKey` the request is actually installing.

**This costs a second verifier.** Checking the assertion means parsing `authenticatorData`,
recomputing the `clientDataJSON` hash, and verifying `rpIdHash`, the `uv` flag and the sign
count — none of which `signPkamChallenge`'s verifier does. The "one verifier, identical bytes,
two repositories that do not compile against each other" property that `apkam_possession_proof`
preserves **does not extend to this leg**, and **T9** requires that it not be made to.

**The credential must be discoverable (resident).** Reading the registered `kid` list back
would mean `enroll:listns`, executed authenticated (`enrollment_directory.dart:81-83`) — with
the APKAM key the eviction destroyed. So the client cannot supply `allowCredentials`; the
authenticator must enumerate its own credential for the origin. Having the server return
candidate `kid`s on the unauthenticated leg is rejected: it lets anyone enumerate how many
devices an atSign has trusted.

**The challenge leg is a new server operation, and capability negotiation is mandatory.**
`EnrollVerbBuilder.checkParams()` hard-requires `otp != null` **and** `apkamPublicKey != null`
(`enroll_verb_builder.dart:153-160`), and `AtEnrollmentRequest.otp` is non-nullable
(`at_enrollment_request.dart:109, 200, 240`). It cannot be smuggled through `metadata` instead
— that field is contractually opaque, so an atServer predating the feature would **silently
store a challenge request and never answer it**. Hence an explicit unsupported error plus a
client-side timeout.

## Credential lifecycle across a waived enrollment

**Metadata is only ever written by the request that creates the record** — there is no
post-enrollment metadata write and no `enroll:metadata` verb
(`enrollment_directory.dart:42-44`), and `metadataBuilder` fires once, after the APKAM keypair
is minted and before the request is sent (`at_enrollment_request.dart:112-130`). The
enrollment created by a waived recovery is the **only** chance to register a credential for it.

| Question | Ruling |
| --- | --- |
| Re-register the **same** credential, or mint a fresh one? | **Same credential, re-registered.** A fresh `create()` ceremony needs a user gesture mid-recovery; one abandoned recovery leaves the next eviction untrusted. |
| Scope of the registration | Per-enrollment, and it dies with the enrollment. The authenticator credential is a device fact that outlives any single enrollment. |
| Same `kid` under two enrollments | Permitted **only** transiently across a recovery. Verification accepts an assertion matching a registration on **any non-revoked** enrollment of that atSign. |
| Where the browser prompt happens | Not inside `metadataBuilder` — a poor place for a permission prompt. The provider completes `register()` **before** the request is assembled and hands the builder a plain map. |

## Code changes

| File | Change |
| --- | --- |
| `packages/at_commons/lib/src/verb/enroll_params.dart` | none to the wire; `otp` becomes optional-when-assertion-present at the **validation** layer |
| `packages/at_commons/lib/src/verb/enroll_verb_builder.dart` | `checkParams()` stops hard-requiring `otp != null` / `apkamPublicKey != null` for the challenge and assertion operations (`:153-160`) |
| `packages/at_auth/.../models/at_enrollment_request.dart` | `otp` is non-nullable today (`:109, 200, 240`) — a waiver request type needs it optional, or a sibling request class |
| new — `packages/at_auth/lib/src/enroll/trusted_device_challenge.dart` | the frozen `H(nonce\|atSign\|apkamPublicKey)` **challenge derivation** — a two-repo byte contract like `apkam_possession_proof.dart`, except what is frozen is the derived challenge, not the signed message |
| new — `packages/at_client/lib/src/trusted_device/` | `TrustedDeviceCredential`, `TrustedDeviceAssertion`, `TrustedDeviceProvider` (the adapter seam **T8** requires) |
| `packages/at_client/lib/src/response/enrollment.dart` | **larger than it looks** — the `Enrollment` response model has five fields and **no `metadata`** (`:1-31`), so the manage-side listing cannot see trusted-device entries until it is widened |
| `packages/at_client/lib/src/secret_sharing/enrollment_directory.dart` | read `metadata.trustedDevice` back from `enroll:listns` — for the **management UI**, not for the evicted client, which cannot call `listns` |
| **at_server (out of repo — external blocker for phases 3–4)** | challenge operation, nonce issuance and rate limiting, a **WebAuthn-shaped verifier** (parse `authenticatorData`, recompute the `clientDataJSON` hash, check `rpIdHash` / `uv` / sign count) kept **separate from the PKAM verifier** per **T9**, waiver decision, `metadata` size cap |

```dart
abstract class TrustedDeviceProvider {
  Future<bool> isAvailable();
  Future<Map<String, dynamic>?> register(AtKeysIo keysIo);
  Future<TrustedDeviceAssertion?> assertPossession({
    required String nonce,
    required String atSign,
    required String apkamPublicKey,
  });
}
```

`isAvailable()` backs the feature-detect fallback; `register()` returns the entry
`metadataBuilder` attaches; `assertPossession()` returns `kid`, the signed bytes, and the
transport-specific evidence (WebAuthn `clientDataJSON` / `authenticatorData`, or an OIDC JWT).
Fallback policy lives **inside** the provider, so "fall back to OTP" is code with tests.

## Failure modes

| Condition | Behaviour |
| --- | --- |
| No assertion supplied | Existing path unchanged — OTP or SPP required |
| **Assertion supplied, no matching `kid`** | **One indistinguishable error**, shared with the row below |
| **Signature, origin or `uv` does not verify** | **The same error, the same rate-limit bucket** |
| Nonce expired or replayed | Reject; issue a new nonce |
| Challenge operation unsupported by the atServer | Explicit unsupported error, or client timeout — fall back to OTP |
| Enrollment holding the registration was revoked | Registration is void — **T6** |
| Authenticator unavailable in this browser | `isAvailable()` feature-detect; fall back to OTP before prompting |
| User dismisses the authenticator prompt (registration **or** assertion) | Fall back to OTP; never leave the enrollment half-built |

**Why the two error rows are merged.** Distinct errors for "unknown `kid`" and "bad signature"
hand back device enumeration **one guess at a time** — a validity oracle on an unauthenticated
leg. One error, one bucket. **Rate limiting applies to both legs**: unauthenticated nonce
*issuance* per atSign is an unbounded DoS surface if only signature failures are throttled.

Every failure degrades to current behaviour. The feature can never make onboarding worse.

## Test matrix

| Case | Expectation |
| --- | --- |
| Registration round-trips through `enroll:listns` | `metadata.trustedDevice` returns verbatim |
| Unknown entry `v` / `use` / `alg` | Reader skips that entry, does not throw |
| Co-member's malformed or hostile `trustedDevice` blob in a `listns` response | Skipped like a malformed `keyPackage` (`enrollment_directory.dart:105-110`), roster still built |
| Valid assertion, no `otp` | Enrollment accepted |
| Challenge derived from an `apkamPublicKey` other than the one the request installs | Rejected — **T2** |
| `clientDataJSON.challenge` does not match the server's recomputation | Rejected — **T2** |
| Device credential offered where a PKAM/APKAM signature is required | Rejected, and the device key is absent from the candidate set — **T9** |
| Assertion algorithm differs from the registered `alg` | Rejected with no fallback to a weaker algorithm — **T10** |
| Replayed nonce | Rejected |
| Nonce issued for atSign A, presented for atSign B | Rejected |
| Assertion with wrong RP ID / origin | Rejected — **T7** |
| Assertion without user verification, credential registered `uv: true` | Rejected — **T7** |
| Assertion from a different atSign's credential | Rejected |
| Assertion from a **revoked** enrollment's registration | Rejected, and the old enrollment's status asserted revoked — **T6** |
| Same `kid` registered under two live enrollments | Behaviour per the lifecycle rulings, asserted explicitly |
| Unknown `kid` vs bad signature | **Byte-identical error responses**, same rate-limit counter |
| Rate limit on nonce issuance | Enforced, tested independently of signature failure |
| User dismisses the authenticator prompt | Falls back to OTP; no partial enrollment record |
| Registration against a pre-feature atServer | Inert — stored, ignored, no client error (validates phase 1) |
| No assertion | Byte-identical to today's OTP path |

## Phasing

| # | Step | Blocked on |
| --- | --- | --- |
| 1 | Data shapes + registration through `metadata`, no waiver — inert, verifiable against today's atServer | — |
| 2 | `TrustedDeviceProvider` + synthetic test-only implementation; frozen signable framing | — |
| 3 | atServer: challenge operation, nonce issuance, rate limiting, verification. Waiver behind a flag | **at_server team** |
| 4 | WebAuthn implementation, device-bound, `uv: 'required'` | 3 |
| 5 | Auto-approval decision | 3–4 in production |
| 6 | OIDC implementation as a separate adapter package | 2 |
| 7 | Device-secrecy read gate on `lookup:` — the second use site | 3 |
| 8 | Revisit the key-**retrieval** gate | the escrow question below |

Phases 1–2 need no browser work and no atServer release.

## Open, blocking

| Question | Why it blocks |
| --- | --- |
| **Does a verified waiver also auto-approve the enrollment?** | Without it, `enroll:approve` still needs `__manage` and a human taps *approve* on device 2 — the OTP goes, the human hop stays. With it, a device credential grants namespace access unattended. Decides whether phase 4 delivers the stated outcome. |
| **Must `enroll:listns` project `metadata` per-caller?** | It returns each approved enrollment's `metadata` map **wholesale** to every namespace co-member (`enrollment_directory.dart:89-100`) — so every app in a namespace learns every other enrollment's trusted-device public keys and device count, the same enumeration the unauthenticated leg refuses. Either the atServer projects per-caller, or this exposure is accepted. |
| **`metadata` size cap** | Needs an atServer-side limit, refused not truncated. Agreement to obtain. |

## The second use site: public hidden keys

Registered **devices** waive OTPs; trusted **connections** read device-secrecy keys. The second is
a smaller, separate feature on the same primitive, and it is no longer deferred.

A public hidden key (`public:_…`) is readable today by any unauthenticated connection that knows
its name. `lookup:` on an unauthenticated connection prefixes `public:` and serves whatever is
there; the `_` prefix affects only `scan:` listings, which filter it out. The handler also skips
the access log for `_` keys, so an unauthorised read is not recorded there. The protection is the
name being unguessable.

A device-secrecy attribute replaces obscurity with a gate: served only to a connection that has
proven which device it is on. That is a tier **below** authentication — the connection holds no
atKeys and cannot act as the atSign — which is exactly why a trusted *connection* is worth
defining separately from an authenticated one.

| Piece | Where |
| --- | --- |
| Per-key attribute | `Metadata`, beside `isPublic` / `isHidden` (`at_key.dart`) |
| Read gate | a `lookup:` parameter — the builder carries only `auth`, `operation`, `bypassCache` today (`lookup_verb_builder.dart:16-23`) |
| Proof on the connection | the same device assertion, verified once per connection rather than once per enrollment |

**`plookup:` cannot carry it.** Cross-atSign resolution is server-to-server, so the end user's
device proof never reaches the owner's atServer. A device-secrecy key is therefore device-scoped,
not shareable — a property to state before anyone designs against the opposite.

## Deferred — the key-retrieval gate

Gating retrieval of the enrollment record's **sealed key material** on a device proof is a
different proposition from the read gate above, and it remains **not viable as a recovery
path**. The enrollment record
does carry sealed material (`enroll_params.dart:13-17`), but the APKAM private key that
authenticates the fetch is minted on the requesting device and never transmitted, in either
the legacy `rsa2048` or the PQ `mldsa65` path. The ciphertext survives eviction; the connection
allowed to fetch it cannot be established, and per **T1** the presented identifier cannot
replace it. This is `enterprise-identity.md` **E1** from the other direction: the remedy is
re-enroll, not recovery from the server.

The `lookup:` mechanics are specified in the section above, so what blocks this is the escrow
question and not the mechanism. It belongs to a separate project: binding an **unwrapping** key
to a platform authenticator (WebAuthn PRF or equivalent).
