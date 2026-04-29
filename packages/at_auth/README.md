# at_auth

Platform-neutral core of **onboarding**, **authentication**, and **APKAM
enrollment** for the Atsign Protocol. Used by both
[`at_onboarding_cli`](../at_onboarding_cli) (CLI / server apps) and
[`at_client_flutter`](../at_client_flutter) (Flutter apps) — most
application developers will pick up one of those higher-level packages
rather than consuming `at_auth` directly.

## What `at_auth` does

| Capability                      | Entry point                                            |
| ------------------------------- | ------------------------------------------------------ |
| CRAM-based initial onboarding   | `AtAuth.onboard(AtOnboardingRequest, cramSecret)`      |
| PKAM authentication             | `AtAuth.authenticate(AtAuthRequest)`                   |
| APKAM enrollment (request side) | `AtEnrollment.submit(...)`                             |
| APKAM enrollment (approve side) | `AtEnrollment.approve(...)` / `AtEnrollment.deny(...)` |
| Free atSign registration        | `RegistrarService` (fetches CRAM key by email)         |

See [`example/onboard.dart`](example/onboard.dart),
[`example/authenticate.dart`](example/authenticate.dart), and
[`example/enrollment_request.dart`](example/enrollment_request.dart) for
end-to-end usage.

## The atSign lifecycle

The full journey from "I don't own an atSign yet" to "my app is talking
to the atServer" breaks into three phases. Understanding all three is
important because each produces credentials that need to be handled
correctly.

### Phase 1 — Provision an atSign (get a CRAM key)

An atSign is a namespaced identity (e.g. `@alice`) with a matching
personal server (the **atServer**). Before any cryptographic keys exist,
you need to claim the atSign itself.

- Free atSigns: [my.noports.com/no-ports-plans](https://my.noports.com/no-ports-plans)
- Paid / custom atSigns: [my.atsign.com](https://my.atsign.com)

Registration produces a **CRAM key** — a high-entropy secret, delivered
to the registered email address, that proves first-time ownership.
Programmatic registration is available via `RegistrarService` (see
[`lib/src/registrar/`](lib/src/registrar)).

At this point the atSign exists on the root directory but its atServer
has no authenticated user and no encryption keys. The CRAM key is the
one-time bootstrap credential.

### Phase 2 — Onboard the atSign (generate the master AtKeys)

Onboarding happens **exactly once per atSign** and consists of:

1. Authenticating to the atServer with the CRAM key.
2. Generating the atSign's cryptographic keypairs (PKAM signing,
   encryption, self-encryption).
3. Publishing the public halves and registering the PKAM public key on
   the atServer.
4. Writing the private halves to a local `.atKeys` file (for CLI apps)
   or to the device **keychain** (for Flutter apps).

The result is a **master AtKeys** set. These keys:

- Are the **root of trust** for the atSign — losing them is
  approximately as bad as forgetting the password to a cryptocurrency
  wallet; there is no recovery path that doesn't involve reclaiming the
  atSign from scratch.
- **MUST be backed up by the end user.** Any app that uses `at_auth` to
  onboard an atSign should tell the user to back up the `.atKeys`
  file / keychain entry. `at_client_flutter` surfaces an "export keys"
  flow; CLI apps typically just write the file and leave it to the user.
- Are the only keys allowed to **approve or deny APKAM enrollment
  requests** — see Phase 3.

After Phase 2, the CRAM key is no longer usable (onboarding is
single-shot). Use [`example/onboard.dart`](example/onboard.dart) to walk
through it end-to-end.

### Phase 3 — Authenticate apps via APKAM (per-app scoped AtKeys)

The master AtKeys are powerful — they can read anything on the atServer
and approve new devices. You don't want every app on every device
holding them. APKAM (App-level Pkam Key Authentication Mechanism)
solves this.

How APKAM works:

1. A new app / device submits an **enrollment request** specifying the
   namespaces it needs and the access level it needs on each
   (e.g. `{'todos': 'rw', 'profile': 'r'}`). Each request gets a
   short-lived **OTP** to bind the request to a human-approved session.
2. An already-authenticated session holding the master AtKeys (or any
   session whose keys include the `__manage` namespace) **approves or
   denies** the request.
3. On approval, the atServer issues a **new, scoped AtKeys set** — it
   can only read/write within the granted namespaces.
4. The enrolling app stores those scoped keys (disk or keychain) and
   uses them for normal PKAM authentication thereafter.

Why this matters:

- **Scope limits blast radius.** An "evil" or simply buggy app with
  scoped keys can only damage data in its own namespace. A todos app
  with `{'todos': 'rw'}` can never read your `charts.acme` data even if
  it's fully compromised.
- **Scoped keys are revocable.** The master-keys holder can revoke any
  previously-approved enrollment; the atServer rejects future
  authentications from those keys immediately.
- **Audit trail.** Every active enrollment is listed with its `appName`,
  `deviceName`, namespace permissions, and status (`pending`,
  `approved`, `denied`, `revoked`, `expired`).

See [`example/enrollment_request.dart`](example/enrollment_request.dart)
for the submitting side; the approve/deny side is demonstrated in
[`at_onboarding_cli/example/apkam_examples/enroll_app_listen.dart`](../at_onboarding_cli/example/apkam_examples/enroll_app_listen.dart).

## Where to go next

| If you're building…            | Use                                                                                   |
| ------------------------------ | ------------------------------------------------------------------------------------- |
| A CLI or server app            | [`at_onboarding_cli`](../at_onboarding_cli) + [`at_cli_commons`](../at_cli_commons)   |
| A Flutter app                  | [`at_client_flutter`](../at_client_flutter) — includes pre-built onboarding widgets   |
| Anything that reads/writes data after auth | [`at_client`](../at_client)                                               |

## Open source usage and contributions

BSD3-licensed. See [`CONTRIBUTING.md`](../../CONTRIBUTING.md) for
guidance on setting up tools, running tests, and raising a PR.
