/// The longest stretch of text from outside the process that an exception
/// message carries, counted as written, escapes included.
const maxMessageTextLength = 180;

/// [text] as it may appear in a one-line exception message.
///
/// Each backslash, each control, format and line-separator character and
/// each lone surrogate is shown as a JSON-style escape (`\\`, `\u000a`,
/// `\u{e0001}`), and so is [quote], when given, as a backslash before it. At
/// most [maxLength] characters are kept as written, escapes included, never
/// cutting inside an escape or a character; when any are left out, `...`
/// follows.
///
/// Throws [ArgumentError] when [quote] is not one character.
String clipForMessage(String text,
    {int maxLength = maxMessageTextLength, String? quote}) {
  if (quote != null && quote.runes.length != 1) {
    throw ArgumentError.value(quote, 'quote', 'must be one character');
  }
  final quoteRune = quote?.runes.single;
  final out = StringBuffer();
  for (final rune in text.runes) {
    final shown = rune == quoteRune
        ? '\\$quote'
        : rune == 0x5c
            ? r'\\'
            : _unprintable(rune)
                ? rune > 0xffff
                    ? '\\u{${rune.toRadixString(16)}}'
                    : '\\u${rune.toRadixString(16).padLeft(4, '0')}'
                : String.fromCharCode(rune);
    if (out.length + shown.length > maxLength) {
      out.write('...');
      break;
    }
    out.write(shown);
  }
  return out.toString();
}

/// Whether [rune] is a control (Cc), format (Cf), line or paragraph separator
/// (Zl, Zp) character, or a surrogate.
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
