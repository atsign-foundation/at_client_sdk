import 'package:test/test.dart';
import 'package:dart_utf7/utf7.dart';

void main() {
  test('Decodes text successfully', () {
    var encoded = 'Hello, +ThZ1TA-';
    expect(Utf7.decode(encoded), equals('Hello, 世界'));
  });
  test('Encodes text successfully', () {
    var encoded = 'Hello, 世界';
    expect(Utf7.encode(encoded), equals('Hello, +ThZ1TA-'));
  });
  test('rfc sample one - encode', () {
    expect(Utf7.encode('A≢Α.'), anyOf(equals('A+ImIDkQ.'), equals('A+ImIDkQ-.')));
  });
  test('rfc sample one - decode', () {
    expect(Utf7.decode('A+ImIDkQ.'), equals('A≢Α.'));
  });
  test('rfc sample two - encode', () {
    expect(Utf7.encode('Hi Mom -☺-!'), equals('Hi Mom -+Jjo--!'));
  });
  test('rfc sample two - decode', () {
    expect(Utf7.decode('Hi Mom -+Jjo--!'), equals('Hi Mom -☺-!'));
  });
  test('rfc sample three - encode', () {
    expect(Utf7.encode('日本語'), equals('+ZeVnLIqe-'));
  });
  test('rfc sample three - decode', () {
    expect(Utf7.decode('+ZeVnLIqe-'), equals('日本語'));
  });
  test('rfc sample four - encode', () {
    expect(Utf7.encode('Item 3 is £1.'), equals('Item 3 is +AKM-1.'));
  });
  test('rfc sample four - decode', () {
    expect(Utf7.decode('Item 3 is +AKM-1.'), equals('Item 3 is £1.'));
  });
  test('encodeAll encodes line ends, spaces and other special characters', () {
    expect(Utf7.encodeAll('Äb\r\n#^s\\'), equals('+AMQ-b+AA0ACgAjAF4-s+AFw-'));
  });
}
