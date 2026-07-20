import 'package:at_chops/src/key/keys.dart';

@Deprecated(
    'Use RsaKeyPair for RSA key material instead. This compatibility wrapper '
    'will be removed in the next major release.')
class AtPkamKeyPair extends AsymmetricKeyPair {
  AtPkamKeyPair.create(super.publicKey, super.privateKey) : super.create();
}
