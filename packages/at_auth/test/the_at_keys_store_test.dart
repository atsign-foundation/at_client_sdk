import 'package:at_auth/at_auth.dart';
import 'package:test/test.dart';

/// `theAtKeysStore`, which names an AtKeys store in a message from what
/// `AtKeysIo.describeSource` says of it.
void main() {
  test(
      'Given no source, or an empty one, when theAtKeysStore names the '
      'store, then it is the AtKeys store with nothing after it', () {
    expect(theAtKeysStore(null), 'the AtKeys store',
        reason: 'a store whoever names it gave no source for');
    expect(theAtKeysStore(''), 'the AtKeys store',
        reason: 'a store with nothing more to say of itself');
  });

  test(
      'Given a source, when theAtKeysStore names the store, then the source '
      'is in brackets after it', () {
    expect(theAtKeysStore("this device's keychain"),
        "the AtKeys store (this device's keychain)",
        reason: 'the source is in brackets after "the AtKeys store"');
  });
}
