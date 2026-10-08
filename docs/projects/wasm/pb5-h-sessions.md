# pb5-h-sessions.md — sessions: acquire keys, heal the server copy

**Status:** on branch `st/wasm/pb5-sessions`, 2026-10-08. No PR yet. It sits on layer C (#2271) and the rebased PB-3 stage 6d (#2276), on the `gkc-v4-ga` line (#2415).

**Bottom line:**
- `at_client_wasm` starts a client in one call, in one of two modes:
  - `ephemeralSession` (Mode E): keys handed in, nothing written anywhere.
  - `portalSession` (Mode P): keys from an envelope unlocked by the passkey PRF. A first visit imports the `.atKeys` and seals it under a newly registered passkey.
- Reading keys and repairing the server copy are two functions, and the type system keeps them apart:
  - `acquireKeys` only reads the server copy.
  - `heal` is the only writer.
- Heal goes over the client's own authenticated connection. No second socket is opened for it.
- **One open contract question for the portal (R-5):** what a device must do after the keys are resealed under a new content key.

**Related docs:**
- The golden envelope contract: [`packages/at_client_wasm/test/fixtures/README.md`](../../../packages/at_client_wasm/test/fixtures/README.md).
- The remote-only storage this runs on: [`pb3-stage6.md`](pb3-stage6.md).
- The portal-cuts-keys ruling: [`decisions.md`](decisions.md).

---

## 1. Two modes

| | Mode E — `ephemeralSession` | Mode P — `portalSession` |
|---|---|---|
| Keys come from | the caller (`AtKeys`) | the device copy or the envelope at `_atkeys.<app>@<atSign>`, else an `.atKeys` import |
| Unlock | none | passkey PRF only |
| Device writes | none | the device copy (`KeyBytesStore`) and the passkey credential hint |
| Server writes | none | `heal` only, and only on `healed` |
| Storage | `RemoteOnlyAtClientStorage` | `RemoteOnlyAtClientStorage` |

## 2. Acquire, then heal

```mermaid
sequenceDiagram
  participant App
  participant S as portalSession
  participant A as acquireKeys
  participant D as device copy (KeyBytesStore)
  participant R as server copy
  participant C as AtClient + RemoteSecondary
  App->>S: portalSession(atSign, app, ...)
  S->>A: acquireKeys(server: ServerCopyReader)
  A->>D: get(atSign)
  alt no device copy
    A->>R: fetch — unauthenticated lookup, own socket, closed after
  end
  alt a copy opens with the passkey PRF
    A->>D: put(envelope)
  else no copy opens
    A->>A: importAtKeys, register a passkey, seal under its PRF
    A->>D: put(new envelope)
  end
  A-->>S: AcquiredKeys(keysIo, prf?)
  S->>C: remoteOnlyClient(keysIo) → (client, remote)
  opt keys are passkey-held (prf != null)
    S->>R: heal(server: RemoteServerCopy(reader, remote))
    Note over S,R: put = update:public: on the client's RemoteSecondary
  end
  S-->>App: AtClient
```

- **Type-enforced split.**
  - `acquireKeys` takes a `ServerCopyReader`, which has `fetch` only.
  - `heal` takes a `ServerCopy`, which adds `put`.
  - Acquisition writing the server copy is therefore a compile error, not a review finding.
- **Why heal runs after the client exists.**
  - Writing the server copy needs an authenticated connection.
  - The client already holds one. `RemoteServerCopy` writes on it and never closes it.
- **A failed heal is logged, and the client keeps running.** Heal is repair, not a precondition for the session.

## 3. Heal outcomes

| `HealOutcome` | Found | Writes |
|---|---|---|
| `healed` | The server copy has no unlock for this passkey | `put` of the device copy merged with the server copy's unlocks |
| `alreadyPresent` | The server copy already opens with the passkey | nothing |
| `contentKeyMismatch` | The device and server copies seal different content keys, so the keys were resealed | nothing |
| `missingCopy` | The device or the server copy is absent | nothing |

## 4. ServerCopy adapters

| Adapter | Role | Connection |
|---|---|---|
| `LookupServerCopyReader` | `fetch` | A fresh `lookUps(authenticator: null)` connection. It sends `lookup:_atkeys.<app>@<atSign>` and is closed in `finally` |
| `RemoteServerCopy` | `fetch` through the reader, `put` | `put` is `updateCommand` on the client's `RemoteSecondary` with `auth: true`, which it leaves open |

- `fetch` reads AT0015 (key not found) and `data:null` as `null`. Every other error propagates.
- **Rejected alternative:** a second authenticated connection just for `put`.
  - It would PKAM twice per session.
  - It would leave a socket authenticated as the enrollment, which is the second-socket leak that stage 6 removed.

## 5. Open — R-5: reseal contract

- A **reseal** issues a new content key and seals a new envelope. Its triggers include:
  - re-enrollment;
  - a fresh `.atKeys` import on a device whose passkey opens no copy.
- Every existing device copy and every `prf` unlock is then stale:
  - `heal` reports `contentKeyMismatch` and writes nothing.
  - A passkey synced to a new device falls back to importing the `.atKeys` again.
- **Open questions:**
  - When may a reseal replace the server copy?
  - Must a device drop its copy and re-acquire from the server?
- Detecting a reseal proactively, by comparing a hash of the server copy's `content.ct`, is deferred to PB-8 / V2.

## 6. Findings

- **Golden read in the browser.**
  - The golden test now reads `test/fixtures/envelope_v1_golden.dart`.
  - `test/fixtures_test.dart` (VM) pins that constant to the JSON contract file byte for byte.
- **The at_client follow-up ([#2336](https://github.com/atsign-foundation/at_client_sdk/pull/2336), in at_client 4.0.0 on this branch):**
  - A `RemoteOnlyAtClientStorage` client runs no expiry or availability timers.
  - Rederiving after an enrollment change moves `RemoteOnlyAtClientStorage` onto the new `RemoteSecondary`.
  - `remoteOnlyClient` leaves `isLocalStoreRequired` at its default.
- **First-visit import needs a browser `.atKeys` decoder.**
  - `acquireKeys` takes `importAtKeys`; decoding an `.atKeys` file without `dart:io` or at_chops is not available yet.
