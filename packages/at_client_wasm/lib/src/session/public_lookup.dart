import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart'
    show AtLookUpException, SecondaryAddressFinder;

/// The value of an unauthenticated `lookup:<key>` against [atSign]'s server,
/// on a connection of its own from [lookUps] that is closed afterwards; null
/// when the key is not found (AT0015) or holds null.
Future<String?> publicLookup(
    {required AtLookUpFactory lookUps,
    required AtRootDomain rootDomain,
    SecondaryAddressFinder? secondaryAddressFinder,
    required String atSign,
    required String key}) async {
  final lookUp = lookUps(
      atSign: atSign,
      rootDomain: rootDomain,
      authenticator: null,
      secondaryAddressFinder: secondaryAddressFinder);
  try {
    final response = await lookUp.executeCommand('lookup:$key\n');
    if (response == null || !response.startsWith('data:')) {
      throw StateError('unexpected lookup response: $response');
    }
    final text = response.substring('data:'.length).trim();
    return text == 'null' ? null : text;
  } on AtLookUpException catch (e) {
    if (e.errorCode == 'AT0015') return null;
    rethrow;
  } finally {
    await lookUp.close();
  }
}
