import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:at_lookup/at_lookup_web.dart';

/// A program for the browser: it opens an atSign from in-memory keys on the
/// memory storage, then puts, gets, deletes and lists keys.
///
/// `web_safe_test.dart` compiles it with dart2wasm; nothing runs it.
Future<void> main() async {
  const atSign = '@alice';
  final preference = AtClientPreference()..namespace = 'wavi';
  final client = await Atsign(atSign).open(
      // ignore: invalid_use_of_visible_for_testing_member
      keys: InMemoryAtKeysIo.holding(atSign, AtKeys()),
      preference: preference,
      storage: InMemoryAtClientStorage(atSign: atSign, closedByClient: true),
      lookUps: webSocketLookUps(),
      secondaryAddressFinder:
          HttpsSecondaryAddressFinder(preference.rootDomain));
  final phone =
      AtKey.self('phone', namespace: 'wavi', sharedBy: atSign).build();
  await client.put(phone, '+44 7700 900000');
  print((await client.get(phone)).value);
  await client.delete(phone);
  print(await client.getAtKeys(regex: 'wavi'));
  await client.stop();
}
