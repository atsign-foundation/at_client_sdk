import 'package:at_chops/src/algorithm/at_iv.dart';
import 'package:at_chops/src/key/key_type.dart';

/// Class which represents metadata for encryption/decryption.
@Deprecated(
    'Use the direct encryption algorithm result bytes and your own metadata '
    'instead. This compatibility API will be removed in the next major '
    'release.')
class AtEncryptionMetaData {
  String atEncryptionAlgorithm;
  String? keyName;
  EncryptionKeyType encryptionKeyType;
  InitialisationVector? iv;
  AtEncryptionMetaData(this.atEncryptionAlgorithm, this.encryptionKeyType);
}
