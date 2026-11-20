import 'package:at_auth/passkey.dart';
import 'package:test/test.dart';

/// A backslash, so expected escapes read as `${bs}u000a`.
const bs = r'\';

void main() {
  group('clipForMessage', () {
    test('quotes short printable text unchanged', () {
      expect(clipForMessage('error:AT0015'), '"error:AT0015"');
    });

    test('escapes quotes and backslashes', () {
      expect(clipForMessage('a"b${bs}c'), '"a$bs"b$bs${bs}c"');
    });

    test('escapes line breaks, controls and format characters', () {
      final reply = 'error:x\n[INFO] key accepted'
          '${String.fromCharCodes([0x202e, 0x00, 0x200b])}';
      expect(
          clipForMessage(reply),
          '"error:x${bs}u000a[INFO] key accepted'
          '${bs}u202e${bs}u0000${bs}u200b"');
    });

    test('escapes a format character outside the basic plane', () {
      expect(clipForMessage('a${String.fromCharCode(0xe0041)}'),
          '"a${bs}u{e0041}"');
    });

    test('clips long text to the limit, escapes counted, inside the quotes',
        () {
      final clipped = clipForMessage('a' * 10000);
      expect(clipped, '"${'a' * 180}..."');

      final escaped = clipForMessage('\n' * 10000);
      expect(escaped.length, lessThanOrEqualTo(180 + '"..."'.length));
      expect(escaped, endsWith('..."'));
      expect(escaped, isNot(contains('\n')));
    });
  });
}
