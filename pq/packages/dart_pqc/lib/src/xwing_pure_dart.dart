import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/digests/sha3.dart';

import 'dart_pqc_base.dart';
import 'ml_kem_768.dart';

// X-Wing KEM — draft-connolly-cfrg-xwing-kem-06.
// Pure-Dart fallback: ML-KEM-768 via pqcrypto, X25519 via package:cryptography,
// SHA3-256 via pointycastle (transitive dep, no new explicit dep needed).
//
// Key layout (identical to XWingFfi — byte-level compatible):
//   PK  (1216 B): ML-KEM-768 pk (1184) || X25519 pk (32)
//   SK  (2464 B): ML-KEM-768 sk (2400) || X25519 sk (32) || X25519 pk (32)
//   CT  (1120 B): ML-KEM-768 ct (1088) || X25519 ephemeral pk (32)
//   SS  (  32 B): SHA3-256(LABEL || ssM || ssX || ctX || pkX)
//   LABEL = [0x5C, 0x2E, 0x2F, 0x2F, 0x5E, 0x5C]

const int _mlKemPkLen = 1184;
const int _mlKemSkLen = 2400;
const int _mlKemCtLen = 1088;

/// X-Wing KEM backed by pure Dart.
///
/// Use [instance] for the singleton, or [XWingPureDart.new] for an isolated instance.
final class XWingPureDart implements XWingAlgorithm {
  static const XWingPureDart instance = XWingPureDart._();

  const XWingPureDart._();

  static final MlKem768PureDart _mlKem = MlKem768PureDart.instance;
  static final X25519 _x25519 = X25519();

  static final Uint8List _label =
      Uint8List.fromList(const [0x5C, 0x2E, 0x2F, 0x2F, 0x5E, 0x5C]);

  // ── Key sizes ──────────────────────────────────────────────────────────────

  static const int pkBytes = 1216;
  static const int skBytes = 2464;
  static const int ctBytes = 1120;
  static const int ssBytes = 32;

  // ── XWingAlgorithm ─────────────────────────────────────────────────────────

  @override
  Future<PqcKeyPair> generateKeyPair([Uint8List? seed96]) async {
    if (seed96 != null && seed96.length != 96) {
      throw ArgumentError('X-Wing seed must be 96 bytes (got ${seed96.length})');
    }

    // ML-KEM-768 leg
    final Uint8List? mlKemSeed =
        seed96 != null ? Uint8List.sublistView(seed96, 0, 64) : null;
    final PqcKeyPair mlKemKp = await _mlKem.generateKeyPair(mlKemSeed);
    final Uint8List pkM = mlKemKp.publicKey; // 1184 B
    final Uint8List skM = mlKemKp.secretKey; // 2400 B

    // X25519 leg
    Uint8List pkX, skX;
    if (seed96 != null) {
      final Uint8List x25519Seed = Uint8List.sublistView(seed96, 64, 96);
      final SimpleKeyPair kp = await _x25519.newKeyPairFromSeed(x25519Seed);
      final SimplePublicKey pub = await kp.extractPublicKey();
      final List<int> priv = await kp.extractPrivateKeyBytes();
      pkX = Uint8List.fromList(pub.bytes);
      skX = Uint8List.fromList(priv);
    } else {
      final SimpleKeyPair kp = await _x25519.newKeyPair();
      final SimplePublicKey pub = await kp.extractPublicKey();
      final List<int> priv = await kp.extractPrivateKeyBytes();
      pkX = Uint8List.fromList(pub.bytes);
      skX = Uint8List.fromList(priv);
    }

    final Uint8List pk = Uint8List(pkBytes);
    pk.setAll(0, pkM);
    pk.setAll(_mlKemPkLen, pkX);

    final Uint8List sk = Uint8List(skBytes);
    sk.setAll(0, skM);
    sk.setAll(_mlKemSkLen, skX);
    sk.setAll(_mlKemSkLen + 32, pkX);

    return PqcKeyPair(publicKey: pk, secretKey: sk);
  }

  @override
  Future<EncapsulationResult> encaps(Uint8List publicKey) async {
    if (publicKey.length != pkBytes) {
      throw ArgumentError(
          'X-Wing pk must be $pkBytes bytes (got ${publicKey.length})');
    }
    final Uint8List pkM = Uint8List.sublistView(publicKey, 0, _mlKemPkLen);
    final Uint8List pkX = Uint8List.sublistView(publicKey, _mlKemPkLen);

    // ML-KEM encaps
    final EncapsulationResult mlRes = await _mlKem.encapsulate(pkM);
    final Uint8List ctM = mlRes.ciphertext; // 1088 B
    final Uint8List ssM = mlRes.sharedSecret; // 32 B

    // X25519 ephemeral: ctX = eph_pk, ssX = DH(eph_sk, pkX)
    final SimpleKeyPair ephKp = await _x25519.newKeyPair();
    final SimplePublicKey ephPub = await ephKp.extractPublicKey();
    final List<int> ephPriv = await ephKp.extractPrivateKeyBytes();
    final Uint8List ctX = Uint8List.fromList(ephPub.bytes); // 32 B
    final Uint8List ssX = await _dhRaw(
        Uint8List.fromList(ephPriv), Uint8List.fromList(pkX));

    final Uint8List ss = _combine(ssM, ssX, ctX, pkX);

    final Uint8List ct = Uint8List(ctBytes);
    ct.setAll(0, ctM);
    ct.setAll(_mlKemCtLen, ctX);

    return EncapsulationResult(ciphertext: ct, sharedSecret: ss);
  }

  @override
  Future<Uint8List> decaps(Uint8List secretKey, Uint8List ciphertext) async {
    if (secretKey.length != skBytes) {
      throw ArgumentError(
          'X-Wing sk must be $skBytes bytes (got ${secretKey.length})');
    }
    if (ciphertext.length != ctBytes) {
      throw ArgumentError(
          'X-Wing ct must be $ctBytes bytes (got ${ciphertext.length})');
    }

    final Uint8List skM =
        Uint8List.sublistView(secretKey, 0, _mlKemSkLen);
    final Uint8List skX =
        Uint8List.sublistView(secretKey, _mlKemSkLen, _mlKemSkLen + 32);
    final Uint8List pkX =
        Uint8List.sublistView(secretKey, _mlKemSkLen + 32);
    final Uint8List ctM = Uint8List.sublistView(ciphertext, 0, _mlKemCtLen);
    final Uint8List ctX = Uint8List.sublistView(ciphertext, _mlKemCtLen);

    final Uint8List ssM = await _mlKem.decapsulate(skM, ctM);
    final Uint8List ssX = await _dhRaw(skX, ctX);

    return _combine(ssM, ssX, ctX, pkX);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<Uint8List> _dhRaw(Uint8List sk, Uint8List peerPk) async {
    final SimpleKeyPairData kp = SimpleKeyPairData(
      sk,
      publicKey: SimplePublicKey(const [], type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    final SimplePublicKey peer =
        SimplePublicKey(peerPk, type: KeyPairType.x25519);
    final SecretKey ss =
        await _x25519.sharedSecretKey(keyPair: kp, remotePublicKey: peer);
    return Uint8List.fromList(await ss.extractBytes());
  }

  Uint8List _combine(
      Uint8List ssM, Uint8List ssX, Uint8List ctX, Uint8List pkX) {
    final Uint8List buf = Uint8List(
        _label.length + ssM.length + ssX.length + ctX.length + pkX.length);
    var o = 0;
    buf.setAll(o, _label);
    o += _label.length;
    buf.setAll(o, ssM);
    o += ssM.length;
    buf.setAll(o, ssX);
    o += ssX.length;
    buf.setAll(o, ctX);
    o += ctX.length;
    buf.setAll(o, pkX);
    // SHA3-256 via pointycastle (synchronous, no allocation overhead)
    return SHA3Digest(256).process(buf);
  }
}
