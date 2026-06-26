# Crypto walkthroughs — worked end-to-end examples

Worked, end-to-end traces of the post-quantum encryption design in action — the
"how does it actually play out" companion in a three-doc set that shares one
shape (design → build → worked example):

> - **[crypto-roadmap.md](crypto-roadmap.md)** — the design source of truth
>   (goals, architecture, phasing, the *why*).
> - **[crypto_impl_plan.md](crypto_impl_plan.md)** — the build plan
>   (task breakdown, ordering, PR carving, the *how* and *when*).
> - **This doc** — worked scenarios that exercise the design.
>
> Nothing here is normative; when a walkthrough and the roadmap disagree, the
> roadmap wins. See the roadmap's
> [document map](crypto-roadmap.md#document-map) for how the sections pair up.

The design has two deliverables and, per
[ADR 0002](adr/0002-d1-single-tier-nskey.md), **D1 is a single tier — the
`nskey` data path**:

- **D1 — the nskey data path.** Application data is encrypted under a symmetric
  **content key (CK)** with the provider **`at/symmetric/AES/GCM`**; the CK is
  conveyed once, X-Wing-sealed to an **nskey**, by the provider **`at/nskey`**
  (a discrete `<ckKid>.__ck` record cited by `ckKid`, never inlined per value).
  Self data and cross-atSign sharing use the *identical* flow — only *which*
  nskey the CK is sealed to differs (Alice's **self nskey** for her own data;
  the recipient's published **public nskey** for a peer). The nskey *privates*
  reach each authorised APKAM keypair per-APKAM via the secret-sharing
  substrate (`__ssenv` push + `enroll:listfornamespace`, with `requestSecret`
  as the pull backstop). This is D1's default for self **and** shared data;
  see [pq-data-encryption.md](pq-data-encryption.md).
- **D2 — `at/pqmls`.** The MLS-based forward-secure **group** provider
  (`SecureGroup` v1 → pq-mls; TreeKEM; the atServer group Delivery Service).
  Groups, scale, and robust/per-message forward secrecy live here — not in D1.

## Table of contents

- [Walkthrough A — NoPorts, end to end](#walkthrough-a--noports-end-to-end)
  - [Feature discovery — the backwards-compatibility lever](#feature-discovery--the-backwards-compatibility-lever)
  - [One session, step by step](#one-session-step-by-step)
- [Walkthrough B — a large group, end to end](#walkthrough-b--a-large-group-end-to-end)
- [Walkthrough C — a two-atSign chat with APKAM-keypair churn (`at_talk`)](#walkthrough-c--a-two-atsign-chat-with-apkam-keypair-churn-at_talk)
  - [How a new APKAM keypair obtains the nskey private (and thence the CK)](#how-a-new-apkam-keypair-obtains-the-nskey-private-and-thence-the-ck)
  - [New APKAM keypairs: new vs. past data](#new-apkam-keypairs-new-vs-past-data)
  - [Caveats this example surfaces](#caveats-this-example-surfaces)

The three walkthroughs map onto the design's two deliverables (see
[the two deliverables](crypto-roadmap.md#the-two-major-deliverables)):

- **[Walkthrough A — NoPorts](#walkthrough-a--noports-end-to-end)** exercises
  Deliverable 1 (the nskey data path) for self and pair traffic and fleet
  config — the production payoff.
- **[Walkthrough B — a large group](#walkthrough-b--a-large-group-end-to-end)**
  exercises Deliverable 2 (`at/pqmls` / pq-mls) at scale, against the atServer
  group Delivery Service.
- **[Walkthrough C — a two-atSign chat](#walkthrough-c--a-two-atsign-chat-with-apkam-keypair-churn-at_talk)**
  exercises the cross-atSign nskey data path with APKAM-keypair churn.

## Walkthrough A — NoPorts, end to end

Actors: **@client** (sshnp), **@daemon** (sshnpd; a device may run many),
**@srvd** (relay; a third atSign). The identity/recipient unit is the **APKAM
keypair** (one per keyfile/install — a daemon or client may hold more than one);
each APKAM keypair has a **per-APKAM key package** registered in its enrollment
record (never published — see
[pq-secret-push.md](pq-secret-push.md) section 2). NoPorts' ephemeral one-shot
clients (npt/sshnp sessions) use throwaway per-APKAM keypairs.

NoPorts is the canonical consumer: it already has the many-keyfiles-per-atSign
problem (multiple sshnpd daemons per device atSign), already signs envelopes
(its `validation_utils` is the ancestor of the SDK's `EnvelopeSigning`), and its
main harvest-now-decrypt-later exposure is the session-key exchange (sshnpd
RSA-2048-wraps AES session keys to sshnp's per-session ephemeral keypair).

### Feature discovery — the backwards-compatibility lever

Backwards compatibility rides NoPorts' existing **feature discovery**: the
daemon's ping response carries `supportedFeatures: {name: bool}`
(`sshnpd_impl.dart`), clients read it null-tolerantly (a missing map means an
old daemon), and features gate behaviour per session — exactly how `twinKeys`
rolled out. Two new `DaemonFeature`s:

| Feature         | Daemon advertises that it...                                                   |
|-----------------|--------------------------------------------------------------------------------|
| `pqData`        | can decrypt notifications written on the D1 nskey data path (`at/nskey` + GCM) |
| `pqSessionKeys` | supports deriving session keys via the D2 `at/pqmls` group `export()` (none in flight) |

The crucial subtlety: a client must NOT flip its default provider for traffic to
a daemon that can't decrypt it. `PutRequestOptions.cryptoProviderId`
(per-operation override, from the M0 seam) is the gate: choose the provider per
destination based on the ping response.

### One session, step by step

1. **Discovery.** sshnp pings @daemon (existing flow); the ping response
   carries `supportedFeatures`, read null-tolerantly (a missing map = old
   daemon). The client learns `pqData` and `pqSessionKeys`.
2. **Session request (the nskey data path).** The client picks a provider per
   the ping. With `pqData`, the request notification is written on the **D1
   nskey data path**: the client cuts (or reuses) a content key CK, conveys it
   once via `at/nskey` sealed to @daemon's **published public nskey** for the
   session namespace, and seals the request body with `at/symmetric/AES/GCM`
   under that CK (citing `ckKid`). With `legacy`, it is byte-identical to
   today. Because the (still RSA-wrapped) session key rides *inside* this
   PQ-safe payload, a recorded exchange can no longer be peeled open later — the
   harvest-now hole is closed.

   ```dart
   final features = await pingDaemon(device);            // existing flow
   final provider = features['pqData'] == true
       ? 'at/symmetric/AES/GCM'   // D1 nskey data path; CK conveyed via at/nskey
       : 'legacy';
   await notify(req, ..., putRequestOptions: PutRequestOptions()
     ..cryptoProviderId = provider);
   ```

3. **Session keys (convey as a CK, don't transmit raw).** The session material
   is conveyed as a CK on the nskey data path: it rides inside the AES-GCM body
   above, so no key travels in the clear and the per-session RSA-2048 keypair
   generation can be deleted. If both sides advertise `pqSessionKeys`, they may
   *optionally* derive the session keys from a D2 `at/pqmls` pair-group
   `export()` instead of conveying them — a D2 optimisation, not a D1 step:

   ```dart
   // OPTIONAL D2 (at/pqmls) optimisation, gated on pqSessionKeys:
   // sshnpd, replacing genBundle():
   final pair = await atClient.groups
       .withAtSigns([requestingAtsign], namespace: '$device.sshnp');
   final aesKeyC2D = await pair.export('c2d:$sessionId');
   final aesKeyD2C = await pair.export('d2c:$sessionId');
   // response carries only sessionId — no key material in flight

   // sshnp: the same two export() calls; both sides derive independently
   ```

   Side benefit when this D2 path is used: deletes the per-session RSA-2048
   keypair generation — a measurable startup win on small devices.
4. **srvd relay.** The relay-auth key involves a third atSign; rather than seal
   a CK to a third party's public nskey per session, it stays transmitted,
   protected by the nskey data path of the request that carries it.
5. **Delivery.** Self data within one atSign, and the @client↔@daemon pair, are
   both the nskey data path — there is no group and **no DS host**. The CK
   conveyance and the data ride ordinary pairwise notify + sync; the recipient
   atServer syncs to that atSign's authorised APKAM keypairs. (Walkthrough B's
   Delivery Service is only for large D2 groups.)
6. **Fleet management (self data on the nskey data path).** Many sshnpd on one
   device atSign plus a policy/management client share a config secret as
   **self data**, encrypted under a CK conveyed via `at/nskey` to the device
   atSign's **self nskey**. Management writes the secret once; every authorised
   daemon reads it after one sync (it already holds the self-nskey private,
   delivered per-APKAM by the substrate at enrollment). A stolen device →
   `enroll:revoke` the offending enrollment, then **rotate the nskey keypair
   excluding the revoked APKAM keypair** (and rotate the CK): the successor
   conveyance is never sealed to the revoked keypair, so everything shared after
   that instant is unreadable by it.

   ```dart
   // management client, once — self data on the nskey data path:
   await atClient.put(
     AtKey()..key = 'webhook-token'..namespace = 'policy_v2.sshnp',
     token,
     putRequestOptions: PutRequestOptions()
       ..cryptoProviderId = 'at/symmetric/AES/GCM'); // CK sealed to the self nskey

   // every authorised sshnpd, after one sync (holds the self-nskey private):
   final token = await atClient.get(
     AtKey()..key = 'webhook-token'..namespace = 'policy_v2.sshnp');

   // stolen device: enroll:revoke → rotate the nskey keypair + CK, excluding
   // the revoked APKAM keypair → everything after that moment is unreadable by it
   ```

7. **Rollout.** (1) ship dual-stack daemons that advertise the features — safe,
   nothing changes on the wire; (2) ship clients that prefer the nskey data path
   when `pqData` is advertised; (3) once the deployed-daemon floor includes
   `pqData`, flip the client default to the nskey data path; (4) `pqSessionKeys`
   (the optional D2 `at/pqmls` derivation) retires `genBundle`/ephemeral-keypair
   code when the floor allows. Consolidation bonus at any point: NoPorts can
   replace `validation_utils` signing with the SDK's `EnvelopeSigning` (its
   descendant), moving verification onto the per-enrollment `_apsk` trust chain
   — strictly better for multi-daemon deployments.

Net: every request/response/heartbeat becomes PQ-safe on the nskey data path;
the session key stops travelling raw (conveyed as a CK, or derived via the
optional D2 `export()`); and fleet secrets distribute per-APKAM via the
secret-sharing substrate, with **coarse forward secrecy** by CK rotation +
deleting the old `at/nskey` conveyance and **per-APKAM future-data revocation**
by rotating the nskey keypair to exclude a revoked keypair — with old peers
always negotiating cleanly via feature discovery. The design requirements that
keep this user-invisible (admission is per-APKAM within an atSign's namespace
authorisation; identity is derived from identifiers the program already has)
live in the roadmap's
[NoPorts adoption](crypto-roadmap.md#upgrading-noports-with-daemon-ping-feature-discovery).

## Walkthrough B — a large group, end to end

This is a **D2 (`at/pqmls`)** scenario — genuine forward-secure groups, not the
D1 nskey data path.

Actors: a dedicated DS atSign **`@my_org_groups`** running the
[group Delivery Service](crypto-roadmap.md#atserver-group-delivery-service-target-design);
admins **@alice**, **@bob**; members across many atSigns. The membership unit is
the **APKAM keypair**: each authorised APKAM keypair is a leaf with a **per-APKAM
key package** registered in its enrollment record (never published; discovered
only via the gated `enroll:listfornamespace` verb).

1. **Provision the DS.** `@my_org_groups` is operated as infrastructure (HA,
   monitored, backed up). It is ciphertext-only — never a group member, never
   holds group keys.
2. **Create.** `@alice` → `group:create{groupId, ownerAcl:[@alice,@bob]}`. The
   DS provisions the group object: roster, `seq=0`, empty TTL'd log.
3. **Add a member (@frank).** An admin: fetches + verifies @frank's per-APKAM
   key package (via the gated verb, not a public lookup); commits an Add locally
   (advances the epoch), producing a Commit + a Welcome; sends the **Welcome
   pairwise** to @frank (1:1); then
   `group:append{kind:commit, value:<commit ct>, msgId}` + `group:add @frank`
   to the DS. The DS assigns `seq=N`, logs it, adds @frank to the roster, and
   fans out `{group, N}` **wakes** to every member atSign. Members
   `group:fetch:since` the commit, apply it, advance to epoch N; @frank pulls
   current state and joins.
4. **Application message (any member → group).** The sender seals once under
   the epoch key, then one `group:append{kind:app, value:<ct>, expiresAt,...}`
   to the DS. The DS assigns the next `seq`, logs (with the app TTL), fans out
   wakes. Each member atServer pulls the delta into local storage; that
   atSign's authorised APKAM keypairs then read it via ordinary sync —
   including the sender's *own* other APKAM keypairs (the DS fans out to the
   sender's atSign too). Cost: one append + O(member-atSigns) wakes/pulls —
   never O(member-APKAMs).
5. **Concurrent admins.** @alice and @bob both commit at epoch N. Both
   `group:append`; the DS's atomic `seq` orders them — one lands at N, the
   other gets a conflict, rebases to N+1, resubmits. No fork.
6. **Catch-up.** A member offline for a while returns and
   `group:fetch:since:<lastSeq>`. Commits replay in `seq` order; expired app
   messages appear as tombstones (skippable). If a commit it still needs has
   aged out (offline past the retention deadline), it is a straggler → an
   admin **re-adds it at the current epoch** (fresh Welcome), not a
   full-history replay.
7. **Remove / revoke (@grace).** An admin commits a Remove + rotates the epoch
   (`excludeEnrollmentIds` — the per-enrollment/per-APKAM revocation lever, the
   same lever the D1 nskey data path uses for keypair rotation), then
   `group:append{kind:commit}` + `group:remove @grace`. The DS sequences, fans
   out, drops @grace from the roster. Everything from the new epoch on is
   unreadable by @grace.
8. **Retention & GC.** Members periodically `group:ack{seq}`; the DS truncates
   the log below the min high-water mark (everyone has those) or a deadline.
   App messages expire per their `expiresAt`; commits are retained until
   applied-by-all or the deadline (then straggler-rejoin).
9. **Trust boundary.** The DS only ever sees ciphertext + the plaintext atSign
   roster: it orders, routes, and retains, but never decrypts and cannot forge
   membership — members reject any commit not signed by an authorised owner
   leaf, and reorder/withhold is detectable via the MLS transcript hash.
10. **Engine (v2).** The crypto is MLS: TreeKEM makes each commit O(log n)
    instead of O(n), with RFC 9420 forward secrecy and post-compromise
    security — all behind the same `SecureGroup` engine symbol and the same DS.
    The **provider id is `at/pqmls`** (the D2 provider); the Dart engine symbols
    (`SecureGroup`, `GroupCryptoProvider`) are unchanged. This is D2, not a D1
    tier.

Net: members send/admin once to the DS; the DS sequences and fans out
ciphertext it can't read; catch-up, retention, ordering, and revocation are
handled at the group object — and the per-message cost scales with the number
of member *atSigns*, not member *APKAM keypairs*.

## Walkthrough C — a two-atSign chat with APKAM-keypair churn (`at_talk`)

A worked example of the **cross-atSign nskey data path** (D1): two atSigns,
multiple APKAM keypairs each, bidirectional messaging, and late-joining APKAM
keypairs. It shows exactly how decryption stays scoped to the namespace-authorised
APKAM keypairs on both sides, and how a freshly-enrolled APKAM keypair reads new
*and* past data. The design it realises is the roadmap's
[Phase 3 — the nskey data path](crypto-roadmap.md#phase-3--the-nskey-data-path-d1-self--shared)
and [pq-data-encryption.md](pq-data-encryption.md) section 5.3 (cross-atSign put
+ read).

**Setup.** Four APKAM keypairs — `Ka1`, `Ka2` under `@alice` and `Kb1`, `Kb2`
under `@bob` — each authorised (`rw`) on the `at_talk` namespace, each with a
**per-APKAM key package** registered in its enrollment record (an X-Wing
encapsulation key + APKAM-certified signing key; **not** published). The
relevant keys are each atSign's `at_talk` **nskeys**: `@alice`'s self nskey +
published `public:nskey.at_talk@alice`, and `@bob`'s likewise. There is **no
group and no epoch key** — Alice→Bob data is encrypted under a content key
**CK** (AES-256-GCM), conveyed once via `at/nskey` sealed to **Bob's published
public nskey**; Bob→Alice symmetrically, sealed to Alice's public nskey. Alice's
own clients read her sent CKs via her **self nskey**. CKs are minted lazily on
first use.

**Which nskey the CK is sealed to.** The choice is per recipient, not a group:

- Alice writing data **Bob should read** → seal the CK to
  `public:nskey.at_talk@bob`.
- Alice writing data **only her own clients read** (self data) → seal the CK to
  Alice's **self nskey**; this is never shared cross-atSign by construction, so
  Bob never sees Alice's self data.

There is no "(pair, namespace) group" to scope: the atServer's
namespace-authorisation gate decides who may *fetch* the records, and the nskey
the CK is sealed to decides who can *decapsulate* it. Both gates are keyed to
`at_talk`, so the set is exactly "both sides' `at_talk`-authorised APKAM
keypairs."

```mermaid
sequenceDiagram
    autonumber
    participant a1 as Ka1 (@alice)
    participant a2 as Ka2 (@alice)
    participant a3 as Ka3 (@alice)
    participant S as atServers
    participant b1 as Kb1 (@bob)
    participant b2 as Kb2 (@bob)
    participant b3 as Kb3 (@bob)

    Note over a1,b2: Step 0 — Ka1,Ka2,Kb1,Kb2 hold per-APKAM key packages, rw on at_talk. No group; @alice and @bob each have at_talk nskeys
    Note over S: atServers gate every at_talk key (data AND __ck conveyance records) by enrollment access

    rect rgb(232,242,255)
    Note over a1: Step 1 — Ka1 sends to @bob
    a1->>a1: cut CK; seal CK ONCE via at/nskey to public:nskey.at_talk@bob; AES-GCM-seal M1 under CK
    a1->>S: put @bob:ckB1.__ck.at_talk@alice (sealed to bob public nskey) + @bob:msg1.at_talk@alice {ckKid}
    Note over a1,S: nskey PRIVATES already on each APKAM keypair via the substrate (per-APKAM); NOT pushed per message
    end

    rect rgb(232,255,236)
    Note over b1,b2: Step 2 — Kb1 and Kb2 decrypt M1
    S-->>b1: ckB1.__ck + msg1 (allowed: at_talk)
    S-->>b2: ckB1.__ck + msg1 (allowed: at_talk)
    b1->>b1: decapsulate CK with public-nskey private; cache by ckKid; AES-GCM-open M1
    b2->>b2: decapsulate CK; open M1
    Note over b1,b2: an APKAM keypair missing the nskey private pulls it (requestSecret in at_talk) — the PRIVATE, not the CK
    end

    rect rgb(255,250,232)
    Note over b2: Step 3 — Kb2 replies to @alice (same CK epoch, sealed to alice's public nskey)
    b2->>b2: AES-GCM-seal M2 under a CK conveyed to public:nskey.at_talk@alice
    b2->>S: put @alice:msg2.at_talk@bob {ckKid} (+ __ck if not already conveyed)
    end

    rect rgb(232,255,236)
    Note over a1,a2: Step 4 — Ka1 and Ka2 decrypt M2
    S-->>a1: @alice:msg2... (+ __ck)
    S-->>a2: @alice:msg2...
    a1->>a1: decapsulate CK with alice's public-nskey private; open M2
    a2->>a2: open M2 (CK already cached)
    end

    rect rgb(255,232,244)
    Note over b3: Step 5 — Kb3 enrolled, registers its key package (at_talk)
    b3->>S: register per-APKAM key package; gain rw on at_talk
    Note over b1: a holder (Kb1) pushes the at_talk nskey PRIVATES to Kb3 per-APKAM
    b1->>S: __ssenv.at_talk envelope to kp(Kb3) — conveys nskey privates (substrate, Layer 1)
    Note over b3: holds nskey privates → reads CURRENT __ck conveyances → opens new data. NO epoch rotation on join
    b3->>S: PAST: pull nskey privates if it missed the push (requestSecret) — never a per-message key
    S-->>b3: nskey privates (allowed: Kb3 is at_talk-authorised)
    Note over b3: retain __ck records → opens M1,M2 · delete-for-FS → pre-rotation data stays opaque
    end

    rect rgb(244,232,255)
    Note over a3: Step 6 — Ka3 enrolled, registers its key package (at_talk)
    a3->>S: register per-APKAM key package; gain rw on at_talk
    Note over a1: a holder (Ka1) pushes the at_talk nskey PRIVATES (self + public) to Ka3 per-APKAM
    a1->>S: __ssenv.at_talk envelope to kp(Ka3) — conveys nskey privates incl. the SELF nskey private
    Note over a3: holds nskey privates → reads current __ck conveyances → opens new data
    a3->>S: PAST: pull nskey privates if missed (requestSecret)
    S-->>a3: nskey privates (allowed: Ka3 is at_talk-authorised)
    Note over a3: SELF nskey private also lets Ka3 decapsulate alice's OWN self CKs — no self group to join
    end
```

### How a new APKAM keypair obtains the nskey private (and thence the CK)

The CK is never sent in the clear, and the **nskey private** that unwraps it is
never published. Two independent steps get a new APKAM keypair reading:

1. **Layer 1 — the nskey private, per-APKAM (substrate).** A holder seals the
   namespace's nskey **privates** to the new APKAM keypair's key package with
   `pqSeal` and writes a substrate envelope keyed
   `<msgId>.<kpid>.__ssenv.at_talk@<atsign>` — addressed by **key-package id
   (`kpid`)**, per-APKAM, **not** by a per-process client id. This happens once
   per APKAM keypair (approval-time push / `enroll:listfornamespace` /
   `requestSecret` pull backstop). Two gates protect every copy:

   - **Transport gate (atServer, by namespace).** The envelope carries the
     `at_talk` suffix, so the atServer only lets an enrollment *read* it if it
     is authorised for `at_talk` — identical to the gate on the data itself.
   - **Crypto gate (the key package private).** The envelope body is `pqSeal`ed
     to one specific APKAM keypair's key package, so only the holder of that
     keyfile's key-package private half can open it.

2. **Layer 2 — the CK, on ordinary sync.** Once an APKAM keypair holds the nskey
   private, it reads CKs with no further per-APKAM step: on syncing a
   `<ckKid>.__ck.at_talk@<owner>` conveyance record, the `at/nskey` provider
   **decapsulates** the CK with the matching nskey private and caches it by
   `kid`; the `at/symmetric/AES/GCM` provider then resolves data values by
   `ckKid` and AES-GCM-decrypts.

So for **Kb3** (Step 5): Kb3 generates its key package locally and registers the
*public* half in its enrollment record (gated, never published). A holder (Kb1)
pushes the `at_talk` nskey privates to Kb3's key package via the substrate;
Kb3's atServer delivers it (Kb3 is at_talk-authorised → gate 1 passes); Kb3
opens it with its key-package private half, which never left the device → holds
the nskey privates (gate 2 passes). Now Kb3 syncs the current `__ck` conveyances,
decapsulates the live CK with the public-nskey private, and reads new data — **no
epoch rotation on join, no per-message key push, no Add+Commit**. For history,
Kb3 reads whatever `__ck` conveyances are still retained (see
[New APKAM keypairs: new vs. past data](#new-apkam-keypairs-new-vs-past-data)).
Nothing about Kb3 is special — it succeeds iff (a) its enrollment authorises
`at_talk` and (b) it holds its own key-package private. That is exactly "all
@bob APKAM keypairs with `at_talk` access, and only those."

### New APKAM keypairs: new vs. past data

| APKAM keypair | New data | Past data |
|---|---|---|
| **Kb3** (@bob) | Receives the `at_talk` nskey private per-APKAM via the substrate (push, or `requestSecret` pull), then syncs the current `__ck` conveyances and decapsulates the live CK → reads all new data. **No epoch rotation, no `__ck` re-mint required on join.** | Reads whatever `__ck` conveyances are still **retained** (server allows — Kb3 is at_talk-authorised). **Retain** → opens M1, M2. **Delete-for-FS** → CKs whose conveyance was deleted on rotation stay opaque. |
| **Ka3** (@alice) | Symmetric: receives @alice's `at_talk` nskey privates (self **and** public) per-APKAM; reads current `__ck` conveyances → reads all new data. The **self** nskey private also lets it decapsulate @alice's own self CKs. | Reads retained `__ck` conveyances; server-allowed. Same retain-vs-delete fork. |

### Caveats this example surfaces

- **History is a policy fork, not a mechanism gap.** The D1 artefact is the
  `at/nskey` CK-conveyance record (the `<ckKid>.__ck` record), not a per-group
  epoch key. **Retain** the `__ck` records and any at_talk-authorised APKAM
  keypair can read history; **delete** them on CK rotation (and evict the cached
  CK) and that era's data becomes undecryptable — D1's **coarse forward secrecy**
  (see [pq-data-encryption.md](pq-data-encryption.md) section 6). D1 therefore
  *does* have forward secrecy: coarse FS by CK rotation + conveyance deletion,
  plus post-compromise security via the (expensive, O(n) per-APKAM) nskey-keypair
  rotation lever. D2 (`at/pqmls`) adds *robust/per-message* FS, scale, and
  membership decoupled from namespace authorisation — it is not the only source
  of FS. Decide the `at_talk` retention policy deliberately.
- **A new APKAM keypair does NOT force a rotation.** Joining `at_talk` just
  conveys the nskey private to the new keypair (per-APKAM) and lets it read the
  existing CKs — no mandatory epoch rotation. (Mandatory rotation on join is a
  D2 / `at/pqmls` MLS property — see Walkthrough B — not a D1 behaviour.)
- **Cross-atSign FS is bilateral.** Alice forward-secures her *outbound* data
  unilaterally (she owns the CK conveyance + cache). For *inbound*, Bob owns the
  authoritative `@alice:<ckKid>.__ck.at_talk@bob` replica's source; Alice can
  purge her cache but closing inbound FS depends on Bob's rotation (or the
  heavier public-nskey *keypair* rotation). Normal for any FS system.
- **Target, partly built.** The D1 cross-atSign target is the nskey data path
  above (CK conveyed via `at/nskey` to the recipient's public nskey; data under
  `at/symmetric/AES/GCM`). Until the nskey-data-path milestone lands, shared
  data still routes to `legacy`, so currently *all* @bob APKAM keypairs decrypt
  via @bob's legacy shared keypair — the loose superset, not the
  namespace-scoped flow above. This walkthrough is the target the
  [Phase 3 design](crypto-roadmap.md#phase-3--the-nskey-data-path-d1-self--shared)
  specifies.
