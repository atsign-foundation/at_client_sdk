import 'package:at_chops/src/key/at_key_pair.dart';

class AtEncryptionKeyPair extends AsymmetricKeyPair {
  AtEncryptionKeyPair.create(super.publicKey, super.privateKey)
      : super.create();
}
