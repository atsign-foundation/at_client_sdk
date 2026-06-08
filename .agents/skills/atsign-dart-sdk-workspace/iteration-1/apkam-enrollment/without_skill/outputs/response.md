# Setting Up APKAM Enrollment to Add a New Device to an Existing atSign

## What is APKAM?

APKAM (atPlatform Key Management) is the enrollment mechanism used by the atPlatform to allow new devices or applications to gain authorized access to an existing atSign. Instead of sharing the master key (the `.atKeys` file), a new device goes through an enrollment request flow where the owning device approves or denies access.

---

## Overview of the Enrollment Flow

1. **New device** sends an enrollment request to the atServer.
2. **Owning device** (the one already authenticated) receives a notification of the pending enrollment.
3. **Owning device** approves (or denies) the request.
4. **New device** receives the approved enrollment and can now authenticate.

---

## Step-by-Step Setup

### 1. Add the Dependency

In your `pubspec.yaml`, include the at_client_mobile or at_onboarding_flutter package (which wraps `at_client`):

```yaml
dependencies:
  at_client_mobile: ^4.x.x
  at_onboarding_flutter: ^7.x.x   # optional UI helper
```

Run:

```bash
dart pub get
```

---

### 2. Initiate Enrollment on the New Device

On the new (unauthenticated) device, you send an enrollment request. The SDK provides `AtEnrollmentImpl` or uses the onboarding flow to handle this.

Using the low-level `at_client` approach:

```dart
import 'package:at_client/at_client.dart';
import 'package:at_auth/at_auth.dart';

final atSign = '@example';

// Build preferences
final prefs = AtClientPreference()
  ..rootDomain = 'root.atsign.org'
  ..hiveStoragePath = '/path/to/storage'
  ..commitLogPath = '/path/to/commitlog'
  ..isLocalStoreRequired = true;

// Create enrollment request
final enrollmentRequest = AtEnrollmentRequest(
  atSign: atSign,
  appName: 'MyNewApp',       // identifies the application
  deviceName: 'MyNewPhone',  // identifies the device
  namespaces: {
    'myapp': 'rw',           // namespace -> access level (r, w, or rw)
  },
  // Optional: provide an APKAM public key if managing keys yourself
);

// Submit the enrollment request
final atAuth = AtAuthImpl();
final response = await atAuth.enroll(prefs, enrollmentRequest);

print('Enrollment ID: ${response.enrollmentId}');
print('APKAM keys generated — store them securely');
```

The SDK automatically:
- Generates an APKAM key pair for the new device.
- Sends the `enroll:request` verb to the atServer.
- Returns an enrollment ID that must be polled until approved.

---

### 3. Approve the Enrollment on the Owning Device

The owning device (already authenticated) will receive a notification. It can list and approve pending enrollments:

```dart
import 'package:at_client/at_client.dart';

final atClient = AtClientManager.getInstance().atClient;

// List pending enrollments
final enrollmentService = atClient.enrollmentService;
final pendingList = await enrollmentService.fetchEnrollmentRequests(
  EnrollmentListRequestParam()
    ..enrollmentStatusFilter = [EnrollmentStatus.pending],
);

for (final enrollment in pendingList) {
  print('Enrollment ID : ${enrollment.enrollmentId}');
  print('App Name      : ${enrollment.appName}');
  print('Device Name   : ${enrollment.deviceName}');
  print('Namespaces    : ${enrollment.namespaces}');
}

// Approve a specific enrollment
final enrollmentId = pendingList.first.enrollmentId;
await enrollmentService.approve(
  EnrollmentRequestDecision.approved(
    ApprovedRequestDecisionParams(
      enrollmentId: enrollmentId,
      encryptedAPKAMSymmetricKey: '<generated-by-sdk>',
    ),
  ),
);

print('Enrollment $enrollmentId approved');
```

The SDK handles encrypting the APKAM symmetric key with the new device's public key before sending the approval.

---

### 4. Complete Authentication on the New Device

After approval, the new device polls or listens for the approval and then completes authentication:

```dart
// Poll for enrollment status
final enrollmentResponse = await atAuth.fetchEnrollmentStatus(
  prefs,
  atSign,
  enrollmentId: response.enrollmentId,
);

if (enrollmentResponse.enrollmentStatus == EnrollmentStatus.approved) {
  // Persist the APKAM keys
  await atAuth.persistKeysLocalSecretManager(enrollmentResponse, prefs);

  // Now authenticate normally
  final atAuthResponse = await atAuth.authenticate(
    AtAuthRequest(atSign: atSign)..atKeysFilePath = '/path/to/new_device.atKeys',
    prefs,
  );
  print('Authenticated: ${atAuthResponse.isSuccessful}');
}
```

---

### 5. Using the High-Level Onboarding UI (Flutter)

If you are building a Flutter app, `at_onboarding_flutter` handles this entire flow with built-in screens:

```dart
import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';

AtOnboarding.onboard(
  context: context,
  config: AtOnboardingConfig(
    atClientPreference: prefs,
    domain: 'root.atsign.org',
    rootEnvironment: RootEnvironment.Production,
    appAPIKey: 'your-api-key',  // from my.atsign.com
  ),
);
```

This widget detects whether the atSign is new or existing and presents:
- QR code scanning for CRAM authentication (first device).
- Enrollment request flow for subsequent devices.

---

## Key Concepts

| Concept | Description |
|---|---|
| **Enrollment ID** | Unique identifier for each enrollment request; used to track approval status. |
| **APKAM key pair** | An RSA key pair generated per device; the private key never leaves the device. |
| **APKAM symmetric key** | An AES key encrypted with the APKAM public key; used to decrypt self encryption keys. |
| **Namespaces** | Fine-grained access scoping; a new device can be restricted to specific app namespaces. |
| **Enrollment Status** | `pending`, `approved`, `denied`, `revoked`. |

---

## Revoking a Device

To revoke a previously enrolled device:

```dart
await enrollmentService.revoke(
  EnrollmentRequestDecision.revoked(
    RevokedRequestDecisionParams(enrollmentId: enrollmentIdToRevoke),
  ),
);
```

After revocation, the revoked device can no longer authenticate with that atSign.

---

## Common Pitfalls

- **Storage paths must be unique per atSign** on the device to avoid key collisions.
- **Namespaces must match** what your app uses; requesting `rw` on a namespace your app never writes to is not harmful but requesting too-narrow access will cause permission errors at runtime.
- **The owning device must be online** (or come online within the enrollment TTL) to approve the request; if it never approves, the enrollment expires on the server.
- **Do not share `.atKeys` files** between devices — that defeats the purpose of APKAM. Each device should go through the enrollment flow.

---

## References

- [atPlatform Documentation](https://docs.atsign.com)
- [at_client pub.dev page](https://pub.dev/packages/at_client)
- [at_auth pub.dev page](https://pub.dev/packages/at_auth)
- [at_onboarding_flutter pub.dev page](https://pub.dev/packages/at_onboarding_flutter)
- [APKAM design document (GitHub)](https://github.com/atsign-foundation/at_protocol/blob/trunk/decisions/2022-10-APKAM.md)
