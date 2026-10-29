import 'package:at_chops/src/metadata/encryption_metadata.dart';

// Class that contains the encryption/decryption result with data type [AtEncryptionResultType] and metadata [AtEncryptionMetaData]
@Deprecated('Use the direct encryption algorithm result bytes instead. This '
    'compatibility API will be removed in the next major release.')
class AtEncryptionResult {
  late AtEncryptionResultType atEncryptionResultType;
  dynamic result;
  late AtEncryptionMetaData atEncryptionMetaData;
}

@Deprecated('Use the direct encryption algorithm result bytes instead. This '
    'compatibility API will be removed in the next major release.')
enum AtEncryptionResultType { bytes, string }
