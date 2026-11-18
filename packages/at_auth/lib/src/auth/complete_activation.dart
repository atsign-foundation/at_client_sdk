import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';

final _logger = AtSignLogger('completeActivation');

/// Completes the activation of [atSign] over [atLookUp], a connection
/// authenticated as the atSign's first enrollment: publishes
/// [encryptionPublicKey] as `public:publickey@<atSign>` with `ttr:-1`, then
/// deletes the CRAM secret.
///
/// The publish replaces whatever `publickey` is already published. With no
/// [encryptionPublicKey] nothing is published, and the CRAM secret is deleted
/// all the same.
Future<void> completeActivationOf(
    {required AtLookUp atLookUp,
    required String atSign,
    required String? encryptionPublicKey}) async {
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
  final deleteResponse = await atLookUp.executeVerb(deleteBuilder);
  _logger.info('Cram secret delete response : $deleteResponse');
}
