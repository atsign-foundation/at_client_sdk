# Trusted connections

* **Status:** Draft
* **Last Updated:** 2026-09-23
* **Objective:** Tag each connection with the device it comes from, and grant
  connections from registered devices authority that ordinary connections lack.

## The feature

Every connection already describes itself. The `from:` verb carries a
client config — `clientId`, `appName`, `appVersion`, `platform` — which the
atServer stamps on the connection's metadata. **Add one field: a device ID.**

The device ID is registered on the enrollment record when the owner approves
the device. A later connection that presents a registered ID, and proves it, is
a **trusted connection**.

### What a trusted connection may do

| Action | Ordinary connection | Trusted connection |
| --- | --- | --- |
| Re-enroll the same app on the same device | New OTP from the owner | No OTP |
| Read a **public hidden** key marked *device-secrecy* | Served to anyone who knows the name | Allowed |
| Have its re-enrollment approved | Owner approves | Open question |

The first row pays for the feature — how much depends on the first open
question. The second closes a hole.

### The second use site: public hidden keys

A public hidden key (`public:_…`) is readable today by **any unauthenticated
connection that knows its name**. `lookup:` on an unauthenticated connection
prefixes `public:` and serves whatever is there; the `_` prefix affects only
`scan:` listings, which filter it out. The handler also skips the access log
for `_` keys, so an unauthorized read is not recorded there.

The protection is the name being unguessable. A device-secrecy attribute
replaces that with a gate: the key is served only to a connection that has
proven which device it is on. Gated reads, allowed or refused, are logged —
the `_` skip would otherwise hide probing too.

This is also why a trusted connection is worth defining separately from an
authenticated one. It is a tier *below* authentication — the connection holds
no atKeys and cannot act as the atSign, but it has proven its device, which is
enough to read a key scoped to approved devices.

### What counts as a device ID

| Client | Feasible ID | Note |
| --- | --- | --- |
| Native desktop | MAC address, or the OS machine ID (`IOPlatformUUID`, `MachineGuid`, `/etc/machine-id`) | `dart:io` exposes neither — FFI or a platform channel. The paired key sits in the Secure Enclave, released by **Touch ID**; TPM with Windows Hello on Windows |
| iOS | `identifierForVendor` | MAC is fixed at `02:00:00:00:00:00` since iOS 7 |
| Android | `ANDROID_ID` | MAC restricted since Android 6, randomized per network since 10 |
| Browser | A device-bound passkey — Windows Hello, Microsoft Authenticator, a security key | No MAC, no hardware ID. Binding cannot be requested, only detected (the backup-eligible flag); iCloud Keychain and Google passkeys always sync. Authenticator is device-bound — to the phone, not the browser |
| Enterprise | A device claim in the tenant IdP's assertion | Entra ID / Okta compliance decides |

### Proof, not presentation

**A device ID is a name, not a secret.** The client config is self-reported;
anyone who has seen an ID once can send it. So authority never follows the ID
alone. At registration the device also registers a public key held by its
platform — Keychain, TPM, Android Keystore, passkey authenticator. A trusted
connection signs a fresh server challenge with it. The ID says *which* device;
the signature says *this* device.

The ID still earns its place: a re-enrolled device replaces its stale
enrollment rather than adding one, and management UIs have a name to show.

Three properties hold for every instance; dropping one makes a trusted
connection weaker than the OTP it replaces:

| Property | Consequence if dropped |
| --- | --- |
| Key is device-bound, sync disallowed | It reaches other machines and a vendor cloud — "this device" means nothing |
| User verification required | A stolen unlocked laptop acts as trusted silently |
| Challenge is fresh and single-use | A recorded signature replays forever |

## How this helps the browser

A web app keeps its atKeys in browser storage, which is evictable — on space
pressure, on privacy settings, on a cleared profile. Recovery is a fresh APKAM
enrollment, and today that needs a new OTP carried to the device by a human.
The same walk to a second device, every time a browser reclaims disk.

The browser is exactly where the obvious device IDs do not exist, and where
the cheap substitute fails: a random ID in `localStorage` is **circular** —
evicted alongside the keys it would recover.

**The passkey is the browser's device ID.** The authenticator holds it, not the
origin's storage, so it survives the event that creates the problem. It is
also scoped to the app's domain, so "same app, same device" comes from WebAuthn
itself.

1. At enrollment the app registers its passkey on the enrollment record.
2. Storage is evicted. The app has no keys and cannot authenticate.
3. The app opens a connection; `from:` returns the challenge it already issues
   for PKAM — single-use, 60-second TTL. Attempts are rate-limited.
4. The authenticator signs the challenge **with the atSign and the new APKAM
   public key**, under user verification.
5. The app sends `enroll:request` with the signature instead of an OTP.
6. The server matches the credential, verifies origin and signature, and waives
   the OTP. Any failure returns one indistinguishable error; the OTP path
   resumes.

**Step 4 is load-bearing.** Signing the challenge alone binds it to nothing —
a relaying attacker could have the user's own passkey vouch for an APKAM key the
attacker controls. `enroll:update` already signs over the key being installed;
same treatment, byte framing frozen as a two-repo contract.

**The passkey must be discoverable.** Listing registered credentials needs the
key eviction destroyed, so the app cannot supply an allow-list; returning
candidates unauthenticated would let anyone count an atSign's devices.

**This is a UX change, not a new capability.** The approver already re-seals
the user's keys onto the new record, so nothing becomes reachable that was not
reachable before.

## Goals

* One connection-level trust model, with the device ID as its only
  platform-specific part.
* Keep the security bar at or above the OTP path it replaces.
* Remove the OTP from browser re-enrollment after eviction.

### Non-goals

* Recovering evicted key material. The APKAM private key is minted on the
  device and never transmitted; the ciphertext survives eviction, the
  connection allowed to fetch it does not.
* Vendor-specific IdP code in the SDK.

## Considered Options

* ### Option 1 — Semi-permanent passcode

Already in the SDK (`setSPP` / `getOTP`). Reduces the friction without removing
it: still a shared secret a human conveys, still expiring, and setting it needs
`__manage`. Kept as the fallback.

* ### Option 2 — Present the device ID

The tag alone, checked for membership in the registered list. Rejected as the
source of authority — anyone who has seen the ID satisfies the check. Kept as
the connection's label in logs and management UIs.

* ### Option 3 — Device ID bound to a platform-held key

The tag names the device; a signature over a fresh challenge proves it. One
model across native, mobile and browser. **This is the proposal.**

* ### Option 4 — Federated assertion from the tenant's IdP

An Entra ID or Okta assertion is already signed, audience-bound and
short-lived, and the tenant's compliance policy becomes the trust decision.
Strongest of the four, unavailable to consumers. Taken as the enterprise
instance of Option 3.

## Proposal Summary

Adopt **Option 3**, with **Option 4** as its enterprise instance and
**Option 1** as the fallback when neither is available.

## Proposal in Detail

| Piece | Change | Where |
| --- | --- | --- |
| Device ID on the connection | One more client-config field on `from:` | at_commons, atServer connection metadata |
| Registration | Enrollment record's opaque `metadata` slot — no grammar change | at_commons |
| Challenge and verification | Reuse the `from:` challenge (fresh, 60 s TTL, removed on use); new work is rate limiting and the origin and signature checks | atServer |
| Device-secrecy keys | A new key metadata attribute (alongside `ttl`, `ccd`), a `lookup:` gate, and logging of gated reads | at_commons, atServer grammar |
| Client | One provider interface — native key, passkey, OIDC — with OTP fallback under test | at_client |

Four questions are open and belong to this review:

| Question | Why it blocks |
| --- | --- |
| Does a trusted connection also auto-approve? | If not, approval still needs `__manage` — the OTP goes, the walk to the second device stays. If so, the atServer grants namespaces but not keys: only an approving client can re-seal them, so removing the second device entirely means revisiting the key-recovery non-goal |
| Refuse synced passkeys? | Refusing backup-eligible credentials keeps "this device" honest but excludes most Safari and Chrome users; accepting them widens "device" to every device on the user's Apple or Google account |
| Who reads a device-secrecy key? | Every registered device is also enrolled and can authenticate, so the tier below authentication serves only a device whose keys were evicted — unless a device may be registered without enrolling (a kiosk, a sensor) |
| Who may see registered devices? | Enrollment discovery returns each record's metadata to every namespace co-member, so every app learns every device's key and count — the enumeration the unauthenticated leg refuses |

### Expected Consequences

* Device IDs are personal data — a MAC address especially. Store a hash salted
  per atSign, so one device is not correlatable across atSigns.
* A metadata size cap must be agreed with the atServer team, refused rather
  than truncated, or a growing device set bloats every enrollment listing.
* OTP handling becomes conditional — validation hard-requires an OTP today and
  the request model treats it as non-nullable.
* Capability negotiation is mandatory: an older atServer must return an explicit
  unsupported error rather than silently ignore the new field.
* The enrollment response model gains a metadata field, so management UIs can
  list and revoke trusted devices.
* A device-secrecy key stops being fetchable through `plookup:` from another
  atSign. That path is server-to-server, so the end user's device ID never
  reaches the owner's atServer — the key becomes device-scoped, not shareable.
