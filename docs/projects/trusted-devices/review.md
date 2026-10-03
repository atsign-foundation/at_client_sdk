# Trusted devices — architectural review

**Status:** proposal, for review. Implementation detail lives in `design.md` alongside this file.

---

## The idea

A device that has already been enrolled should not be treated as a stranger the next time it
asks. At enrollment, the device registers a credential of its own on the enrollment record. Later,
when it needs to enrol again, it proves possession of that credential and the one-time passcode is
waived. Any device that cannot produce one is challenged exactly as today.

The credential is held by the platform authenticator — Touch ID, Windows Hello, an authenticator
app — not by the web page. That is the whole trick: it survives the thing that caused the problem.

## What prompted it

| | |
| --- | --- |
| Where the keys live | A web app keeps its atKeys in browser storage (IndexedDB) |
| What goes wrong | Browsers evict that storage — on space pressure, on privacy settings, on a cleared profile. It is routine, not an edge case |
| What it costs today | Recovery is a fresh enrollment, and a fresh enrollment needs a new one-time passcode carried to the device by a human |
| What it does **not** cost | Data access is already restored on re-enrollment — the approver re-seals the user's keys onto the new record. **This is a UX change, not a new capability.** Nothing becomes reachable that was not reachable before |

The friction is the human hop, repeated every time a browser reclaims disk space. On a phone that
is the same person walking to a second device to read six digits, over and over.

## The one rule

**A fingerprint is an identifier, not a secret.** Anything the page can read, an observer can
read once and replay forever. So the waiver is never a stored-string comparison — it is a
signature over a challenge the server issues fresh each time. Screen resolution, canvas hashes,
user-agent strings and MAC-style device IDs all fail this test and none of them are in the design.

Three properties are non-negotiable, and dropping any one makes the scheme weaker than the
passcode it replaces:

- **Device-bound** — the credential must not sync to other machines or a vendor cloud, or "this
  device" means nothing.
- **User verification required** — biometric or PIN at each use, or a stolen unlocked laptop
  re-enrols silently.
- **Origin-verified server-side** — or any website can present the credential.

## How it works

1. At enrollment, the device creates a credential in its authenticator and registers the public
   half on the enrollment record.
2. Storage is later evicted. The app has no keys and cannot authenticate.
3. The app asks the atServer for a challenge — a single-use, short-lived nonce.
4. The authenticator signs the nonce **together with the atSign and the new enrollment key**,
   after a biometric or PIN prompt.
5. The app submits the enrollment request with that signature instead of a passcode.
6. The server matches the credential, checks the origin, verifies the signature — and accepts the
   request with no passcode. Anything that fails returns one indistinguishable error and the
   passcode path resumes.

Step 4 matters more than it looks: signing the nonce alone would let a relaying attacker have the
user's own credential vouch for a key the attacker controls. Binding the atSign and the enrollment
key into the signed bytes closes that.

## Optional enhancements

The same seam takes more than one credential provider. One adapter, several instances.

| Provider | Audience | Fit |
| --- | --- | --- |
| **Platform passkey** (Touch ID, Windows Hello) | Consumer, default | Baseline. Caveat: consumer passkeys are **synced by default** via iCloud Keychain and Google Password Manager, so device-binding must be requested explicitly |
| **Microsoft Authenticator** | Personal users who want a portable holder | Its passkeys are **device-bound only** — no sync. Same credential model, different holder, and it moves the trust anchor off the laptop that got wiped onto a phone the user already carries |
| **Entra ID / Okta** | Enterprise tenants | The strongest of the three. An OIDC assertion is already a signed, audience-bound, short-lived proof — a real credential, not an identifier. The tenant's existing device-compliance and conditional-access policy becomes the trust decision, at no cost to us |

The enterprise case has a standing constraint from the identity work: no vendor-specific IdP code
in the SDK. Entra and Okta arrive through generic OIDC, or they do not arrive.

## What it would take

- **Registration is free** — the enrollment record already carries an opaque metadata slot. No
  wire-format change, no atServer release.
- **The challenge step is the real work** — one new server-side operation to issue and verify
  nonces, plus signature and origin verification. That lands in the atServer team's repo, not
  ours, and is the external dependency for the whole feature.
- **Client-side** — a small provider abstraction so passkey and OIDC sit behind one interface, and
  fallback to the passcode is code with tests rather than a hope.

## Open for this call

| Question | Why it matters |
| --- | --- |
| **Does a verified waiver also auto-approve the enrollment?** | If not, approval still needs a privileged connection — the passcode goes away but the walk to the second device does not. If so, a device credential grants namespace access unattended. This decides whether the feature delivers the outcome we are describing |
| **Who can see the registered credentials?** | Enrollment discovery returns each record's metadata to every app sharing the namespace today. That would let one app learn every other device's credential and count them. Either the server filters per caller, or we accept the exposure knowingly |
