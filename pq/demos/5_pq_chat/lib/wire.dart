// On-the-wire message envelope. JSON-encoded as the inbox row's value.
//
// Fields:
//   dhPk       always present — sender's current DH ratchet PK
//   kemPk      optional — present when sender just rotated their KEM keypair
//   kemCt      optional — present when this message is a KEM ratchet step (carries Encaps result)
//   nonce      AES-GCM nonce
//   ct         AES-GCM ciphertext (length = plaintext length)
//   mac        AES-GCM authentication tag (16B)
//   msgN       sender's message counter within their current send chain
//   isInit     true only on the initiator's very first message
//   initEphPk, initIkPk, initKemCt  PQXDH init payload (only when isInit)

import 'dart:convert';
import 'dart:typed_data';
import 'crypto.dart' show toHex, fromHex;

class WireMessage {
  final Uint8List dhPk;
  final Uint8List? kemPk;
  final Uint8List? kemCt;
  final Uint8List nonce;
  final Uint8List ct;
  final Uint8List mac;
  final int msgN;
  final bool isInit;
  final Uint8List? initEphPk;
  final Uint8List? initIkPk;
  final Uint8List? initKemCt;

  WireMessage({
    required this.dhPk,
    required this.nonce,
    required this.ct,
    required this.mac,
    required this.msgN,
    this.kemPk,
    this.kemCt,
    this.isInit = false,
    this.initEphPk,
    this.initIkPk,
    this.initKemCt,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'dhPk': toHex(dhPk),
      'nonce': toHex(nonce),
      'ct': toHex(ct),
      'mac': toHex(mac),
      'msgN': msgN,
      'isInit': isInit,
    };
    if (kemPk != null) m['kemPk'] = toHex(kemPk!);
    if (kemCt != null) m['kemCt'] = toHex(kemCt!);
    if (initEphPk != null) m['initEphPk'] = toHex(initEphPk!);
    if (initIkPk != null) m['initIkPk'] = toHex(initIkPk!);
    if (initKemCt != null) m['initKemCt'] = toHex(initKemCt!);
    return m;
  }

  factory WireMessage.fromJson(Map<String, dynamic> j) {
    Uint8List? opt(String k) {
      final v = j[k] as String?;
      return v == null ? null : fromHex(v);
    }

    return WireMessage(
      dhPk: fromHex(j['dhPk'] as String),
      nonce: fromHex(j['nonce'] as String),
      ct: fromHex(j['ct'] as String),
      mac: fromHex(j['mac'] as String),
      msgN: j['msgN'] as int,
      isInit: j['isInit'] as bool? ?? false,
      kemPk: opt('kemPk'),
      kemCt: opt('kemCt'),
      initEphPk: opt('initEphPk'),
      initIkPk: opt('initIkPk'),
      initKemCt: opt('initKemCt'),
    );
  }

  String toEncoded() => jsonEncode(toJson());

  static WireMessage fromEncoded(String s) =>
      WireMessage.fromJson(jsonDecode(s) as Map<String, dynamic>);

  int get sizeBytes =>
      dhPk.length +
      (kemPk?.length ?? 0) +
      (kemCt?.length ?? 0) +
      nonce.length +
      ct.length +
      mac.length +
      4 + 1 +
      (initEphPk?.length ?? 0) +
      (initIkPk?.length ?? 0) +
      (initKemCt?.length ?? 0);
}
