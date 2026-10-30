import 'dart:typed_data';

import 'package:at_client/at_client.dart' show SecretSharingAlgos;
import 'package:at_client/src/secret_sharing/key_package.dart' show PackageKey;

/// A namespace key generation as a minter makes one: a fresh seed under
/// [keyAlgo] and the kid its public half derives.
Future<({String kid, Uint8List seed})> nskeyGeneration(
    [String keyAlgo = SecretSharingAlgos.xWing]) async {
  final kem = SecretSharingAlgos.kemFor(keyAlgo)!;
  final seed = kem.newSeed();
  final pair = await kem.keyPairFromSeed(seed);
  return (
    kid: PackageKey.fromBytes(
            use: SecretSharingAlgos.useEnc, alg: keyAlgo, pub: pair.publicKey)
        .kid,
    seed: seed,
  );
}
