# Crypto walkthroughs — worked end-to-end examples

Worked, end-to-end traces of the post-quantum / group-first encryption design
in action — the "how does it actually play out" companion in a three-doc set
that shares one shape (design → build → worked example):

> - **[crypto-roadmap.md](crypto-roadmap.md)** — the design source of truth
>   (goals, architecture, phasing, the *why*).
> - **[crypto_impl_plan.md](crypto_impl_plan.md)** — the build plan
>   (task breakdown, ordering, PR carving, the *how* and *when*).
> - **This doc** — worked scenarios that exercise the design.
>
> Nothing here is normative; when a walkthrough and the roadmap disagree, the
> roadmap wins. See the roadmap's
> [document map](crypto-roadmap.md#document-map) for how the sections pair up.

The three walkthroughs map onto the design's two deliverables (see
[the two deliverables](crypto-roadmap.md#the-two-major-deliverables)):

- **[Walkthrough A — NoPorts](#walkthrough-a--noports-end-to-end)** exercises
  Deliverable 1 (PQ-safe messaging) on small groups — the production payoff.
- **[Walkthrough B — a large group](#walkthrough-b--a-large-group-end-to-end)**
  exercises Deliverable 2 (pq-mls) at scale, against the atServer group
  Delivery Service.
- **[Walkthrough C — a two-atSign chat](#walkthrough-c--a-two-atsign-chat-with-client-churn-at_talk)**
  exercises the cross-atSign `(pair, namespace)` shared group with client churn.

## Walkthrough A — NoPorts, end to end

Actors: **@client** (sshnp), **@daemon** (sshnpd; a device may run many),
**@srvd** (relay; a third atSign). Each client is a leaf with a published
KeyPackage.

NoPorts is the canonical consumer: it already has the many-clients-per-atSign
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

| Feature         | Daemon advertises that it...                                                  |
|-----------------|-------------------------------------------------------------------------------|
| `groupCrypto`   | can decrypt notifications encrypted by the SDK's `group` provider             |
| `pqSessionKeys` | supports deriving session keys from a pair-group `export()` (none in flight)  |

The crucial subtlety: a client must NOT flip its default provider for traffic to
a daemon that can't decrypt it. `PutRequestOptions.cryptoProviderId`
(per-operation override, from the M0 seam) is the gate: choose the provider per
destination based on the ping response.

### One session, step by step

1. **Discovery.** sshnp pings @daemon (existing flow); the ping response
   carries `supportedFeatures`, read null-tolerantly (a missing map = old
   daemon). The client learns `groupCrypto` and `pqSessionKeys`.
2. **Session request (Tier 0 — transport).** The client picks a provider per
   the ping — `provider = features['groupCrypto'] ? 'group' : 'legacy'`, set
   via `PutRequestOptions.cryptoProviderId`. With `group`, the request
   notification is a PQ-safe group message of the @client↔@daemon pair group;
   with `legacy`, byte-identical to today. Because the (still RSA-wrapped)
   session key rides *inside* this payload, a recorded exchange can no longer
   be peeled open later — the harvest-now hole is closed even before Tier 1.

   ```dart
   final features = await pingDaemon(device);            // existing flow
   final provider = features['groupCrypto'] == true ? 'group' : 'legacy';
   await notify(req, ..., putRequestOptions: PutRequestOptions()
     ..cryptoProviderId = provider);
   ```

3. **Session keys (Tier 1 — derive, don't transmit).** If `pqSessionKeys`,
   both sides resolve the same pair group and derive
   `aesC2D = pair.export('c2d:'+sessionId)` and
   `aesD2C = pair.export('d2c:'+sessionId)`. Same `(label, epoch)` → identical
   bytes on both sides; the response carries only `sessionId`, no key material
   in flight, and the per-session RSA keypair generation is deleted. Without
   `pqSessionKeys`, fall back to today's ephemeral-RSA exchange (already
   protected by Tier 0).

   ```dart
   // sshnpd, replacing genBundle():
   final pair = await atClient.groups
       .withAtSigns([requestingAtsign], namespace: '$device.sshnp');
   final aesKeyC2D = await pair.export('c2d:$sessionId');
   final aesKeyD2C = await pair.export('d2c:$sessionId');
   // response carries only sessionId — no key material in flight

   // sshnp: the same two export() calls; both sides derive independently
   ```

   Side benefit: deletes the per-session RSA-2048 keypair generation — a
   measurable startup win on small devices.
4. **srvd relay.** The relay-auth key involves a third atSign; a per-session
   3-party group is overkill, so it stays transmitted, protected by Tier 0.
5. **Delivery.** The group is 2 atSigns (or a self group within one atSign for
   Tier 2). The member-atSign count is tiny, so there is **no DS host** —
   pairwise notify + the recipient atServer's sync to its own clients.
   (Walkthrough B's Delivery Service is only for large groups.)
6. **Fleet management (Tier 2 — self group).** Many sshnpd on one device atSign
   plus a policy/management client are a self `SecureGroup`. Management writes
   a config secret once; every daemon reads it, joined automatically at
   enrollment. A stolen device → `enroll:revoke` → the daemon's leaf is
   removed and the group rotates → everything shared after that instant is
   unreadable by it.

   ```dart
   // management client, once:
   await atClient.groups.self('policy_v2.sshnp')
       .putSecret('webhook-token', token);

   // every sshnpd, joined automatically at enrollment:
   final token = await atClient.groups.self('policy_v2.sshnp')
       .getSecret('webhook-token');

   // stolen device: enroll:revoke → leaf removed + group rotates;
   // everything shared after that moment is unreadable by it
   ```

7. **Rollout.** (1) ship dual-stack daemons that advertise the features — safe,
   nothing changes on the wire; (2) ship clients that prefer the features when
   advertised; (3) once the deployed-daemon floor includes `groupCrypto`, flip
   the client default; (4) `pqSessionKeys` retires `genBundle`/ephemeral-keypair
   code when the floor allows. Consolidation bonus at any point: NoPorts can
   replace `validation_utils` signing with the SDK's `EnvelopeSigning` (its
   descendant), moving verification onto the per-enrollment `_apsk` trust chain
   — strictly better for multi-daemon deployments.

Net: every request/response/heartbeat becomes PQ-safe (Tier 0), session keys
stop travelling at all (Tier 1), and fleet secrets get rotating-key
distribution with instant revocation (Tier 2) — with old peers always
negotiating cleanly via feature discovery. The design requirements that keep
this user-invisible (admission stays per-atSign; identity is derived from
identifiers the program already has) live in the roadmap's
[NoPorts adoption](crypto-roadmap.md#upgrading-noports-with-daemon-ping-feature-discovery).

## Walkthrough B — a large group, end to end

Actors: a dedicated DS atSign **`@my_org_groups`** running the
[group Delivery Service](crypto-roadmap.md#atserver-group-delivery-service-target-design);
admins **@alice**, **@bob**; members across many atSigns, each a leaf with a
published KeyPackage.

1. **Provision the DS.** `@my_org_groups` is operated as infrastructure (HA,
   monitored, backed up). It is ciphertext-only — never a group member, never
   holds group keys.
2. **Create.** `@alice` → `group:create{groupId, ownerAcl:[@alice,@bob]}`. The
   DS provisions the group object: roster, `seq=0`, empty TTL'd log.
3. **Add a member (@frank).** An admin: fetches + verifies @frank's published
   KeyPackage; commits an Add locally (advances the epoch), producing a Commit
   + a Welcome; sends the **Welcome pairwise** to @frank (1:1); then
   `group:append{kind:commit, value:<commit ct>, msgId}` + `group:add @frank`
   to the DS. The DS assigns `seq=N`, logs it, adds @frank to the roster, and
   fans out `{group, N}` **wakes** to every member atSign. Members
   `group:fetch:since` the commit, apply it, advance to epoch N; @frank pulls
   current state and joins.
4. **Application message (any member → group).** The sender seals once under
   the epoch key, then one `group:append{kind:app, value:<ct>, expiresAt,...}`
   to the DS. The DS assigns the next `seq`, logs (with the app TTL), fans out
   wakes. Each member atServer pulls the delta into local storage; that
   atSign's many clients then read it via ordinary sync — including the
   sender's *own* other clients (the DS fans out to the sender's atSign too).
   Cost: one append + O(member-atSigns) wakes/pulls — never O(member-clients).
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
   (`excludeEnrollmentIds`), then `group:append{kind:commit}` +
   `group:remove @grace`. The DS sequences, fans out, drops @grace from the
   roster. Everything from the new epoch on is unreadable by @grace.
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
    security — all behind the same `SecureGroup` interface and the same DS.

Net: members send/admin once to the DS; the DS sequences and fans out
ciphertext it can't read; catch-up, retention, ordering, and revocation are
handled at the group object — and the per-message cost scales with the number
of member *atSigns*, not member *clients*.

## Walkthrough C — a two-atSign chat with client churn (`at_talk`)

A worked example of the Phase 4 `(pair, namespace)` shared group: two atSigns,
multiple clients each, bidirectional messaging, and late-joining clients. It
shows exactly how decryption stays scoped to namespace-authorized clients on
both sides, and how a freshly-created client reads new *and* past messages. The
design it realises is the roadmap's
[Phase 4 — cross-atSign groups](crypto-roadmap.md#phase-4--cross-atsign-groups-shared-encryption).

**Setup.** `alice1`, `alice2`, `bob1`, `bob2` exist, each has `rw` on the
`at_talk` namespace and has published a KeyPackage (X-Wing leaf KEM key +
APKAM-certified signing key). The group is **`pair:@alice:@bob:at_talk`** —
canonical atSign ordering so both sides compute the same `groupId`; one
symmetric group, both directions sealing under the same epoch key. Members =
`{alice1, alice2, bob1, bob2}`. Epoch key `E1` is the AES-256-GCM key the group
encrypts under, minted lazily on first use.

**Why scope = `(pair, namespace)`.** The group is *not* `pair:@alice:@bob`
(would leak alice→bob `banking` to an at_talk-only bob client) and *not*
`self:@alice:at_talk` (would hand bob alice's private self data). It is the
unique group whose membership equals "both sides' `at_talk` clients", mirroring
the atServer's enrollment-authorization topology for the `at_talk` keys it
carries.

```mermaid
sequenceDiagram
    autonumber
    participant a1 as alice1
    participant a2 as alice2
    participant a3 as alice3
    participant S as atServers
    participant b1 as bob1
    participant b2 as bob2
    participant b3 as bob3

    Note over a1,b2: Step 0 — a1,a2,b1,b2 published KeyPackages, rw on at_talk. Group pair:@alice:@bob:at_talk, members {a1,a2,b1,b2}
    Note over S: atServers gate every at_talk key (data AND epoch-key envelopes) by enrollment access

    rect rgb(232,242,255)
    Note over a1: Step 1 — alice1 sends to @bob
    a1->>a1: lazily create group; mint epoch E1; seal M1 under E1
    a1->>S: put @bob:msg1.at_talk@alice {group, epoch 1, kid k1}
    a1->>S: push E1 to a2,b1,b2 — X-Wing per leaf, via __ssenv.at_talk envelopes
    end

    rect rgb(232,255,236)
    Note over b1,b2: Step 2 — bob1 and bob2 decrypt M1
    S-->>b1: @bob:msg1... + E1 envelope (allowed: at_talk)
    S-->>b2: @bob:msg1... + E1 envelope (allowed: at_talk)
    b1->>b1: decapsulate E1 with leaf key; open M1
    b2->>b2: decapsulate E1; open M1
    Note over b1,b2: a client missed at push-time pulls E1 (requestSecretsFromNamespace at_talk)
    end

    rect rgb(255,250,232)
    Note over b2: Step 3 — bob2 replies to @alice (same group, same E1)
    b2->>b2: seal M2 under E1
    b2->>S: put @alice:msg2.at_talk@bob {group, epoch 1, kid k1}
    end

    rect rgb(232,255,236)
    Note over a1,a2: Step 4 — alice1 and alice2 decrypt M2
    S-->>a1: @alice:msg2...
    S-->>a2: @alice:msg2...
    a1->>a1: open M2 with E1 (already a member)
    a2->>a2: open M2 with E1
    end

    rect rgb(255,232,244)
    Note over b3: Step 5 — bob3 created, publishes KeyPackage (at_talk)
    b3->>S: publish KeyPackage; register for at_talk
    b1->>b1: roster-watch sees b3 → Add b3 + Commit → epoch E2 (mandatory rotation)
    b1->>S: push E2 to {a1,a2,b1,b2,b3} (fans out cross-atSign)
    Note over b3: NEW: holds E2 → opens every message from epoch 2 on
    b3->>S: PAST: pull __rk.1 (request in at_talk)
    S-->>b3: E1 (allowed: b3 is at_talk-authorized)
    Note over b3: history-ON → opens M1,M2 · history-OFF (strict FS) → M1,M2 stay opaque
    end

    rect rgb(244,232,255)
    Note over a3: Step 6 — alice3 created, publishes KeyPackage (at_talk)
    a3->>S: publish KeyPackage; register for at_talk
    a1->>a1: roster-watch sees a3 → Add a3 + Commit → epoch E3
    a1->>S: push E3 to {a1,a2,a3,b1,b2,b3}
    Note over a3: NEW: holds E3 → opens every message from epoch 3 on
    a3->>S: PAST: pull __rk.1, __rk.2
    S-->>a3: E1, E2 (allowed: a3 is at_talk-authorized)
    Note over a3: history-ON → opens M1,M2 · also joins self:@alice:at_talk for alice's self data
    end
```

### How a new client obtains the epoch key

The epoch key is never sent in the clear and never wrapped under a static
per-atSign key. For each member leaf, the committer **X-Wing-encapsulates** the
epoch key to *that leaf's* published KEM public key and writes the result as a
secret-sharing envelope keyed `<msgId>.<clientId>.__ssenv.at_talk@<atsign>`.
Two independent gates therefore protect every copy of the key:

1. **Transport gate (atServer, by namespace).** The envelope key carries the
   `at_talk` suffix, so the atServer only lets a client *read* the envelope if
   its enrollment is authorized for `at_talk` — identical to the gate on the
   message itself. A client without `at_talk` can't even fetch the envelope.
2. **Crypto gate (the leaf KEM key).** The envelope body is encapsulated to one
   specific leaf's KEM public key, so only the holder of that leaf's private
   key can **decapsulate** it. Possessing a different member's envelope is
   useless.

So for **bob3** (Step 5): bob3 generates its leaf keypair locally and publishes
the *public* KeyPackage. A current member (bob1, via same-atSign roster watch)
Adds bob3 and Commits a new epoch `E2`, encapsulating `E2` to bob3's published
KEM public key and writing the `__ssenv.at_talk` envelope addressed to bob3.
bob3's atServer delivers it (bob3 is at_talk-authorized → gate 1 passes); bob3
decapsulates with its leaf KEM **private** key, which never left the device →
recovers `E2` (gate 2 passes). For past messages, bob3 issues a pull for
`__rk.1`; a member re-encapsulates `E1` to bob3's leaf and delivers it through
the same two gates. Nothing about bob3's identity is special — it succeeds iff
(a) its enrollment authorizes `at_talk` and (b) it holds its own leaf private
key. That is exactly "all bob clients with `at_talk` access, and only those."

### New clients: new vs. past messages

| Client | New messages | Past messages |
|--------|--------------|---------------|
| **bob3** | A same-atSign member Adds+Commits → mandatory rotation to `E2`, pushed to all members; bob3 decapsulates `E2` and reads from epoch 2 on. (If not proactively added, bob3 pulls `__rk.current`.) | Pulls retained `__rk.1`; server allows (at_talk-authorized). **history-ON** → opens M1, M2. **history-OFF** (strict FS) → pre-join epochs stay opaque. |
| **alice3** | Symmetric: alice1/alice2 Add+Commit → `E3`, fanned out cross-atSign to all six clients; alice3 reads from epoch 3 on. Also joins `self:@alice:at_talk` for alice's self data. | Pulls `__rk.1`, `__rk.2`; server-allowed. Same history-ON/OFF fork. |

### Caveats this example surfaces

- **History is a policy fork, not a mechanism gap.** v1 retains old epoch keys
  and lets any namespace-authorized client pull them, so chat history works —
  but that is in tension with forward secrecy. The MLS swap (D2) gives true FS,
  under which a joiner cannot read pre-join traffic by design; "new member reads
  history" then needs an explicit history-sharing mechanism (re-encrypt to the
  new member, or a separate history key). Decide the `at_talk` policy
  deliberately.
- **Every join rotates the epoch** (lever A, mandatory). Churny fleets rotate
  often; fine at pair scale, and a motivation for the Delivery Service (M5) at
  large scale.
- **M4, not yet built.** Today shared keys still route to `legacy` (the `group`
  provider refuses shared keys), so currently *all* bob clients decrypt via
  bob's shared keypair — the loose superset, not the namespace-scoped flow
  above. This walkthrough is the target the Phase 4 design specifies.
