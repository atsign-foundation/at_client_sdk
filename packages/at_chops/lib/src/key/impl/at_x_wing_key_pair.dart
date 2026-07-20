import 'package:at_chops/src/key/impl/x_wing_key_pair.dart';

@Deprecated(
    'Use XWingKeyPair instead. This compatibility wrapper will be removed '
    'in the next major release.')
class AtXWingKeyPair extends XWingKeyPair {
  AtXWingKeyPair.create(super.publicKey, super.privateKey) : super.create();
}
