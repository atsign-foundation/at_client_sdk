/// The longest stretch of text from outside the process that an exception
/// message carries, escapes included, before it is elided.
const maxMessageTextLength = 180;

/// [text] as it may appear in an exception message or a log line: in double
/// quotes, with JSON-style escapes for quotes, backslashes and every control,
/// format and line-separator character, and at most [maxMessageTextLength]
/// characters of it as written, escapes included, the rest elided with an
/// ellipsis inside the quotes.
///
/// Never pass key material, its ciphertext or a secret: name the field
/// instead.
String clipForMessage(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final shown = rune == 0x22
        ? r'\"'
        : rune == 0x5c
            ? r'\\'
            : _unprintable(rune)
                ? rune > 0xffff
                    ? '\\u{${rune.toRadixString(16)}}'
                    : '\\u${rune.toRadixString(16).padLeft(4, '0')}'
                : String.fromCharCode(rune);
    if (out.length + shown.length > maxMessageTextLength) {
      out.write('...');
      break;
    }
    out.write(shown);
  }
  return '"$out"';
}

/// Whether [rune] is a control, format, line-separator or lone surrogate
/// character: one that could make text read as something else when printed.
bool _unprintable(int rune) =>
    rune < 0x20 ||
    (rune >= 0x7f && rune <= 0x9f) ||
    rune == 0xad ||
    (rune >= 0x0600 && rune <= 0x0605) ||
    rune == 0x061c ||
    rune == 0x06dd ||
    rune == 0x070f ||
    (rune >= 0x0890 && rune <= 0x0891) ||
    rune == 0x08e2 ||
    rune == 0x180e ||
    (rune >= 0x200b && rune <= 0x200f) ||
    (rune >= 0x2028 && rune <= 0x202e) ||
    (rune >= 0x2060 && rune <= 0x206f) ||
    (rune >= 0xd800 && rune <= 0xdfff) ||
    rune == 0xfeff ||
    (rune >= 0xfff9 && rune <= 0xfffb) ||
    rune == 0x110bd ||
    rune == 0x110cd ||
    (rune >= 0x13430 && rune <= 0x1343f) ||
    (rune >= 0x1bca0 && rune <= 0x1bca3) ||
    (rune >= 0x1d173 && rune <= 0x1d17a) ||
    (rune >= 0xe0000 && rune <= 0xe007f);
