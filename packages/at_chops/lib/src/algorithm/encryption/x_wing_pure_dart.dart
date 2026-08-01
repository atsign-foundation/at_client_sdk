import 'dart:async';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/encryption/ml_kem_768_pure_dart.dart';
import 'package:at_chops/src/algorithm/encryption/x25519_pure_dart_algo.dart';
import 'package:at_chops/src/algorithm/encryption/x_wing_sizes.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:meta/meta.dart';
import 'package:pointycastle/digests/sha3.dart';
import 'package:pointycastle/digests/shake.dart';

/// X-Wing: general-purpose hybrid post-quantum/traditional KEM combining
/// X25519 and ML-KEM-768, per draft-connolly-cfrg-xwing-kem-10.
///
/// - secret (decapsulation) key: a 32-byte seed, expanded on use via
///   SHAKE-256 into the ML-KEM-768 (d, z) and the X25519 secret key
/// - public (encapsulation) key: `pk_M || pk_X` (1184 + 32 = 1216 bytes)
/// - ciphertext: `ct_M || ct_X` (1088 + 32 = 1120 bytes), where `ct_X` is
///   the encapsulator's ephemeral X25519 public key
/// - shared secret: `SHA3-256(ss_M || ss_X || ct_X || pk_X || XWingLabel)`,
///   32 bytes
///
/// IND-CCA security holds if EITHER component survives — X25519 carries the
/// classical guarantee while ML-KEM-768 carries the post-quantum one
/// (harvest-now-decrypt-later resistance).
///
/// Pure-Dart composition of [MlKem768PureDartAlgo] (`pqcrypto`) and the
/// `cryptography` package's X25519. Stateless — safe to share the single
/// [instance].
final class XWingPureDartAlgo implements AtKemAlgorithm {
  static const XWingPureDartAlgo instance = XWingPureDartAlgo._();

  const XWingPureDartAlgo._();

  static const int seedLength = XWingSizes.seedLength;
  static const int publicKeyLength = XWingSizes.publicKeyLength;
  static const int ciphertextLength = XWingSizes.ciphertextLength;
  static const int sharedSecretLength = XWingSizes.sharedSecretLength;

  static const int _mlKemPublicKeyLength = 1184;
  static const int _mlKemCiphertextLength = 1088;

  /// `XWingLabel`: the ASCII bytes of `\.//^\`.
  static final Uint8List _label =
      Uint8List.fromList([0x5c, 0x2e, 0x2f, 0x2f, 0x5e, 0x5c]);

  static final crypto.X25519 _x25519 = crypto.X25519();

  /// Generate an X-Wing key pair.
  ///
  /// Returns `(publicKey: 1216 bytes, secretKey: 32 bytes)` — the secret key
  /// IS the [seed]; everything else is re-derived from it on decapsulation.
  /// Pass a 32-byte [seed] for deterministic generation (testing), otherwise
  /// one is drawn from a secure random source.
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair(
      [Uint8List? seed]) async {
    seed ??= _randomSeed();
    final _Expanded expanded = await _expand(seed);
    final Uint8List publicKey = Uint8List(publicKeyLength)
      ..setRange(0, _mlKemPublicKeyLength, expanded.mlKemPublicKey)
      ..setRange(_mlKemPublicKeyLength, publicKeyLength, expanded.x25519Public);
    return (publicKey: publicKey, secretKey: Uint8List.fromList(seed));
  }

  @override
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
      Uint8List publicKey) async {
    final ephemeral = await _x25519.newKeyPair();
    final Uint8List ephemeralSecret =
        Uint8List.fromList(await ephemeral.extractPrivateKeyBytes());
    return _encapsulateWith(publicKey, ephemeralSecret, null);
  }

  /// Derandomized encapsulation per the draft's `EncapsulateDerand`:
  /// `eseed[0:32]` is the ML-KEM-768 randomness `m`, `eseed[32:64]` the
  /// ephemeral X25519 secret. Exists to verify the draft's test vectors;
  /// production callers use [encapsulate].
  @visibleForTesting
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulateDerand(
      Uint8List publicKey, Uint8List eseed) async {
    if (eseed.length != 64) {
      throw ArgumentError.value(
          eseed.length, 'eseed', 'X-Wing eseed must be 64 bytes');
    }
    return _encapsulateWith(
        publicKey, eseed.sublist(32, 64), eseed.sublist(0, 32));
  }

  Future<({Uint8List ciphertext, Uint8List sharedSecret})> _encapsulateWith(
      Uint8List publicKey,
      Uint8List ephemeralX25519Secret,
      Uint8List? mlKemRandomness) async {
    if (publicKey.length != publicKeyLength) {
      throw ArgumentError.value(publicKey.length, 'publicKey',
          'X-Wing public key must be $publicKeyLength bytes');
    }
    final Uint8List mlKemPublic = publicKey.sublist(0, _mlKemPublicKeyLength);
    final Uint8List x25519Public = publicKey.sublist(_mlKemPublicKeyLength);

    final (ciphertext: ctM, sharedSecret: ssM) = await MlKem768PureDartAlgo
        .instance
        .encapsulate(mlKemPublic, mlKemRandomness);

    final crypto.SimpleKeyPair ephemeral =
        await _x25519.newKeyPairFromSeed(ephemeralX25519Secret);
    final Uint8List ctX =
        Uint8List.fromList((await ephemeral.extractPublicKey()).bytes);
    final Uint8List ssX = await X25519PureDartAlgo.instance
        .dh(ephemeralX25519Secret, x25519Public);

    final Uint8List ciphertext = Uint8List(ciphertextLength)
      ..setRange(0, _mlKemCiphertextLength, ctM)
      ..setRange(_mlKemCiphertextLength, ciphertextLength, ctX);
    return (
      ciphertext: ciphertext,
      sharedSecret: _combine(ssM, ssX, ctX, x25519Public),
    );
  }

  @override
  Future<Uint8List> decapsulate(
      Uint8List secretKey, Uint8List ciphertext) async {
    if (secretKey.length != seedLength) {
      throw ArgumentError.value(secretKey.length, 'secretKey',
          'X-Wing secret key must be the $seedLength-byte seed');
    }
    if (ciphertext.length != ciphertextLength) {
      throw ArgumentError.value(ciphertext.length, 'ciphertext',
          'X-Wing ciphertext must be $ciphertextLength bytes');
    }
    final _Expanded expanded = await _expand(secretKey);
    final Uint8List ctM = ciphertext.sublist(0, _mlKemCiphertextLength);
    final Uint8List ctX = ciphertext.sublist(_mlKemCiphertextLength);

    final Uint8List ssM = await MlKem768PureDartAlgo.instance
        .decapsulate(expanded.mlKemSecretKey, ctM);
    final Uint8List ssX =
        await X25519PureDartAlgo.instance.dh(expanded.x25519Secret, ctX);

    return _combine(ssM, ssX, ctX, expanded.x25519Public);
  }

  /// `expandDecapsulationKey(sk)`: SHAKE-256(sk, 96 bytes); bytes [0:64]
  /// are ML-KEM-768's (d || z), bytes [64:96] the X25519 secret key.
  Future<_Expanded> _expand(Uint8List seed) async {
    if (seed.length != seedLength) {
      throw ArgumentError.value(
          seed.length, 'seed', 'X-Wing seed must be $seedLength bytes');
    }
    final SHAKEDigest shake = SHAKEDigest(256);
    shake.update(seed, 0, seed.length);
    final Uint8List expanded = Uint8List(96);
    shake.doOutput(expanded, 0, 96);

    final (publicKey: pkM, secretKey: skM) = await MlKem768PureDartAlgo.instance
        .generateKeyPair(expanded.sublist(0, 64));
    final Uint8List skX = expanded.sublist(64, 96);
    final crypto.SimpleKeyPair x25519Pair =
        await _x25519.newKeyPairFromSeed(skX);
    final Uint8List pkX =
        Uint8List.fromList((await x25519Pair.extractPublicKey()).bytes);
    return _Expanded(
      mlKemPublicKey: pkM,
      mlKemSecretKey: skM,
      x25519Secret: skX,
      x25519Public: pkX,
    );
  }

  /// `SHA3-256(ss_M || ss_X || ct_X || pk_X || XWingLabel)`.
  Uint8List _combine(
      Uint8List ssM, Uint8List ssX, Uint8List ctX, Uint8List pkX) {
    final Uint8List input =
        Uint8List(ssM.length + ssX.length + ctX.length + pkX.length + 6)
          ..setRange(0, 32, ssM)
          ..setRange(32, 64, ssX)
          ..setRange(64, 96, ctX)
          ..setRange(96, 128, pkX)
          ..setRange(128, 134, _label);
    return SHA3Digest(256).process(input);
  }

  Uint8List _randomSeed() {
    final Random random = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(seedLength, (_) => random.nextInt(256)));
  }
}

class _Expanded {
  final Uint8List mlKemPublicKey;
  final Uint8List mlKemSecretKey;
  final Uint8List x25519Secret;
  final Uint8List x25519Public;

  _Expanded({
    required this.mlKemPublicKey,
    required this.mlKemSecretKey,
    required this.x25519Secret,
    required this.x25519Public,
  });
}
