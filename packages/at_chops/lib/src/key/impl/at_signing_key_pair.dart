import 'package:at_chops/src/key/keys.dart';

class AtSigningKeyPair extends AsymmetricKeyPair {
  AtSigningKeyPair.create(super.publicKey, super.privateKey) : super.create();
}
