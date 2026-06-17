import 'package:at_chops/src/key/keys.dart';

class AtEncryptionKeyPair extends AsymmetricKeyPair {
  AtEncryptionKeyPair.create(super.publicKey, super.privateKey)
      : super.create();
}
