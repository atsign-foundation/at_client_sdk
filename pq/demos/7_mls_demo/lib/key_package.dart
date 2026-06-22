import 'dart:convert';
import 'dart:typed_data';

String _b64(Uint8List b) => base64Encode(b);
Uint8List _ub64(String s) => Uint8List.fromList(base64Decode(s));
String? _b64opt(Uint8List? b) => b == null ? null : base64Encode(b);
Uint8List? _ub64opt(String? s) => s == null ? null : Uint8List.fromList(base64Decode(s));

// Public material pre-published by each group member.
class KeyPackage {
  final String deviceId;
  final Uint8List mlDsaPk;     // ML-DSA-65 identity pk (1952 B)
  final Uint8List ikPk;        // X25519 identity key (32 B)
  final Uint8List spkPk;       // X25519 signed prekey (32 B)
  final Uint8List spkSig;      // ML-DSA-65 signature over spkPk
  final Uint8List? opkPk;      // X25519 one-time prekey (nullable — consumed on use)
  final Uint8List pqspkPk;     // X-Wing one-time PQ prekey (1216 B)
  final Uint8List pqspkSig;    // ML-DSA-65 sig over pqspkPk
  final Uint8List leafPk;      // X-Wing PK for TreeKEM leaf (1216 B)

  KeyPackage({
    required this.deviceId,
    required this.mlDsaPk,
    required this.ikPk,
    required this.spkPk,
    required this.spkSig,
    this.opkPk,
    required this.pqspkPk,
    required this.pqspkSig,
    required this.leafPk,
  });

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'mlDsaPk': _b64(mlDsaPk),
    'ikPk': _b64(ikPk),
    'spkPk': _b64(spkPk),
    'spkSig': _b64(spkSig),
    'opkPk': _b64opt(opkPk),
    'pqspkPk': _b64(pqspkPk),
    'pqspkSig': _b64(pqspkSig),
    'leafPk': _b64(leafPk),
  };

  factory KeyPackage.fromJson(Map<String, dynamic> j) => KeyPackage(
    deviceId: j['deviceId'] as String,
    mlDsaPk: _ub64(j['mlDsaPk'] as String),
    ikPk: _ub64(j['ikPk'] as String),
    spkPk: _ub64(j['spkPk'] as String),
    spkSig: _ub64(j['spkSig'] as String),
    opkPk: _ub64opt(j['opkPk'] as String?),
    pqspkPk: _ub64(j['pqspkPk'] as String),
    pqspkSig: _ub64(j['pqspkSig'] as String),
    leafPk: _ub64(j['leafPk'] as String),
  );

  String encode() => jsonEncode(toJson());
  static KeyPackage decode(String s) => KeyPackage.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

// Secret key material for a member's KeyPackage.
class KeyPackageSk {
  final String deviceId;
  final Uint8List mlDsaSk;
  final Uint8List ikSk;        // X25519 identity sk (32 B)
  final Uint8List spkSk;       // X25519 signed prekey sk
  final Uint8List? opkSk;      // X25519 one-time prekey sk (nullable)
  final Uint8List pqspkSk;     // X-Wing PQ prekey sk
  final Uint8List leafSk;      // X-Wing leaf sk for TreeKEM

  KeyPackageSk({
    required this.deviceId,
    required this.mlDsaSk,
    required this.ikSk,
    required this.spkSk,
    this.opkSk,
    required this.pqspkSk,
    required this.leafSk,
  });

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'mlDsaSk': _b64(mlDsaSk),
    'ikSk': _b64(ikSk),
    'spkSk': _b64(spkSk),
    'opkSk': _b64opt(opkSk),
    'pqspkSk': _b64(pqspkSk),
    'leafSk': _b64(leafSk),
  };

  factory KeyPackageSk.fromJson(Map<String, dynamic> j) => KeyPackageSk(
    deviceId: j['deviceId'] as String,
    mlDsaSk: _ub64(j['mlDsaSk'] as String),
    ikSk: _ub64(j['ikSk'] as String),
    spkSk: _ub64(j['spkSk'] as String),
    opkSk: _ub64opt(j['opkSk'] as String?),
    pqspkSk: _ub64(j['pqspkSk'] as String),
    leafSk: _ub64(j['leafSk'] as String),
  );
}

// Full keypair bundle (pk + sk together).
class KeyPackagePair {
  final KeyPackage pub;
  final KeyPackageSk sk;
  KeyPackagePair(this.pub, this.sk);
}
