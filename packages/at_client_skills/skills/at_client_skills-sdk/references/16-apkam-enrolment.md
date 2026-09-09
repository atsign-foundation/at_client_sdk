# Programmatic APKAM Enrolment (headless)

APKAM enrolment is how a *second* app or device gets its own `.atKeys` for an
atsign that is already activated, scoped to only the namespaces it asks for.
[05-flutter-auth.md](05-flutter-auth.md) covers it for Flutter, where
`ApkamActivationDialog` drives the flow. A **headless** client — a CLI, a
daemon, an agent on a box with no screen — has no dialog to show, and needs
this instead.

Enrolment always has **two sides**, and they are different APIs in different
packages:

| Side                                 | What it does                | API                              |
| ------------------------------------ | --------------------------- | -------------------------------- |
| **Requesting** (the new device)      | asks to be enrolled         | `AtOnboardingService.enroll(…)`  |
| **Approving** (an existing app)      | grants or refuses           | `atClient.enrollmentService`     |

Nothing enrols itself. A request sits at `pending` until something holding the
`__manage` namespace approves it, so a headless device is only half the
problem — plan for who approves, and how they get the passcode.

**Dependency:** the requesting side lives in `at_onboarding_cli`, which is a
**separate pub.dev dependency**; `at_client` does not re-export it.

```sh
dart pub add at_onboarding_cli
```

---

## Requesting side — `AtOnboardingService.enroll()`

```dart
import 'package:at_onboarding_cli/at_onboarding_cli.dart';

final service = AtOnboardingServiceImpl('@alice', preference);

final response = await service.enroll(
  'my_agent',                       // appName
  'gateway-01',                     // deviceName — must identify this device
  otp,                              // passcode from an already-enrolled app
  {'my_app': 'rw', 'contacts': 'r'} // namespace → access
);

print(response.enrollmentId);
```

`namespaces` is where the scope is decided: `rw` lets the app create and update
in that namespace, `r` lets it only read. Ask for the least it needs — this is
the whole point of enrolling rather than copying the root `.atKeys` around.

### The default timeout will not survive a human

For any enrolment a **person** approves, set `retryInterval` and `maxRetries`
explicitly rather than inheriting
`AtOnboardingService.defaultApkamRetryInterval` and `defaultMaxApkamRetries`.
Those defaults are sized for a machine-to-machine handshake, and `enroll()`
throws the moment the budget runs out — nobody picks up another device, finds
the approval screen and taps approve inside that window. Choose the window
from how long your approver realistically needs:

```dart
final response = await service.enroll(
  'my_agent', 'gateway-01', otp, {'my_app': 'rw'},
  retryInterval: const Duration(seconds: 10),
  maxRetries: 60,                    // ~10 minutes
  atKeysFile: File('/etc/my_agent/@alice_key.atKeys'),
);
```

### It resumes, so a crash does not double-enrol

`enroll()` is `sendEnrollRequest()` → `awaitApproval()` → `createAtKeysFile()`,
and it keeps a local checkpoint. On a re-run with a valid checkpoint it
**skips the request** and goes straight back to waiting, so restarting a
timed-out enrolment does not leave a second `pending` request behind for
somebody to approve by mistake. Call the three separately when you want to own
the waiting — for example to report progress, or to race the wait against
your own deadline:

```dart
final response = await service.sendEnrollRequest(
    'my_agent', 'gateway-01', otp, {'my_app': 'rw'});

// Do your own waiting / UI / logging here.
await service.awaitApproval(
    response,
    retryInterval: const Duration(seconds: 10),
    maxRetries: 60,               // both explicit — the window is 10 minutes
);
await service.createAtKeysFile(response, allowOverwrite: false);
```

`createAtKeysFile` defaults to `allowOverwrite: false`, so it refuses to
clobber an existing keys file. Storage paths (`commitLogPath`,
`hiveStoragePath`, `atKeysFilePath`) default per-atsign and are keyed by
`enrollmentId` when one is passed to `AtOnboardingServiceImpl`, which is what
keeps two enrolments on the same host from sharing local storage.

---

## Getting the passcode

The requesting device cannot mint its own `otp` — that would defeat the
mechanism. It comes from an **already-enrolled** app, over whatever
out-of-band channel you have:

```dart
final atEnrollment = AtEnrollment.create();

// One-time passcode. Pass `expiry` to match how long your out-of-band
// hand-off to the device actually takes; the default is short.
final otp = await atEnrollment.generateOtp(atLookUp);

// Or a semi-permanent passcode for provisioning many devices.
// Must be alphanumeric and exactly 6 characters.
final spp = await atEnrollment.setSpp('AB12CD', atLookUp);
```

Prefer `generateOtp` for one device. Reach for `setSpp` when provisioning a
fleet, and treat it as a shared secret with a real blast radius — anything
holding it can request enrolment until it expires.

---

## Approving side — `atClient.enrollmentService`

```dart
// NOTE: the getter is nullable.
final enrollments = atClient.enrollmentService;
if (enrollments == null) {
  throw StateError('enrollmentService unavailable on this client');
}

final pending = await enrollments.fetchEnrollmentRequests();

await enrollments.approve(EnrollmentRequestDecision.approved(
  ApprovedRequestDecisionBuilder(
    enrollmentId: request.enrollmentId,
    encryptedAPKAMSymmetricKey: request.encryptedAPKAMSymmetricKey,
  ),
));

await enrollments.deny(EnrollmentRequestDecision.denied(enrollmentId));
await enrollments.revoke(EnrollmentRequestDecision.revoked(enrollmentId));
```

Three things to get right:

**1. The getter is `EnrollmentService?`** — nullable on `AtClientSpec`. Check
it rather than blindly using `!`.

**2. `encryptedAPKAMSymmetricKey` arrives on the notification**, not from
`fetchEnrollmentRequests` alone, so an approver that never subscribes has
nothing to pass to `approved(...)`. Approving is not a poll-only workflow.

**3. Only `__manage` can approve.** The atServer grants that namespace to the
app that submitted the `FirstEnrollmentRequest` when the atsign was activated,
and it is what makes that app the administrator for every later request. So if
an atsign was activated without any enrolment being recorded, nothing holds
`__manage` and **no app can approve a later request** — that is fixed at
activation time, not here. Verify an approver exists before you ship a device
that depends on one.

> **SDK doc trap:** the doc comments on `EnrollmentService` show
> `atClient.encryptionService.fetchEnrollmentRequests()` and
> `.encryptionService.deny(...)`. That is a copy-paste slip in the SDK
> comments — the member is `enrollmentService`. `encryptionService` is a
> different thing entirely.

`revoke` expires the enrolment and closes its live connections; a revoked id
cannot be reused. Statuses are
`EnrollmentStatus { pending, approved, denied, revoked, expired }`.

---

## Lower level — `at_auth` directly

`AtOnboardingService` wraps `at_auth`. Drop to `at_auth` only when you are not
using `at_onboarding_cli` — you then own the `AtLookUp` and the key handling:

```dart
final atEnrollment = AtEnrollment.create();

final response = await atEnrollment.submit(
  AtEnrollmentRequest(
    session: session,          // supplies atSign + rootDomain + atKeysIo
    appName: 'my_agent',
    deviceName: 'gateway-01',
    otp: otp,
    namespaces: {'my_app': 'rw'},
  ),
  atLookUp,
);

await atEnrollment.waitForApproval(response);
// response.session is the hand-off; response.atAuthKeys is deprecated.
```

Pass `session`. The loose `atSign`, `rootDomain`, `apkamPublicKey` and
`encryptedAPKAMSymmetricKey` parameters are all `@Deprecated` in favour of it,
and the constructor throws `ArgumentError` if neither `session` nor the
deprecated `atSign` is supplied. On the response, read `session` — `atAuthKeys`
is deprecated too.

`waitForApproval` polls with defaults of its own, and they are far more
generous than `enroll()`'s. That mismatch is the point worth carrying: the two
entry points do not agree on how long to wait, so read the defaults of
whichever one you call instead of assuming. Neither substitutes for your own
deadline — if giving up matters, race the wait against your own timer rather
than trusting a retry budget to bound it. Use `list(statusFilters, atLookUp)`
to enumerate enrolments by status.
