import 'package:at_chops/src/key/impl/ml_dsa_65_key_pair.dart';

@Deprecated(
    'Use MlDsa65KeyPair instead. This compatibility wrapper will be removed '
    'in the next major release.')
class AtMlDsa65KeyPair extends MlDsa65KeyPair {
  AtMlDsa65KeyPair.create(super.publicKey, super.privateKey) : super.create();
}
