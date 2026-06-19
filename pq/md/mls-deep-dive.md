# MLS — Messaging Layer Security, deep dive

RFC 9420 (July 2023). The IETF standard for end-to-end encrypted group messaging.

This document explains the **mechanisms**: how the group state is structured, how keys evolve, how the operations work, how forward secrecy and post-compromise security are achieved, and how the moving parts fit together. It is not a wire-format reference.

---

## Read this first (30 seconds)

MLS is a **continuous group key agreement (CGKA)**: every member of a group derives the same shared secret each "epoch," and the secret evolves whenever the membership changes or any member refreshes their keypair. Every change costs **O(log N)** asymmetric operations instead of O(N) — that's the whole reason MLS exists.

| Layer | What it does |
|---|---|
| **Ratcheting tree (TreeKEM)** | Stores per-member keypairs in a binary tree; refreshing one leaf updates only the path to the root (O(log N) work). |
| **Key schedule** | A deterministic KDF chain derives a stack of per-epoch secrets from the tree's root key. |
| **Operations + Commits** | Members propose changes (Add, Remove, Update, PSK). One member bundles proposals into a Commit, which advances the epoch. |
| **KeyPackages + Welcomes** | New members are added by encrypting the joiner secret under their pre-published KeyPackage. |

Everything else in MLS is structure around those four ideas.

---

## Why MLS exists (motivation)

The Signal Double Ratchet is great for two-party sessions but breaks down for groups:

| Scenario | Pairwise (Signal) cost | MLS cost |
|---|---|---|
| 1-to-1 chat | 1 ratchet | overkill — use Signal |
| 5-person group | 10 pairwise sessions; each sender encrypts 4 times | 1 group key; sender encrypts once |
| Member joins | 4 new pairwise sessions to set up | 1 Commit, O(log 5) HPKE ops |
| Member leaves | nothing automatic — every other member must rotate | 1 Commit; the removed member is cryptographically excluded |
| 100-person group | 100×99/2 = 4,950 pairwise sessions | 1 group key |

MLS gives you **one shared group secret** that evolves predictably without quadratic blowup. Multi-device (which is the special case "group with one user, multiple devices") falls out naturally.

---

## The group state structure

Every member holds a **left-balanced binary tree** of size ≥ N (next power of two ≥ N), where N is the member count.

```
                      ROOT
                     /    \
                  N5        N6
                 /  \      /  \
                N1   N2   N3   N4
               /\   /\   /\   /\
              L0 L1 L2 L3 L4 L5 L6 L7
              ^  ^  ^  ^  ^  ^   <-- 6 members
              M0 M1 M2 M3 M4 M5
```

- **Leaves (`Li`)** are members. Each leaf stores a public LeafNode with the member's signing key + HPKE init key + identity credential.
- **Internal nodes (`Ni`)** are virtual — they store an HPKE keypair derived from the leaves below them. The **public part** is known to every group member; the **private part** is known only to members whose leaves are in that node's subtree.

The **root's HPKE private key** is the shared secret all members can derive. Each member computes it by following their leaf's path up to the root using the private keys they hold.

**Key property:** any subtree's private key is known by exactly the members in that subtree. A member outside the subtree only knows the public key.

---

## TreeKEM — the ratcheting mechanism

When member `M` rotates their leaf keypair (an Update), they must also rotate every internal node on the path from their leaf to the root — because those nodes' private keys were derived from `M`'s contribution.

**The path update procedure (the heart of MLS):**

```
Member M at leaf L wants to refresh.

1. M generates a new leaf HPKE keypair.
2. M derives a chain of HPKE secrets up the path:
       path_secret[0] = HPKE_init(leaf)
       path_secret[i+1] = KDF(path_secret[i], "path")
3. For each internal node N_i on the path L → ROOT:
       new_keypair_i = derive HPKE keypair from path_secret[i+1]
       For each "co-path" subtree at level i (the subtree NOT containing L):
         encrypt path_secret[i+1] under the public key of that subtree
   This produces an UpdatePath: a list of (new public key, encrypted-to-co-path)
   tuples, one per level.
4. M broadcasts the UpdatePath inside a Commit.
```

**What other members do on receipt:**

```
Each other member M':
  find the level at which their leaf and L's leaf diverge — call it k
  M's leaf is in M's subtree at level k+1; M' is in the co-path subtree
  decrypt UpdatePath[k]'s ciphertext using M's private key at the subtree node
  obtain path_secret[k+1]
  walk forward: path_secret[k+1] → path_secret[k+2] → ... → root_secret
  install new public keys (from the UpdatePath) for all nodes above level k
```

**Cost analysis:**

| Actor | Cost |
|---|---|
| Updater (M) | O(log N) HPKE encryptions |
| Each other member | 1 HPKE decryption + O(log N) KDF steps |
| Wire size of UpdatePath | O(log N) HPKE ciphertexts ≈ log N × ~200B |

For a 1024-member group: 10 HPKE encrypts/decrypts per Update. Compare to pairwise Signal: 1023 ratchet steps per Update.

**Why it works:** the only thing the UpdatePath leaks is encrypted blobs that only the right subtree members can open. Each new path_secret is fresh entropy; the new root key is independent of the old.

---

## The key schedule (per-epoch secrets)

When a Commit advances the epoch, every member computes a new chain of secrets from the tree's new root key:

```
   init_secret  ──┐                           init_secret = previous epoch's epoch_secret
                  ├─ HKDF.extract → joiner_secret
   psk_secret  ───┘                           psk_secret from any PSK proposals (or zeros)
                                                       │
                            commit_secret  ────────────┤    commit_secret = tree's new root path_secret
                                                       ▼
                                  HKDF.extract → epoch_secret
                                                       │
            ┌────────────────────┬───────────┬─────────┴─────────┬──────────────────────┐
            ▼                    ▼           ▼                   ▼                      ▼
    sender_data_secret   encryption_secret  exporter_secret  authentication_secret  external_secret
                                                                                         │
            ┌────────────────────┬───────────┬─────────┬───────────────┐                ▼
            ▼                    ▼           ▼         ▼               ▼            external_pub
    confirmation_key      membership_key  resumption_psk  epoch_authenticator  init_secret_next
```

Each secret has a specific purpose:

| Secret | Purpose |
|---|---|
| `epoch_secret` | The root of the schedule. Never used directly. |
| `sender_data_secret` | Encrypts per-message metadata (sender ID, generation) so the wire doesn't leak it. |
| `encryption_secret` | Root of per-leaf application message ratchets. |
| `exporter_secret` | Lets applications derive their own out-of-band shared secrets (e.g., for video keys). |
| `authentication_secret` | Used in MAC computations on handshake messages. |
| `external_secret` | Lets external commit authors join. The corresponding `external_pub` is published with the group state. |
| `confirmation_key` | Used to compute the `confirmation_tag` proving the committer knows the new epoch secret. |
| `membership_key` | MACs handshake messages so non-members can't forge them. |
| `resumption_psk` | Used as a PSK in future re-joins (e.g., re-adding a previously removed member). |
| `epoch_authenticator` | Public hash of the epoch state for out-of-band verification. |
| `init_secret_next` | Becomes `init_secret` for the *next* epoch — chains the schedule forward. |

---

## Per-application-message keys (the chain inside an epoch)

Each member's `encryption_secret` derives a **per-leaf** symmetric ratchet that produces a fresh AES key per application message:

```
For member at leaf L:
  leaf_secret[0] = KDF(encryption_secret, leaf_index = L)
  leaf_secret[i+1] = KDF(leaf_secret[i], "chain")
  msg_key[i] = KDF(leaf_secret[i], "key")
  msg_nonce[i] = KDF(leaf_secret[i], "nonce")
```

This is the Double Ratchet's chain step pattern, but indexed per-leaf so multiple senders within a group don't collide. Each member tracks their own leaf's `generation` counter.

**Forward secrecy within an epoch** = the chain ratchets forward one-way; past `msg_key`s are unrecoverable from the current `leaf_secret`.

---

## Operations

MLS distinguishes **Proposals** (suggestions) from **Commits** (the action that finalizes a set of proposals and advances the epoch).

| Proposal | Effect |
|---|---|
| **Add(KeyPackage)** | Adds a new member at the next available leaf. New member receives a Welcome alongside the Commit. |
| **Remove(leaf_index)** | Removes a member. Their leaf is "blanked" (marked invalid). |
| **Update(LeafNode)** | A member rotates their own leaf keypair. Triggers an UpdatePath. |
| **PSK(psk_id, nonce)** | Injects a pre-shared key into the next key schedule (used for resumption, out-of-band trust anchors). |
| **ReInit(...)** | Hard-resets the group with new parameters (e.g., new cipher suite). |
| **ExternalInit(...)** | Used in an External Commit by a non-member joining. |

**Commits:**

```
A Commit = (list of Proposals) + (UpdatePath if needed) + confirmation_tag
```

Any member can author a Commit. The Commit:

1. References Proposals by hash (the proposals may have been sent earlier and stored on the server).
2. Applies them in order to compute the new tree state.
3. Includes an UpdatePath when needed — required when adding/removing/updating someone with secret material on the path.
4. Computes the new epoch's secrets.
5. Signs the Commit with the committer's identity key.
6. Includes a `confirmation_tag = MAC(confirmation_key, transcript_hash)` proving the committer reached the new epoch.

Other members verify and apply identically.

**Race condition:** two members might Commit concurrently. The protocol resolves this via **server-assigned ordering** — the server (or a leader) decides which Commit wins; the loser re-proposes against the new epoch.

---

## KeyPackages — the per-device "business card"

A **KeyPackage** is what a device pre-publishes so others can Add them to groups.

```
KeyPackage = {
  protocol_version,
  cipher_suite,
  init_key:    HPKE public key (one-time-use ideally),
  leaf_node:   {
    encryption_key:   HPKE public key for the leaf,
    signature_key:    identity Ed25519/etc. public key,
    credential:       identity (e.g., user@server, certificate),
    capabilities:     list of supported ciphersuites, proposals, extensions,
    lifetime:         valid from/until (timestamps),
    extensions:       [...]
  },
  extensions: [...],
  signature: Ed25519/etc. over the above, by the device's identity key
}
```

**Two-key design:** `init_key` is used **once** to encrypt the Welcome to a joiner. `encryption_key` is the leaf's HPKE key used in TreeKEM operations afterward.

**Pre-publication:** devices publish a *pool* of KeyPackages on a directory. Each is consumed once when someone Adds the device. If the pool runs dry, devices fall back to a "last-resort" KeyPackage with reuse allowed (degrades joiner forward secrecy slightly).

---

## Welcome messages

When a Commit includes an Add(KeyPackage), the committer also produces a **Welcome** for the new member:

```
Welcome = {
  cipher_suite,
  secrets: list of {
    new_member_key_id,
    encrypted_group_secrets: HPKE.Seal(
       to = KeyPackage.init_key,
       plaintext = {
         joiner_secret,           // the new member needs this
         path_secret (optional),  // their leaf's path_secret in the new tree
         psk_nonce
       }
    )
  },
  encrypted_group_info: AES-GCM.Seal(
    key = welcome_secret,         // derived from joiner_secret
    plaintext = GroupInfo {
      group_id, epoch, tree_hash, confirmed_transcript_hash,
      extensions, signer, signature, ...
    }
  )
}
```

**New member's flow:**

```
1. Receive Welcome via some delivery channel (atProtocol notify, etc.).
2. Find the entry matching one of my KeyPackages (by key_id hash).
3. HPKE.Open with KeyPackage.init_sk → recover joiner_secret + path_secret.
4. Derive welcome_secret from joiner_secret.
5. Decrypt encrypted_group_info → GroupInfo.
6. Build the local tree from GroupInfo + the path_secret.
7. Derive all per-epoch secrets.
8. Member is now in the group at the current epoch.
```

**Bonus:** the joiner can immediately decrypt application messages sent in this epoch — even ones authored *before* their Welcome arrived, as long as the server preserved them.

---

## Forward secrecy and PCS — exactly how

Both properties come from specific mechanisms:

### Forward secrecy

| Granularity | Mechanism |
|---|---|
| Per-application-message | `leaf_secret` chain (HKDF one-way); past `msg_key`s unrecoverable from current state. |
| Per-epoch | `init_secret_next` becomes the next epoch's `init_secret`; the old `epoch_secret` is discarded after the Commit. |
| Long-term | UpdatePath replaces internal node keypairs with fresh entropy; old internal SKs no longer needed. |

If an attacker steals a member's current epoch state, they cannot decrypt any past application messages (chain is one-way) and cannot decrypt past epoch's messages (epoch secrets are forgotten).

### Post-compromise security (PCS)

| Granularity | Mechanism |
|---|---|
| Per Commit | UpdatePath introduces fresh HPKE secrets the attacker cannot derive without re-compromising. |
| Self-healing | If member M is compromised, the next Update by *any* member rotates the path; M's stolen state stops being useful once the next Commit (with a path) lands. |

**Caveat:** PCS only fires after a Commit-with-UpdatePath. A Commit that contains *only* Add proposals (no Update) doesn't rotate path secrets. Best practice: every Commit includes a self-Update to maintain PCS rhythm.

---

## Cipher suites

RFC 9420 defines six base cipher suites (id values 1–6). Each picks {HPKE KEM, AEAD, hash, signature}:

| ID | KEM | AEAD | Hash | Signature |
|---|---|---|---|---|
| 1 | DHKEM-X25519 | AES-128-GCM | SHA-256 | Ed25519 |
| 2 | DHKEM-P256 | AES-128-GCM | SHA-256 | P-256 |
| 3 | DHKEM-X25519 | ChaCha20-Poly1305 | SHA-256 | Ed25519 |
| 4 | DHKEM-X448 | AES-256-GCM | SHA-512 | Ed448 |
| 5 | DHKEM-P521 | AES-256-GCM | SHA-512 | P-521 |
| 6 | DHKEM-X448 | ChaCha20-Poly1305 | SHA-512 | Ed448 |

**PQ extensions (active IETF work):**

- `draft-ietf-mls-extensions` includes a PQ KEM hybrid suite using **X-Wing** (X25519 + ML-KEM-768).
- Post-quantum signatures (e.g., ML-DSA) being discussed for identity keys.
- Once ratified, multi-device PQ-MLS becomes drop-in.

**Today (May 2026):** PQ-MLS drafts exist; production usage limited. Using ML-KEM-768 inside MLS is feasible by extending an existing MLS implementation, but cipher-suite negotiation across implementations isn't standardized yet.

---

## Async-friendly: how offline devices catch up

This is where MLS shines vs naive group schemes.

**Storage model:** the server keeps three append-only logs per group:

1. **Welcome log** — entries indexed by recipient KeyPackage hash; new joiners read only theirs.
2. **Commit log** — every accepted Commit in epoch order. Public.
3. **Application message log** — encrypted app messages, with per-message generation counter.

**Offline device's reconnect flow:**

```
Device wakes up at epoch E_local. Group is now at epoch E_current.

1. Fetch Commits [E_local+1 .. E_current] from server's Commit log.
2. For each Commit:
     - Validate signature + confirmation_tag.
     - Apply Proposals to local tree.
     - Apply UpdatePath if present (decrypt path_secret for our subtree).
     - Advance key schedule to next epoch.
     - Persist new state.
3. Fetch application messages [last_seen .. now] from app message log.
4. Decrypt each with the appropriate epoch's per-leaf chain.
```

Cost is proportional to the number of missed Commits + missed messages, not the group size. A device offline for a week with 100 Commits in between does 100 × O(log N) Commit-application work.

**Welcome storage:** when a device is added, the committer writes the Welcome to the server. The new device fetches it on its first poll. If the device is offline for days when added, the Welcome waits.

---

## External senders + external commits

Two modes for non-members to interact with a group:

### External senders

A non-member can encrypt **application messages** to the group without joining. They learn the `external_secret`-derived `external_pub` from the published group info. Each message they send is HPKE-sealed under that key.

| Use case | Example |
|---|---|
| Server-side admin announcements | "Member X has been moderated" |
| One-way notifications from an external service | A backup-service posting a one-time alert |

External senders can't *decrypt* anything; they just inject signed encrypted messages.

### External commits

A non-member can join the group **without an Add proposal from an existing member**, by sending an External Commit:

```
External committer (joining):
  1. Fetch the group's published GroupInfo.
  2. Generate own LeafNode + path.
  3. Construct ExternalCommit:
       - Proposal: ExternalInit (proves they computed the right external_secret)
       - UpdatePath
       - Implicit Add at next available leaf
       - Optionally: Remove proposals for stale members
  4. Submit to server.

Existing members:
  - Validate ExternalCommit.
  - Apply (the new member is added without anyone explicitly authorizing).
```

This requires group **policy** to allow it — usually limited to specific identities (e.g., the group's "manager" entity).

---

## How MLS handles your three constraints

Recapping the constraints we cared about:

| Constraint | How MLS satisfies it |
|---|---|
| **Sender-blind (alice doesn't know N or device list)** | Alice (as external sender or member) encrypts under the group's `external_pub`. She doesn't enumerate bob's devices. The group abstraction hides device count from her. |
| **No client always online** | Server stores Commit + Welcome + app-message logs persistently. Offline devices catch up by replaying logs on reconnect. |
| **E2EE preserved** | Server stores ciphertexts only. All decryption happens client-side; no key material is ever delivered to the server. |

---

## Threat model

**MLS defends against:**

- A malicious server (sees only ciphertexts + group metadata; cannot read messages).
- Member compromise (PCS within ~1 Commit cycle).
- Past compromise (forward secrecy across epochs and messages).
- Replay (each message has a unique generation; receivers reject duplicates).
- Forged group state (membership_key MACs handshakes; signatures on Commits).
- An offline member sneaking back online (they catch up via Commit log; missed Commits validate correctly).

**MLS does NOT defend against:**

- Identity spoofing (relies on out-of-band identity verification — credentials in LeafNodes).
- Compromised group authority (if the server colludes with one member to reorder Commits, that member can engineer state).
- Side-channel attacks on implementations.
- Membership privacy from the server (the server sees who joined when — encrypted contents only).

---

## Implementation status (production-ready candidates)

| Library | Language | Maturity | Notes |
|---|---|---|---|
| **openmls** | Rust | actively maintained, RFC 9420 + extensions | RustCrypto org. Most-cited reference impl. |
| **mls-rs** | Rust | actively maintained | AWS-backed. Production-oriented. |
| **MLSpp** | C++ | active | Cisco. Used in early Webex deployments. |
| **mls-ts** | TypeScript | partial | Browser-targeted. |
| **Dart MLS** | — | **no production library** | Must FFI to one of the Rust libs, or port a subset. |

For Dart-side integration today, the realistic path is **Dart FFI to `openmls` or `mls-rs`**. Both compile to C-ABI staticlibs; Dart's `dart:ffi` consumes them like any other native dependency. Adds ~1.5–3 MB to the binary.

---

## Mapping MLS onto atProtocol

For an atProtocol-native multi-device deployment using MLS:

| MLS concept | atProtocol home |
|---|---|
| Group ID | A namespace inside an atSign (e.g., the group "owner") |
| Per-device KeyPackage | `keypackage.<device-id>.mls.pqchat@<self>` — one atKey per pre-published KeyPackage, atServer-stored, deleted on consumption (or fallback to last-resort with reuse) |
| GroupInfo (published group state) | `mlsgroup.<group-id>.pqchat@<group-owner>` — the current epoch's GroupInfo blob |
| Commit log | append-only via `mlscommit.<group-id>.<epoch>.pqchat@<group-owner>` per Commit, monitored by group members |
| Welcome (per new member) | `mlswelcome.<keypackage-hash>.pqchat@<new-member>` — written by the committer, consumed once by the new member |
| Application messages | notifications via `notify:mlsmsg.<group-id>.<gen>.pqchat@<recipient-leaf-id>` (or a fan-out atKey per device) |
| External sender encryptions | Same as application messages but signed under the external sender's identity key |

**The atServer never decrypts anything.** It stores ciphertext atKeys, queues Welcomes, and orders the Commit log. Devices monitor their relevant atKeys and apply MLS operations locally.

**Async device coming online:**

1. `plookup` `mlsgroup.<group-id>.pqchat@<owner>` → current GroupInfo.
2. `plookup` all `mlscommit.<group-id>.<epoch>.pqchat@<owner>` rows for epochs between local state and current.
3. Apply each Commit locally.
4. `plookup` queued application messages, decrypt with the matching epoch's per-leaf chain.

The atServer's role is purely storage + monitor-stream delivery — exactly what it does today for regular atKeys.

---

## Comparison vs Signal Double Ratchet (1-on-1)

| Property | Signal Double Ratchet (1:1) | MLS (group, including single-user multi-device) |
|---|---|---|
| Best for | Two-party chat | Group ≥ 3, multi-device |
| Setup cost | 1 PQXDH per pair | Group bootstrap (Add + Welcome per member) |
| Per-message cost | 1 chain step + 1 AEAD | 1 chain step + 1 AEAD (same) |
| Add member cost | New pairwise PQXDH (N existing members × new device) | 1 Commit, O(log N) HPKE ops, 1 Welcome |
| Remove member cost | No protocol-level support; each remaining member must rotate | 1 Commit, O(log N), removed member cryptographically excluded |
| FS | per message | per message + per epoch |
| PCS | per DH ratchet step (~1 round-trip) | per Commit-with-UpdatePath |
| Sender knows recipient device count | yes | **no** (external sender / group abstraction) |
| Async-friendly | yes (skipped-message-key cache) | yes (Commit log + Welcome storage) |
| Spec maturity | de facto via Signal | IETF RFC 9420 |
| PQ status | PQXDH (Signal 2023) | PQ extension drafts in progress |
| Implementation effort | low (the demos in `pq/demos/` are ~700 lines) | high (FFI to a Rust MLS library) |

---

## Key takeaways

1. **TreeKEM is the engine.** Everything else is plumbing around the O(log N) tree update.
2. **Epochs are the unit of synchronization.** All members must converge to the same epoch before they can communicate; the Commit + key schedule make convergence deterministic.
3. **KeyPackages + Welcomes solve the async-onboarding problem.** A new device's KeyPackage waits on the server until someone Adds it; the resulting Welcome waits until the device polls.
4. **Sender-blindness is a free property** of the external-sender mode — alice doesn't need to know bob's group composition; she encrypts under `external_pub` and the group decrypts.
5. **PCS lives in the UpdatePath.** Any Commit without an UpdatePath skips PCS for that epoch; production deployments commit a self-Update with every state change to keep PCS firing.

---

## Further reading

- RFC 9420 — The Messaging Layer Security (MLS) Protocol (July 2023, IETF)
- IETF MLS working group archives — extension drafts, PQ profiles
- "On Ends-to-Ends Encryption: Asynchronous Group Messaging with Strong Security Guarantees" (Cohn-Gordon et al., 2018) — the academic origin of TreeKEM
- openmls source: github.com/openmls/openmls
- mls-rs source: github.com/awslabs/mls-rs
