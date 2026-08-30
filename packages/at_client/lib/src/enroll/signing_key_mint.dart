import 'package:at_chops/at_chops.dart'
    show MlDsa65KeyPair, RsaKeyPair, SigningAlgoType;

/// A freshly minted data signing keypair for an enrollment being created, or
/// null when [inUse] names none.
///
/// **The algorithm minted is the one the enrollment will keep**, and that is
/// what makes the first start's reconciliation a no-op. An enrollment minted
/// under an algorithm its in-use set does not name is found wanting at that
/// start, which mints a SECOND keypair and republishes `_apsk` — orphaning the
/// key the enrollment record already advertised, and invalidating any signing
/// link conveyed against it, since a link is bound to the exact advertised
/// value it vouched for.
///
/// One home for the three paths that create an enrollment — the self-retrofit,
/// the PQ-native activation and an app's enrolment — because an algorithm one
/// of them mints and another does not is a state where the same posture
/// produces different key material depending on which door the enrollment came
/// through.
///
/// Files nothing and advertises nothing: where the halves go differs by path,
/// and for an enrolment the id to file them under does not exist until the
/// atServer answers.
///
/// Refuses a set naming more than one algorithm rather than choosing one. An
/// envelope carries one signature per active signing key, so two members mean
/// every envelope is signed twice, and a verifier takes the strongest
/// algorithm it and the advertisement share — making the second signature
/// either the one passed over or the one an attacker strips to.
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
      // `RsaKeyPair.generate()` rather than
      // `AtChopsUtil.generateAtPkamKeyPair()`, which returns a type at_chops
      // deprecates.
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
