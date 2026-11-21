import 'dart:typed_data';

import 'package:at_auth/passkey.dart' show passkeyDisplayName;

import 'random_bytes.dart';

/// The WebAuthn ceremony timeout, in milliseconds, for create and get.
const passkeyCeremonyTimeoutMs = 120000;

/// The WebAuthn `publicKey` creation options for a discoverable passkey.
///
/// `user.id` is 64 fresh random bytes, so a passkey names no atSign and each
/// registration is a distinct user; [atSign] is `user.name` only, and
/// `user.displayName` is [passkeyDisplayName] of [enrolledAt] and
/// [deviceName]. The `prf` extension is enabled without an eval input: the
/// PRF output is read by a later assertion.
Map<String, Object?> passkeyCreationOptions({
  required String rpId,
  required String rpName,
  required String atSign,
  required DateTime enrolledAt,
  required String deviceName,
  Uint8List Function(int length) random = randomBytes,
}) =>
    {
      'publicKey': {
        'challenge': random(32),
        'timeout': passkeyCeremonyTimeoutMs,
        'rp': {'id': rpId, 'name': rpName},
        'user': {
          'id': random(64),
          'name': atSign,
          'displayName': passkeyDisplayName(enrolledAt, deviceName)
        },
        'pubKeyCredParams': [
          {'type': 'public-key', 'alg': -7},
          {'type': 'public-key', 'alg': -257}
        ],
        'authenticatorSelection': {
          'residentKey': 'required',
          'userVerification': 'required'
        },
        'extensions': {'prf': <String, Object?>{}}
      }
    };
