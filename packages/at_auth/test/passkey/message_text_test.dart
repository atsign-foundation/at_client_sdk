import 'package:at_auth/passkey.dart';
import 'package:test/test.dart';

void main() {
  group('clipForMessage', () {
    test('quotes short text whole', () {
      expect(clipForMessage('error:AT0011-boom'), '"error:AT0011-boom"');
    });

    test('escapes line breaks, so a reply cannot start a log line', () {
      expect(clipForMessage('x\r\n[INFO] login ok'),
          r'"x\u000d\u000a[INFO] login ok"');
    });

    test('escapes format characters such as a right-to-left override', () {
      final rlo = String.fromCharCode(0x202e);
      expect(clipForMessage('a${rlo}b'), '"a${r'\u' '202e'}b"');
    });

    test('escapes quotes and backslashes, so the quoting cannot be closed',
        () {
      expect(clipForMessage(r'a"b\c'), r'"a\"b\\c"');
    });

    test('escapes a code point beyond the BMP in braces', () {
      expect(clipForMessage('\u{e0041}'), r'"\u{e0041}"');
    });

    test('clips to 180 characters, escapes included', () {
      expect(clipForMessage('x' * 1000), '"${'x' * 180}..."');
      final escaped = clipForMessage('\n' * 1000);
      expect(escaped, '"${r'\u000a' * 30}..."');
    });
  });
}
