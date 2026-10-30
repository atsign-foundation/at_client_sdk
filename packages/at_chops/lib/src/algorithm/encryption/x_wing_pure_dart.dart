import 'dart:async';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/encryption/ml_kem_768_pure_dart.dart';
import 'package:at_chops/src/algorithm/encryption/x25519_pure_dart_algo.dart';
import 'package:at_chops/src/algorithm/encryption/x_wing_core.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:meta/meta.dart';

/// X-Wing: general-purpose hybrid post-quantum/traditional KEM combining
/// X25519 and ML-KEM-768. Registered at **IANA HPKE KEM id `0x647A`**.
///
/// ## Which document to cite
///
/// The construction originates in `draft-connolly-cfrg-xwing-kem`, an
/// Independent Submission that CFRG never adopted and that expires on
/// 2026-09-03; cite it for history only. The identity that does not lapse is
/// the IANA code point, plus the CFRG research-group document
/// `draft-irtf-cfrg-concrete-hybrid-kems` section 4.2, which states that its
/// `MLKEM768-X25519` "is identical to the X-Wing construction" and retains the
/// same combiner label for compatibility.
///
/// The IANA registry row still reads **X-Wing** (referencing
/// `draft-connolly-cfrg-xwing-kem-06`). `draft-ietf-hpke-pq` *requests* the
/// rename to `MLKEM768-X25519`, and that request has not been effected, so the
/// code point should not be described as registered under the new name.
///
/// Conformance is checked against the IETF HPKE working group's published
/// `0x647A` vectors — see `test/hpke_wg_kem_vectors.dart`. Go's standard
/// library vendors the same file, so `crypto/hpke.MLKEM768X25519()` is an
/// independent oracle for these bytes.
///
/// Interop note for other implementations: Bouncy Castle has carried X-Wing
/// since 1.78, but releases 1.78 to 1.80 feed the combiner label **first**
/// rather than last and so derive a different shared secret from the same
/// inputs. **1.81 is the floor.** Since X-Wing rejects implicitly, getting this
/// wrong surfaces as an opaque AEAD authentication failure rather than a key
/// error.
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
final class XWingPureDartAlgo with KemSeedMixin implements AtKemAlgorithm {
  static const XWingPureDartAlgo instance = XWingPureDartAlgo._();

  const XWingPureDartAlgo._();

  @override
  int get kemSeedLength => seedLength;

  @override
  String get kemSeedDescription => 'an X-Wing seed';

  static const int seedLength = XWingCore.seedLength;
  static const int publicKeyLength = XWingCore.publicKeyLength;
  static const int ciphertextLength = XWingCore.ciphertextLength;
  static const int sharedSecretLength = XWingCore.sharedSecretLength;

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
    seed ??= newSeed();
    final _Expanded expanded = await _expand(seed);
    final Uint8List publicKey = XWingCore.concatPublicKey(
        expanded.mlKemPublicKey, expanded.x25519Public);
    return (publicKey: publicKey, secretKey: Uint8List.fromList(seed));
  }

  /// For X-Wing this is the same call as [generateKeyPair] with a seed — the
  /// secret key IS the seed — but callers that do not name the backend go
  /// through [keyPairFromSeed], because that identity does not hold for
  /// ML-KEM.
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> keyPairFromValidatedSeed(
          Uint8List seed) =>
      generateKeyPair(seed);

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
    final halves = XWingCore.splitPublicKey(publicKey);

    // The seeded arm is reached only via this backend's own
    // @visibleForTesting encapsulateDerand, so the testing hook is the right
    // callee.
    final (ciphertext: ctM, sharedSecret: ssM) = mlKemRandomness == null
        ? await MlKem768PureDartAlgo.instance.encapsulate(halves.mlKem)
        : await MlKem768PureDartAlgo.instance
            // ignore: invalid_use_of_visible_for_testing_member
            .encapsulateDerand(halves.mlKem, mlKemRandomness);

    final crypto.SimpleKeyPair ephemeral =
        await _x25519.newKeyPairFromSeed(ephemeralX25519Secret);
    final Uint8List ctX =
        Uint8List.fromList((await ephemeral.extractPublicKey()).bytes);
    final Uint8List ssX = await X25519PureDartAlgo.instance
        .dh(ephemeralX25519Secret, halves.x25519);

    return (
      ciphertext: XWingCore.concatCiphertext(ctM, ctX),
      sharedSecret: XWingCore.combine(ssM, ssX, ctX, halves.x25519),
    );
  }

  @override
  Future<Uint8List> decapsulate(
      Uint8List secretKey, Uint8List ciphertext) async {
    XWingCore.checkDecapsulationInputs(secretKey, ciphertext);
    final _Expanded expanded = await _expand(secretKey);
    final ct = XWingCore.splitCiphertext(ciphertext);

    final Uint8List ssM = await MlKem768PureDartAlgo.instance
        .decapsulate(expanded.mlKemSecretKey, ct.mlKem);
    final Uint8List ssX =
        await X25519PureDartAlgo.instance.dh(expanded.x25519Secret, ct.x25519);

    return XWingCore.combine(ssM, ssX, ct.x25519, expanded.x25519Public);
  }

  /// Materialises [XWingCore.expandSeed]'s halves with this backend's
  /// components.
  Future<_Expanded> _expand(Uint8List seed) async {
    final halves = XWingCore.expandSeed(seed);
    final (publicKey: pkM, secretKey: skM) =
        await MlKem768PureDartAlgo.instance.generateKeyPair(halves.mlKemSeed);
    final Uint8List skX = halves.x25519Secret;
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
