import 'package:at_chops/src/key/keys.dart';

@Deprecated(
    'Use algorithm-specific key pair classes instead. This compatibility '
    'wrapper will be removed in the next major release.')
class AtSigningKeyPair extends AsymmetricKeyPair {
  AtSigningKeyPair.create(super.publicKey, super.privateKey) : super.create();
}
