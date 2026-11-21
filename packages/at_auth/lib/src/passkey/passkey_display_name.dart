import 'dart:convert';

/// The most UTF-8 bytes a passkey's display name may hold.
const passkeyDisplayNameMaxBytes = 64;

/// The display name of a passkey registered at [enrolledAt] from the device
/// [deviceName]: [enrolledAt] in UTC to the minute, then ` \u00b7 ` and
/// [deviceName], as `2026-11-06 14:05Z \u00b7 Alice Mac`.
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
