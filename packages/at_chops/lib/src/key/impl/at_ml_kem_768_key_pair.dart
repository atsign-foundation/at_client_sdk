import 'package:at_chops/src/key/impl/ml_kem_768_key_pair.dart';

@Deprecated(
    'Use MlKem768KeyPair instead. This compatibility wrapper will be removed '
    'in the next major release.')
class AtMlKem768KeyPair extends MlKem768KeyPair {
  AtMlKem768KeyPair.create(super.publicKey, super.privateKey) : super.create();
}
