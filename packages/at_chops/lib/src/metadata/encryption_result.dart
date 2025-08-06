import 'package:at_chops/src/metadata/encryption_metadata.dart';

// Class that contains the encryption/decryption result with data type [AtEncryptionResultType] and metadata [AtEncryptionMetaData]
class AtEncryptionResult {
  late AtEncryptionResultType atEncryptionResultType;
  dynamic result;
  late AtEncryptionMetaData atEncryptionMetaData;
}

enum AtEncryptionResultType { bytes, string }
