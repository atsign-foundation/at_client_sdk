import 'dart:typed_data';

import 'aes_gcm.dart';
import 'passkey_creation_options.dart';

/// The WebAuthn `publicKey` request options for an assertion that evaluates
/// the `prf` extension on [evalInput], optionally restricted to
/// [allowCredential].
Map<String, Object?> passkeyRequestOptions({
  required String rpId,
  required Uint8List evalInput,
  Uint8List? allowCredential,
  Uint8List Function(int length) random = randomBytes,
}) =>
    {
      'publicKey': {
        'challenge': random(32),
        'timeout': passkeyCeremonyTimeoutMs,
        'rpId': rpId,
        'userVerification': 'required',
        'allowCredentials': [
          if (allowCredential != null)
            {'type': 'public-key', 'id': allowCredential}
        ],
        'extensions': {
          'prf': {
            'eval': {'first': evalInput}
          }
        }
      }
    };
