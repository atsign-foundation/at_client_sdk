import 'package:at_auth/at_auth.dart';
import 'package:test/test.dart';

String _kindOf(AtKeysIo io) => switch (io) {
      WrittenAtKeysIo() => 'written',
      GeneratedAtKeysIo() => 'generated',
    };

void main() {
  test(
      "A switch over AtKeysIo's subtypes needs only WrittenAtKeysIo and "
      'GeneratedAtKeysIo', () {
    expect(_kindOf(InMemoryAtKeysIo()), 'written');
  });
}
