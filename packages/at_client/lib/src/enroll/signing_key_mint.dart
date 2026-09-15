import 'package:at_chops/at_chops.dart'
    show MlDsa65KeyPair, RsaKeyPair, SigningAlgoType;

/// A freshly minted data signing keypair for an enrollment being created, or
/// null when [inUse] names none.
///
/// Files and advertises nothing — the caller stores the halves — and throws
/// [ArgumentError] when [inUse] names more than one algorithm, or one with no
/// mint path.
Future<({SigningAlgoType algorithm, String publicKey, String privateKey})?>
    mintAdvertisedSigningKey(Set<SigningAlgoType> inUse) async {
  if (inUse.isEmpty) return null;
  if (inUse.length > 1) {
    throw ArgumentError.value(
        inUse,
        'inUse',
        'an enrollment is created holding one data signing keypair; name one '
            'algorithm. Two active signing keys sign every envelope twice and '
            'buy nothing a verifier can insist on');
  }
  final algorithm = inUse.single;
  switch (algorithm) {
    case SigningAlgoType.mldsa65:
      final pair = await MlDsa65KeyPair.generate();
      return (
        algorithm: algorithm,
        publicKey: pair.atPublicKey.publicKey,
        privateKey: pair.atPrivateKey.privateKey,
      );
    case SigningAlgoType.rsa2048:
      final pair = RsaKeyPair.generate();
      return (
        algorithm: algorithm,
        publicKey: pair.atPublicKey.publicKey,
        privateKey: pair.atPrivateKey.privateKey,
      );
    default:
      throw ArgumentError.value(
          algorithm,
          'inUse',
          'a data signing keypair can be minted as rsa2048 or mldsa65; '
              '${algorithm.name} has no mint path, and defaulting to one of '
              'the others would advertise a key the caller did not ask for');
  }
}
