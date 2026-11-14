/// The most characters of an enrollment id a message quotes.
const int maxQuotedEnrollmentIdLength = 40;

/// [enrollmentId], read from a keyfile, as a message may quote it: each
/// control character, bidirectional formatting character and line or
/// paragraph separator replaced with `?`, and cut to
/// [maxQuotedEnrollmentIdLength] characters, followed by `...`, when it is
/// longer.
String printableEnrollmentId(String enrollmentId) {
  final characters = enrollmentId.runes.toList();
  final kept = characters.length > maxQuotedEnrollmentIdLength
      ? characters.sublist(0, maxQuotedEnrollmentIdLength)
      : characters;
  final printable = String.fromCharCodes(
      [for (final c in kept) _isUnprintable(c) ? 0x3f : c]);
  return kept.length < characters.length ? '$printable...' : printable;
}

/// Whether [c] is a control character (C0, DEL, C1), a bidirectional
/// formatting character, or a line or paragraph separator.
bool _isUnprintable(int c) =>
    c < 0x20 ||
    (c >= 0x7f && c <= 0x9f) ||
    c == 0x061c ||
    c == 0x200e ||
    c == 0x200f ||
    (c >= 0x2028 && c <= 0x202e) ||
    (c >= 0x2066 && c <= 0x2069);
