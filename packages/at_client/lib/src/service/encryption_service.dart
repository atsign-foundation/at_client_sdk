import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_utils/at_logger.dart';

class EncryptionService {
  RemoteSecondary? remoteSecondary;

  LocalSecondary? localSecondary;

  late final String atSign;

  late final AtSignLogger logger;

  EncryptionService(this.atSign) {
    logger = AtSignLogger('EncryptionService ($atSign)');
  }

  /// Used in atmosphere pro
  String generateFileEncryptionKey() {
    return EncryptionUtil.generateAESKey();
  }
}
