import 'dart:typed_data';

import 'aes_gcm.dart';

/// The WebAuthn ceremony timeout, in milliseconds, for create and get.
const passkeyCeremonyTimeoutMs = 120000;

/// The WebAuthn `publicKey` creation options for a discoverable passkey.
///
/// `user.id` is 64 fresh random bytes, so a passkey names no atSign and each
/// registration is a distinct user; [atSign] appears only as the display
/// name. The `prf` extension is enabled without an eval input: the PRF output
/// is read by a later assertion.
Map<String, Object?> passkeyCreationOptions({
  required String rpId,
  required String rpName,
  required String atSign,
  Uint8List Function(int length) random = randomBytes,
}) =>
    {
      'publicKey': {
        'challenge': random(32),
        'timeout': passkeyCeremonyTimeoutMs,
        'rp': {'id': rpId, 'name': rpName},
        'user': {'id': random(64), 'name': atSign, 'displayName': atSign},
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
