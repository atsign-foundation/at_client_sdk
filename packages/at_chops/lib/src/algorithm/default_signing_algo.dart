import 'package:at_chops/src/algorithm/algo_type.dart';
import 'package:at_chops/src/algorithm/signing/rsa.dart';
import 'package:at_chops/src/key/keys.dart';

@Deprecated(
    'Use RsaSignatureAlgo instead. This compatibility wrapper will be removed '
    'in the next major release.')
class DefaultSigningAlgo extends RsaSigningAlgo {
  // Cannot use super parameters here because the superclass constructor
  // parameters are private to its library.
  // ignore: use_super_parameters
  DefaultSigningAlgo(
      AsymmetricKeyPair? encryptionKeyPair, HashingAlgoType hashingAlgoType)
      : super(encryptionKeyPair, hashingAlgoType);
}
