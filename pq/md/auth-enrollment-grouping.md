# Auth, Enrollment, and MLS Grouping — design

How per-device authentication, new-device enrollment, and the MLS group state interlock in an atProtocol-native multi-device deployment.

This sits on top of `mls-deep-dive.md` (the MLS algorithm itself) and answers: **what does a new device do from scratch to be a usable endpoint, and how does the group stay coherent across enroll/un-enroll events?**

---

## Read this first

Three layers stack on top of each other. Each is independent and replaceable.

```
┌──────────────────────────────────────────────────────────────┐
│ Layer 3 — MLS group                                          │
│           "Which devices belong to @bob?                     │
│            What is the current group epoch?"                 │
├──────────────────────────────────────────────────────────────┤
│ Layer 2 — Identity binding                                   │
│           "This device is authorized to act on behalf of     │
│            @bob, signed by an enroller @bob trusts."         │
├──────────────────────────────────────────────────────────────┤
│ Layer 1 — atServer authentication (PKAM / APKAM)             │
│           "This connection is allowed to talk to             │
│            @bob's atServer."                                 │
└──────────────────────────────────────────────────────────────┘
```

Failure at a lower layer makes the upper layers irrelevant; success at a lower layer says nothing about the upper ones. Each must be checked separately.

---

## Layer 1 — atServer authentication

Already exists in atProtocol. Reusing without modification.

| Mechanism | Use |
|---|---|
| **PKAM** (Public Key Authenticated Method) | A device proves it holds the private half of an RSA-2048 keypair the atServer has on file under the device's `apkam` / `pkam` atKey. Challenge-response handshake on connect. |
| **APKAM** | Per-application PKAM. Each enrolled app gets a distinct keypair scoped by namespace + app ID. Lets the atServer revoke an app without invalidating other apps. |

**For our purposes:** every device starts each session by authenticating at this layer. Everything above (identity binding, MLS) assumes the connection is already authenticated to talk to the atServer.

**PQ migration of Layer 1:** PKAM is RSA-2048 today. A separate migration replaces it with an ML-DSA or X-Wing signing flow. Independent of MLS.

---

## Layer 2 — Identity binding

This is the layer that says "this connection (Layer 1) is also entitled to act as a specific MLS member identity."

Why a separate layer: Layer 1 says "this device can write to @bob's atServer." It does **not** say "this device is allowed to receive @bob's incoming Triple-Ratchet / MLS messages." A compromised app key with Layer 1 access shouldn't automatically inherit MLS group membership.

### Per-device identity material

Generated once at enrollment and persisted in the device's local keystore:

| Material | Purpose | PQ? |
|---|---|---|
| `ikSig` (Ed25519 keypair) | Identity signing — signs SPKs, MLS LeafNode credentials, Commits | Ed25519 today; ML-DSA in PQ extension |
| `ikDh` (X25519 keypair) | Long-lived DH for Triple-Ratchet path (if also running 1:1 ratchet) | X25519 + ML-KEM hybrid |
| `mls_init` HPKE keypair (inside KeyPackage) | One-shot encryption target for the Welcome message | X25519 today; X-Wing PQ variant |
| `mls_leaf` HPKE keypair | This device's leaf in the MLS tree; rotates on Update | Same |
| **Identity credential** | Binds `ikSig.pk` to the atSign + device ID. Signed by the enrolling device (or a self-signed root for the first device). | Signature primitive same as `ikSig` |

The identity credential is the bridge from Layer 1 (atServer says "this is bob's device") to Layer 3 (MLS group accepts this LeafNode).

### Credential format

Minimal sufficient credential:

```jsonc
{
  "atSign":    "bob",
  "deviceId":  "laptop-2026-05",
  "ikSigPk":   "<hex 32B>",
  "issuedAt":  1748000000000,
  "issuer":    {
    "deviceId": "phone-2026-01",   // enrolling device, or "self" for root
    "ikSigPk":  "<hex 32B>"
  },
  "signature": "<hex 64B>"          // issuer signs the above blob
}
```

Published as `credential.<device-id>.pqchat@bob` on bob's atServer.

The MLS LeafNode for this device references the credential atKey; group members verify the chain back to the root (first device's self-signed credential) before accepting an Add proposal.

---

## Layer 3 — MLS group

Per `mls-deep-dive.md`. One MLS group per atSign. Group members = the atSign's devices. Group size grows + shrinks as devices enroll + unenroll.

### atKeys involved

| atKey | Holder | Purpose |
|---|---|---|
| `credential.<device-id>.pqchat@bob` | per device | Identity credential (Layer 2) |
| `keypackage.<device-id>.<seq>.mls.pqchat@bob` | per device, pool of N | Pre-published KeyPackages (consumed once on Add). Last-resort fallback when pool drains. |
| `mlsgroup.pqchat@bob` | one per atSign | Current GroupInfo (members list, current epoch, tree hash, signed by group committer) |
| `mlscommit.<epoch>.pqchat@bob` | one per epoch | Each accepted Commit, append-only log |
| `mlswelcome.<keypackage-hash>.pqchat@bob` | one per new join | Encrypted Welcome targeted to a specific KeyPackage hash; deleted after consumption |

Bob's devices monitor `mlscommit.*` and `mlswelcome.*` to keep their local state current.

---

## Enrollment flows

### Flow A — First device (new atSign)

```
1. User obtains an atSign through normal at_register (out of scope here).
2. First device generates Layer 1 (PKAM) keypair → completes initial atServer auth.
3. First device generates Layer 2 identity material:
     ikSig, ikDh, plus a SELF-SIGNED root credential
     publish credential.<device-id>.pqchat@bob
4. First device generates Layer 3 MLS state:
     Create a new MLS group with this device as the only member
     Generate first KeyPackage(s) for itself (rare — only useful if
     this device wants to be Add-able later, e.g. after a wipe)
     publish mlsgroup.pqchat@bob   ← GroupInfo for group-of-1, epoch 0
5. First device persists keystore to disk (.atKeys analog).

Result: @bob is now ready to send/receive at PQ layer.
The group is a singleton. Self-signed credential is the trust root.
```

**Trust note:** the first-device credential is self-signed. All subsequent devices' credentials trace through it (or through another existing device that traces through it). If the first-device private key is later compromised, *all* later credentials must be rotated and a new self-signed root established.

### Flow B — Second/Nth device (existing atSign)

```
1. New device installs the app; obtains an APKAM authorization
   from an existing device (existing OTP-based enrollment).
2. New device completes Layer 1 auth to bob's atServer.

   ─── Existing device (the "enroller") action: ────────────────
3. Enroller's device queries pending enrollments via existing
   atProtocol verb; sees the new device's APKAM enrollment request.
4. User confirms on the enroller (existing OTP/biometric flow).
5. Enroller approves Layer 1 — APKAM keys provisioned.
   ──────────────────────────────────────────────────────────────

6. New device generates Layer 2:
     ikSig, ikDh
     CRAFT a credential request: { atSign, deviceId, ikSigPk, issuedAt }
     publish credential_request.<device-id>.pqchat@bob

7. Enroller's monitor stream sees the credential_request.
   Enroller verifies (matches the APKAM enrollment it just approved).
   Enroller signs the credential with its own ikSig.sk.
   publish credential.<device-id>.pqchat@bob  ← signed by enroller's ikSig

8. New device generates Layer 3:
     ikSig now exists → can sign LeafNode for an MLS KeyPackage
     KeyPackage references credential.<device-id>.pqchat@bob
     publish keypackage.<device-id>.0.mls.pqchat@bob

   ─── Enroller's action: ───────────────────────────────────────
9. Enroller's monitor sees the new KeyPackage.
10. Enroller proposes Add(new device's KeyPackage) + UpdatePath.
11. Enroller commits → new epoch.
12. Enroller produces a Welcome targeted at the new KeyPackage.
    publish mlswelcome.<keypackage-hash>.pqchat@bob
    publish mlscommit.<new-epoch>.pqchat@bob
    update mlsgroup.pqchat@bob to the new GroupInfo
   ──────────────────────────────────────────────────────────────

13. New device's monitor picks up its Welcome.
    Decrypts with KeyPackage.init_sk → joiner_secret + GroupInfo.
    Builds the local MLS tree; persists state.

Result: new device is a full member at the current epoch.
```

**What if multiple existing devices race to enroll the same new device?** Each generates its own Commit. The atServer (or any agreed leader-election) orders them; only one Commit wins. Losing enrollers re-propose the Welcome against the new epoch if needed. Practical mitigation: only the device that approved the APKAM enrollment performs the MLS Add — other devices stand down by checking the credential's issuer.

### Flow C — Device recovery / replacement (lost device)

```
1. User reports the device lost from any other enrolled device.

2. The reporting device runs Layer 1 revocation:
     existing APKAM revocation flow — invalidates the lost device's
     keypair on bob's atServer. The lost device can no longer
     authenticate.

3. The reporting device runs Layer 2 / 3 revocation:
     a. Remove(leaf_index of lost device) Proposal in MLS
     b. Commit with UpdatePath → new epoch (PCS rotation)
     c. Update mlsgroup.pqchat@bob

4. The lost device, even if it eventually reconnects with its
   stolen Layer 1 key, fails Layer 1 (revoked). Even if Layer 1
   were bypassed somehow, it would fail Layer 3 — it's not in
   the new tree.

5. Stored messages encrypted to the old epoch (before the lost
   device left) remain readable by the lost device until those
   epochs' material is wiped from disk. The new epoch and forward
   are PCS-protected.
```

**Trust caveat:** if the lost device's `ikSig.sk` was compromised before revocation, the attacker could have already enrolled a third device by issuing a credential for it. Mitigation: when a device is reported lost, every credential it issued must be reviewed; treat the entire subtree of "credentials issued by the lost device" as suspect until manually re-approved.

---

## Authentication flow per session

Each time a device starts a connection, three checks fire in order:

```
1. Layer 1: connect to bob's atServer
   PKAM/APKAM challenge → connection authenticated.
   If fail: abort.

2. Layer 2: load local credential.<device-id>.pqchat@bob
   Verify signature chain back to a known root (first device's self-signed credential).
   Verify atSign matches.
   If fail: alert user, abort.

3. Layer 3: load local MLS state
   Verify it matches mlsgroup.pqchat@bob's current epoch
   (or replay Commits from local epoch to current — see "Catch-up" below).
   If fail: re-sync from atServer.
```

After all three pass, the device is fully operational.

---

## Catch-up after offline

Most realistic scenario: a device returns after hours/days offline.

```
On reconnect, the device:

1. Auth Layer 1 (PKAM session).
2. Verify credential is still issued (no Remove against it).
3. plookup current mlsgroup.pqchat@bob → current epoch E_now
4. plookup mlscommit.<E_local+1>.pqchat@bob through mlscommit.<E_now>.pqchat@bob
5. For each missed Commit:
     verify signature
     verify UpdatePath
     apply locally
     advance epoch counter
6. plookup queued application messages
7. Decrypt with the appropriate epoch's per-leaf chain.
```

Storage cost: one atKey per Commit. For a chatty group, this can grow large. Two mitigation strategies:

| Strategy | How |
|---|---|
| **Pruning** | Periodically delete Commits older than the oldest member's last-seen epoch. Requires tracking last-seen per device. |
| **Snapshots** | Every K Commits, store a complete GroupInfo as `mls_snapshot.<epoch>.pqchat@bob`. Late-joining devices start from snapshot + delta. |

Both are operational concerns — MLS itself doesn't mandate either.

---

## Threat model

### Defended

| Threat | Mechanism |
|---|---|
| Compromised atServer reads messages | All MLS material is ciphertext to the server |
| Compromised atServer reorders Commits maliciously | Each Commit is signed; tampering detected |
| One device's keystore stolen (post-revoke) | Removed via Remove + Commit; PCS within one epoch |
| Replay of old messages | Per-message generation counter; chain has moved past |
| Forged enrollment from outside | Credential signature chain rooted at first device must verify |
| Forged Commit | Confirmation_tag (MAC under confirmation_key) + signature; only group members can produce |

### NOT defended

| Threat | Why |
|---|---|
| First device's `ikSig.sk` compromise before any other devices exist | No issuer chain to verify against; attacker can fork the identity. Mitigation: out-of-band identity verification (e.g., fingerprint check via QR scan when adding a second device). |
| Attacker compromises an enrolling device DURING enrollment | They issue valid credential for their own keys. Mitigation: confirm on enroller via biometric + user verification, not just OTP. |
| atServer denies service (won't deliver Commits/Welcomes) | Out of scope; atProtocol-level concern, not MLS. |
| User physically loses unrevoked device for an extended time | Until revocation, the device can decrypt anything sent to it. |
| Side-channel attacks on Dart/Rust runtime | Outside cryptographic protocol scope. |

---

## Cross-cutting choices

Decisions that affect the design but aren't dictated by it:

| Decision | Options | Recommendation |
|---|---|---|
| Credential signature primitive | Ed25519 / ML-DSA / both (hybrid) | Ed25519 today, add ML-DSA in parallel for PQ resilience. Verify either. |
| Commit cadence for PCS rhythm | Per-Add only / per-Add + periodic self-Update / per-message | Periodic self-Update (e.g., every 100 messages OR every 24h, whichever first). |
| KeyPackage pool size per device | 1 / 10 / 100 | 10 per device, with last-resort fallback when drained. |
| Welcome retention on atServer | Delete on consume / TTL 30d / forever | Delete on consume + TTL 7 days as safety net (cleans up Welcomes for never-joined KeyPackages). |
| Snapshot interval | Every 50 / 100 / 1000 Commits | 100, with last 10 raw Commits kept for fine-grained catch-up. |
| Revocation propagation | Push / pull / both | Pull (next-connect check); push notification optional. |

---

## What this design does NOT cover

Out of scope (separate planning artifacts):

- **First-time atSign creation** (`at_register` is unchanged).
- **PQ migration of Layer 1 PKAM** (separate effort).
- **Group chat** (more than one atSign sharing a group) — single-user multi-device only here. Multi-atSign extends naturally but needs separate trust-model thinking.
- **Wire format details for Welcomes / Commits** — refer to RFC 9420 + the chosen MLS implementation.
- **UI/UX flows** for "approve this new device" — assumed to reuse the current OTP/biometric APKAM pattern.

---

## Open questions for follow-up

1. **Does `ikSig` (identity signing) reuse the existing PKAM/APKAM keypair, or is it a separate Ed25519 keypair?** Probably separate — APKAM is RSA-2048; mixing identity-level signatures across primitives creates audit complexity. Separate keys, even if both held on the same device.
2. **How does the credential chain compress after many enrollments?** A device enrolled through 5 generations of issuers has a 5-step chain. Compaction via a "trusted set" snapshot signed by ≥2 currently-trusted devices.
3. **What does "delete a device" mean for end users?** Layer 1 revocation + Layer 3 Remove are independent; should the UI bundle them as one action.
4. **Re-enrollment after wipe**: device reinstalls fresh, no local keystore. Treated as a *new* device via Flow B (new credential + new KeyPackage); old credential expires naturally.
5. **Multi-atSign per app**: one app on a phone supports both @alice_personal and @alice_work. Are MLS groups fully isolated? (Yes — each atSign has its own group, no sharing of LeafNodes.)

---

## Summary table

| Concern | Mechanism | Existing or new |
|---|---|---|
| Can this connection talk to bob's atServer? | PKAM / APKAM challenge | Existing |
| Is this device authorized to act as bob? | Credential atKey, signed-chain verification | New |
| Is this device a current MLS group member? | LeafNode in `mlsgroup.pqchat@bob`, traced to current epoch | New |
| How does a new device join? | Layer 1 APKAM approval → credential signed by enroller → KeyPackage published → Commit + Welcome | Layer 1 existing; Layer 2/3 new |
| How is a lost device removed? | Layer 1 APKAM revoke → MLS Remove + Commit | Layer 1 existing; Layer 3 new |
| How does an offline device catch up? | Replay missed Commits from atServer log | New |
| What protects messages in transit? | MLS application-key chain → AEAD seal | New |
| What protects messages on atServer? | Already ciphertext; atServer never holds keys | Cryptographically guaranteed by design |