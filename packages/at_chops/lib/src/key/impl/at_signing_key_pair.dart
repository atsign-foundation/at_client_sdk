import 'package:at_chops/src/key/at_key_pair.dart';

class AtSigningKeyPair extends AsymmetricKeyPair {
  AtSigningKeyPair.create(super.publicKey, super.privateKey) : super.create();
}
