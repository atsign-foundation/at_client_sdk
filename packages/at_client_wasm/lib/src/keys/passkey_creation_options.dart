import 'dart:convert';
import 'dart:typed_data';

import 'aes_gcm.dart';

/// The WebAuthn ceremony timeout, in milliseconds, for create and get.
const passkeyCeremonyTimeoutMs = 120000;

/// The most UTF-8 bytes a passkey `user.displayName` may hold.
const passkeyDisplayNameMaxBytes = 64;

/// The passkey `user.displayName`: [enrolledAt] in UTC to the minute, then
/// ` \u00b7 ` and [deviceName], as `2026-11-06 14:05Z \u00b7 Alice Mac`.
///
/// The whole string is at most [passkeyDisplayNameMaxBytes] UTF-8 bytes:
/// [deviceName] is cut after its last code point that fits, never inside one.
String passkeyDisplayName(DateTime enrolledAt, String deviceName) {
  String two(int n) => n.toString().padLeft(2, '0');
  final t = enrolledAt.toUtc();
  final prefix = '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-'
      '${two(t.day)} ${two(t.hour)}:${two(t.minute)}Z \u00b7 ';
  var room = passkeyDisplayNameMaxBytes - utf8.encode(prefix).length;
  final kept = StringBuffer();
  for (final rune in deviceName.runes) {
    final character = String.fromCharCode(rune);
    room -= utf8.encode(character).length;
    if (room < 0) break;
    kept.write(character);
  }
  return '$prefix$kept';
}

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
