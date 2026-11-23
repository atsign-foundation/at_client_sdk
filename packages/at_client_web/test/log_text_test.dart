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

  test('truncateText does not split a surrogate pair', () {
    expect(truncateText('ab\u{1F600}cd', 5), 'ab...');
  });
}
