import 'dart:math';

class TestUtils {
  static String createRandomString(int length) {
    final String characters =
        '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_';
    return String.fromCharCodes(Iterable.generate(length,
        (index) => characters.codeUnitAt(Random().nextInt(characters.length))));
  }
}
