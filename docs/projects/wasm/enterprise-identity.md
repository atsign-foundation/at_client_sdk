# enterprise-identity.md — atSigns behind a customer's identity provider

**Status:** design doc (proposed). Lives in `docs/projects/wasm/`.
**Purpose:** what it takes for an enterprise customer to manage atSigns from **their own**
identity provider (Microsoft Entra, Okta) — the lifecycle mapping, what already exists,
what is missing, and which constraints the browser lane must not violate while the answer
is outstanding.
**Why it is here:** this is an **adoption** blocker, not a program blocker. Nothing below
prevents the WASM work from shipping; all of it prevents an enterprise from adopting it.

---

## 0. The requirement in one line

> An enterprise wants their directory to be the system of record: a SCIM *create user*
> event provisions an atSign, a *disable* or *delete user* event deprovisions it, with no
> human in the loop — and they want the credentials stored where they already store
> secrets.

---

## 1. Lifecycle mapping

The protocol is closer to ready than any earlier doc suggested. Mapping IdP events onto
what `at_auth` and the atServer actually expose:

| IdP event | atProtocol primitive | State |
| --- | --- | --- |
| SCIM **create user** | registrar → CRAM key → `AtAuth.onboard` → first enrollment (auto-approved, server grants `__manage`) | ⛔ **the activation OTP goes to a human mailbox** — §3 |
| **New device / app** for an existing user | `AtEnrollment.submit(EnrollmentRequest, otp)` → `approve` | ✅ fully machine-drivable — the enrollment OTP is minted **programmatically** (`otp:get`), and `setSpp` gives a semi-permanent passcode |
| **Webhook-driven bulk approval** | an `autoApprove` daemon subscribing `.*\.new\.enrollments\.__manage`, regex-matching app/device | ⚠️ **already written**, but reachable only through `auth_cli.dart` — not exported from the barrel |
| SCIM **disable user** | per-enrollment `AtEnrollment.revoke(enrollmentId)` | ⚠️ per-enrollment only; **no atSign-level primitive** — §2 |
| SCIM **re-enable user** | `unrevoke` | ⚠️ exists on the wire and in the server handler; **no library API** |
| **Reconcile** directory ↔ atSigns | `AtEnrollment.list(statusFilters)` | ✅ |
| **Policy** — who may hold an atSign in this tenant | `packages/at_policy` | ✅ right home, unused for this |

**Two structural facts make this tractable:**

1. **The enrollment lifecycle is storage-free.** Every `AtEnrollment` method takes only an
   `AtLookUp` — no `AtClient`, no keystore (`at_enrollment.dart:73,107,126,145,152,159,166,189`).
   It works in a browser under D-12 with no local store.
2. **The handoff already exists.** An approved enrollment yields an `AtAuthSession`, and
   `AtClientManager.fromAuthSession` (`at_client_manager.dart:193-211`) already consumes it.

---

## 2. What the atServer is missing: an atSign-level disable

Per-enrollment `revoke` exists. There is **no primitive that disables the identity's own
access**. Composing one as `list(approved) → revoke each` is **racy** (a new enrollment can
land between the calls) and **non-atomic** (a partial failure leaves the identity
half-disabled).

**There is an adjacent atSign-level control, and it points the wrong way.**

| | `config:block` | what is needed |
| --- | --- | --- |
| Grammar | `config:block:add:@alice @bob` / `:remove:` / `:show` | — |
| Enforced at | `from` verb — `checkInBlockList(fromAtSign)` → `BlockedConnectionException` | the owner's own authentication |
| Direction | **inbound** — stops *other* atSigns reaching my atServer | **the identity itself** must stop working |
| Self-disable | **explicitly foreclosed in code** — the handler strips `currentAtSign` from the list | required |

That last row matters: self-blocking is excluded **deliberately**, which is what makes this
a genuine gap rather than a search that missed something.

**The ask.** One operation that suspends an atSign as a unit — reject new enrollment
requests, suspend all approved enrollments atomically, close live connections — with a
reversible counterpart mirroring `revoke`/`unrevoke`. It needs a **status distinct from
`EnrollmentStatus.revoked`**, so per-enrollment state survives and re-enable does not
wrongly restore individually-revoked enrollments.

This is atServer work, owned in-house, tracked in the atServer plan.

---

## 3. What the registrar is missing: unattended provisioning

**This is the only genuinely external dependency in the whole programme.**

Important scoping correction: the registrar **is** browser-reachable over HTTPS today, and
a web app can complete an interactive activation — OTP to email, exchanged for a CRAM key.
**That path works and is not in question.**

What does not exist, on the surface our own client consumes:

| # | Ask | Priority |
| --- | --- | --- |
| R-1 | A machine-to-machine credential, so a backend can create an atSign with no human reading an OTP email. Today the credential is a single shared `Authorization` header value with no per-tenant scoping | **blocker** |
| R-2 | A deprovisioning endpoint, with agreed reversibility semantics against §2's suspend/restore | **blocker** |
| R-3 | A tenant reconciliation / list endpoint, so an integration can detect and heal drift | wanted |

**Raise these now**, in parallel with the browser work — lead time is the risk, not
difficulty. The full hand-off document is maintained separately and states each item as
"here is the surface we consume; confirm or correct it," because our evidence is our own
client wrapper rather than the registrar's API documentation.

---

## 4. Two defects on the onboarding path, unrelated to WASM

Both pre-date this programme. Both will surface in the first enterprise security review, so
they are recorded here rather than buried under a WASM ticket.

| Defect | Why it matters here |
| --- | --- |
| The default registrar client installs a `badCertificateCallback` accepting **any** certificate — on the channel carrying the activation OTP and returning the CRAM key | A browser **cannot** do this, so the web client already verifies properly. The port fixes it as a side effect; that is an argument for the port, not an excuse for the line |
| Onboarding writes `atAuthKeys` JSON — **private key material** — into `Directory.current.path` as a checkpoint file | A server-side webhook handler would leave private keys in its working directory. Fatal in exactly the deployment this document describes |

---

## 5. Constraints the browser lane must not violate

These are *don't-close-this-door* rules. None requires the IdP integration to be built now.

| # | Constraint | Why |
| --- | --- | --- |
| **E1** | **Onboard the web app as an APKAM enrollment, never as a new atSign.** | Enrollment is machine-drivable today; atSign creation is not (§3). It also makes browser-storage eviction **non-fatal** — the atSign's keys still live on the user's other device, so losing the browser key store means *re-enroll*, not lockout |
| **E2** | Build the sealed key envelope as a **reusable, pure-Dart component**, not welded inside the IndexedDB implementation | An IdP directory attribute (Entra schema extensions, Okta Universal Directory) is a plausible host-supplied key store. If sealing is reusable, that store inherits it. If not, writing plaintext atKeys into a directory attribute would be a serious regression — note that a host-supplied store receives **plaintext** across the port, and owns its own at-rest protection |
| **E3** | **Redirect-based OIDC only** (D-16) | Popups work today but break the moment any V2 storage option requires COOP `same-origin` |
| **E4** | **No new process-global state**; one client per atSign, explicitly (D-18) | An IdP integration is inherently multi-identity: one service holding many users' atSigns. Under D-12 this can be *demonstrated* now, not merely promised |
| **E5** | Export the enrollment lifecycle that already exists — `unrevoke`, `delete`, single `fetch`, and the `autoApprove` daemon | Cheap, non-breaking, additive. These are **library-API gaps, not server gaps**: all of them exist on the wire and in the atServer's enroll handler. The webhook-driven approval daemon is already written |
| **E6** | Make HTTP-client injection mandatory on the onboarding path | Needed for the browser anyway; it is also what lets §4's two defects be fixed independently |

---

## 6. What this document does **not** claim

- It does not assume a flow shape. Whether the customer's OIDC leg is redirect or popup,
  and whether provisioning is SCIM or webhook, is **assumed, not verified** — the reference
  specification was not readable. E3 is deliberately written as the conservative branch,
  which is correct under either shape, so learning more can only *relax* a constraint.
- It does not schedule the IdP integration. It records what would foreclose it.
