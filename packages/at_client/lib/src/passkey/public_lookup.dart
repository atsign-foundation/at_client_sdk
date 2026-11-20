import 'package:at_auth/passkey.dart' show clipForMessage;
import 'package:at_commons/at_builders.dart' show LookupVerbBuilder;
import 'package:at_commons/at_commons.dart'
    show AtRootDomain, InvalidResponseException;
import 'package:at_commons/atsign.dart';
import 'package:at_lookup/at_lookup.dart'
    show AtLookUpException, AtLookUpFactory, SecondaryAddressFinder;

/// The value of an unauthenticated `lookup:` of [key] (in [namespace], when
/// given) shared by [atSign], against [atSign]'s server,
/// on a connection of its own from [lookUps] that is closed afterwards; null
/// when the key is not found (AT0015) or holds null.
Future<String?> publicLookup(
    {required AtLookUpFactory lookUps,
    required AtRootDomain rootDomain,
    SecondaryAddressFinder? secondaryAddressFinder,
    required String atSign,
    required String key,
    String? namespace}) async {
  final lookUp = lookUps(
      atSign: atSign,
      rootDomain: rootDomain,
      authenticator: null,
      secondaryAddressFinder: secondaryAddressFinder);
  try {
    final response = await lookUp.executeCommand((LookupVerbBuilder()
          ..atKey.key = key
          ..atKey.namespace = namespace
          ..atKey.sharedBy = atSign.toAtsign())
        .buildCommand());
    if (response == null || !response.startsWith('data:')) {
      throw InvalidResponseException(
          'unexpected lookup response: ${clipForMessage('$response')}');
    }
    final text = response.substring('data:'.length).trim();
    return text == 'null' ? null : text;
  } on AtLookUpException catch (e) {
    // AT0015 is a key that does not exist; it is reported as null.
    if (e.errorCode == 'AT0015') return null;
    rethrow;
  } finally {
    await lookUp.close();
  }
}
