import 'package:at_chops/src/algorithm/at_iv.dart';
import 'package:at_chops/src/key/key_type.dart';

/// Class which represents metadata for encryption/decryption.
class AtEncryptionMetaData {
  String atEncryptionAlgorithm;
  String? keyName;
  EncryptionKeyType encryptionKeyType;
  InitialisationVector? iv;
  AtEncryptionMetaData(this.atEncryptionAlgorithm, this.encryptionKeyType);
}
