import 'package:at_chops/src/key/impl/rsa_key_pair.dart';

@Deprecated(
    'Use RsaKeyPair instead. This compatibility wrapper will be removed in '
    'the next major release.')
class AtEncryptionKeyPair extends RsaKeyPair {
  AtEncryptionKeyPair.create(super.publicKey, super.privateKey)
      : super.create();
}
