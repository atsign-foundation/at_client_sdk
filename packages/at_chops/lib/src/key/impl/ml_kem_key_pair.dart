

import 'package:at_chops/at_chops.dart';

final class MlKemKeyPair implements AsymmetricKeyPair {

  late AtPublicKey _atPublicKey;
  late AtPrivateKey _atPrivateKey; 

  @override
  AtPublicKey get atPublicKey => _atPublicKey;

  @override
  AtPrivateKey get atPrivateKey => _atPrivateKey;
}
