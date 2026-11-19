import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';

final _logger = AtSignLogger('completeActivation');

/// Completes the activation of [atSign] over [atLookUp], a connection
/// authenticated as the enrollment the activation created: publishes
/// [encryptionPublicKey] as `public:publickey@<atSign>` with `ttr:-1`, then
/// deletes the CRAM secret.
///
/// The publish replaces whatever `publickey` is already published. With no
/// [encryptionPublicKey] nothing is published, and the CRAM secret is deleted
/// all the same. A CRAM secret the atServer reports as not found counts as
/// deleted.
///
/// Returns true when the atServer deleted a CRAM secret, and false when it
/// reported none to delete.
///
/// Throws [ArgumentError], before any command, when [encryptionPublicKey]
/// holds a carriage return or a line feed.
Future<bool> completeActivationOf(
    {required AtLookUp atLookUp,
    required String atSign,
    required String? encryptionPublicKey}) async {
  // NOTE: the update command carries the value as it is, so it must be one
  // line.
  if (encryptionPublicKey != null &&
      (encryptionPublicKey.contains('\r') ||
          encryptionPublicKey.contains('\n'))) {
    throw ArgumentError.value(encryptionPublicKey, 'encryptionPublicKey',
        'must not contain a carriage return or a line feed');
  }
  // NOTE: publish nothing rather than "null" when no key is given.
  if (encryptionPublicKey != null) {
    final updateBuilder = UpdateVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'publickey'
        ..sharedBy = atSign
        ..metadata = (Metadata()
          ..isPublic = true
          ..ttr = -1))
      ..value = encryptionPublicKey;
    final encryptKeyUpdateResult = await atLookUp.executeVerb(updateBuilder);
    _logger.info('Encryption public key update result $encryptKeyUpdateResult');
  } else {
    _logger.info('No encryption public key was given for $atSign, so '
        'public:publickey is left as it is');
  }

  final deleteBuilder = DeleteVerbBuilder()
    ..atKey = (AtKey()..key = AtConstants.atCramSecret);
  try {
    final deleteResponse = await atLookUp.executeVerb(deleteBuilder);
    _logger.info('Cram secret delete response : $deleteResponse');
    return true;
  } on AtLookUpException catch (e) {
    if (e.errorCode != error_codes['KeyNotFoundException']) rethrow;
    _logger.info('The CRAM secret of $atSign was already deleted');
    return false;
  }
}
