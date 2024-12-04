import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:better_cryptography/better_cryptography.dart';

class AesCtrFactory {
  static AesCtr createEncryptionAlgo(AESKey aesKey) {
    switch (aesKey.getLength()) {
      case 16:
        return AesCtr.with128bits(macAlgorithm: MacAlgorithm.empty);
      case 24:
        return AesCtr.with192bits(macAlgorithm: MacAlgorithm.empty);
      case 32:
        return AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
      default:
        throw AtEncryptionException(
            'Invalid AES key length. Valid lengths are 16/24/32 bytes');
    }
  }
}
