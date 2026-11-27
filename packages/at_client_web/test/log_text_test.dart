import 'package:at_client_web/src/log_text.dart';
import 'package:test/test.dart';

void main() {
  test('sanitizeLogText escapes control and bidi characters as \\u escapes',
      () {
    expect(sanitizeLogText('a\x01b\u202ec'), r'"a\u0001b\u202ec"');
  });

  test('sanitizeLogText bounds the text with an ellipsis', () {
    expect(sanitizeLogText('x' * 20, maxLength: 10), '"xxxxxxx..."');
  });

  test('singleLine turns every control and bidi character into a space', () {
    expect(singleLine('a\nb\u202ec\x7f'), 'a b c ');
  });

  test('hasControlText covers C0, C1 and direction characters', () {
    for (final unit in [
      0x00,
      0x1f,
      0x7f,
      0x9f,
      0x061c,
      0x200e,
      0x200f,
      0x2028,
      0x202e,
      0x2066,
      0x2069
    ]) {
      expect(hasControlText(String.fromCharCode(unit)), isTrue,
          reason: 'U+${unit.toRadixString(16)}');
    }
    expect(hasControlText('a  b'), isFalse);
    expect(hasControlText('a\u00a0b'), isFalse);
    expect(hasControlText('a\u200bb'), isFalse);
    expect(hasControlText('a\ufeffb'), isFalse);
  });

  test('truncateText never splits a surrogate pair', () {
    // Seven units of eight: the cut at four falls between the halves of the
    // emoji (units 3 and 4), so the guard drops its high half.
    const value = 'abc\u{1F600}def';
    final cut = truncateText(value, 7);
    expect(cut, 'abc...');
    expect(cut.codeUnits.where((u) => u & 0xFC00 == 0xD800), isEmpty);
  });

  test(
      'the shared log text sanitizer escapes, bounds and flattens untrusted '
      'text', () {
    // Eleven units; the bound of ten cuts at seven, between the emoji halves.
    const untrusted = 'a\x01\u202eb\nc\u{1F600}def';
    final quoted = sanitizeLogText(untrusted, maxLength: 10);
    expect(quoted, startsWith('"'));
    expect(quoted, isNot(contains('\n')));
    expect(quoted, contains(r'\u0001'));
    expect(quoted, contains(r'\u202e'));
    expect(quoted, endsWith('c..."'));
    expect(singleLine(untrusted), 'a  b c\u{1F600}def');
    final cut = truncateText(untrusted, 10);
    expect(cut, 'a\x01\u202eb\nc...');
    expect(cut.codeUnits.where((u) => u & 0xFC00 == 0xD800), isEmpty);
  });
}
