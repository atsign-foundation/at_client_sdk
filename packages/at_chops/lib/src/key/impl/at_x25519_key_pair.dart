import 'package:at_chops/src/key/impl/x25519_key_pair.dart';

@Deprecated(
    'Use X25519KeyPair instead. This compatibility wrapper will be removed '
    'in the next major release.')
class AtX25519KeyPair extends X25519KeyPair {
  AtX25519KeyPair.create(super.publicKey, super.privateKey) : super.create();
}
