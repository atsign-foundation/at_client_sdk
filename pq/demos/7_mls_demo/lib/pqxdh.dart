import 'dart:typed_data';
import 'package:pq_demo_6/openssl.dart';
import 'key_package.dart';

// F = 0xFF * 32 (Signal PQXDH domain separator)
final Uint8List _pqxdhF = Uint8List(32)..fillRange(0, 32, 0xff);

Uint8List _concat(List<Uint8List> parts) {
  final total = parts.fold(0, (s, p) => s + p.length);
  final out = Uint8List(total);
  var off = 0;
  for (final p in parts) { out.setAll(off, p); off += p.length; }
  return out;
}

class PqxdhEnvelope {
  final Uint8List ekPk;    // X25519 ephemeral pk (32 B)
  final Uint8List kemCt;   // X-Wing ciphertext (1120 B)

  PqxdhEnvelope(this.ekPk, this.kemCt);
}

// ── A. Join Handshake (Welcome) ────────────────────────────────────────────

// Sender (existing member) generates masterSecret + envelope for joiner.
(Uint8List masterSecret, PqxdhEnvelope envelope) pqxdhSend(
    Crypto c, Uint8List senderIkSk, KeyPackage joiner) {
  final (ekPk, ekSk) = c.x25519.keygen(c.rand);
  final dh1 = c.x25519.sharedSecret(senderIkSk, joiner.spkPk);
  final dh2 = c.x25519.sharedSecret(ekSk, joiner.ikPk);
  final dh3 = c.x25519.sharedSecret(ekSk, joiner.spkPk);
  final dh4 = joiner.opkPk != null
      ? c.x25519.sharedSecret(ekSk, joiner.opkPk!)
      : Uint8List(0);
  final (kemCt, ssKem) = c.xwing.encaps(joiner.pqspkPk);
  final ikm = _concat([_pqxdhF, dh1, dh2, dh3, dh4, ssKem]);
  final masterSecret = c.hkdf.derive(
      Uint8List(32), ikm, Uint8List.fromList('pqxdh-mls-welcome'.codeUnits.toList()), 32);
  return (masterSecret, PqxdhEnvelope(ekPk, kemCt));
}

// Receiver (joiner) recovers masterSecret from envelope.
Uint8List pqxdhReceive(
    Crypto c, KeyPackageSk joinerSk, Uint8List senderIkPk, PqxdhEnvelope env) {
  final dh1 = c.x25519.sharedSecret(joinerSk.spkSk, senderIkPk);
  final dh2 = c.x25519.sharedSecret(joinerSk.ikSk, env.ekPk);
  final dh3 = c.x25519.sharedSecret(joinerSk.spkSk, env.ekPk);
  final dh4 = joinerSk.opkSk != null
      ? c.x25519.sharedSecret(joinerSk.opkSk!, env.ekPk)
      : Uint8List(0);
  final ssKem = c.xwing.decaps(joinerSk.pqspkSk, env.kemCt);
  final ikm = _concat([_pqxdhF, dh1, dh2, dh3, dh4, ssKem]);
  return c.hkdf.derive(
      Uint8List(32), ikm, Uint8List.fromList('pqxdh-mls-welcome'.codeUnits.toList()), 32);
}

// ── B. Cross-Actor Initial Message ────────────────────────────────────────

class PqxdhExternalEnvelope {
  final Uint8List senderIkPk;  // 32 B
  final Uint8List ekPk;        // 32 B
  final Uint8List kemCt;       // 1120 B

  PqxdhExternalEnvelope(this.senderIkPk, this.ekPk, this.kemCt);
}

(Uint8List masterSecret, PqxdhExternalEnvelope envelope) pqxdhExternalSend(
    Crypto c, Uint8List senderIkSk, Uint8List senderIkPk, KeyPackage receiver) {
  final (ekPk, ekSk) = c.x25519.keygen(c.rand);
  final dh1 = c.x25519.sharedSecret(senderIkSk, receiver.spkPk);
  final dh2 = c.x25519.sharedSecret(ekSk, receiver.ikPk);
  final dh3 = c.x25519.sharedSecret(ekSk, receiver.spkPk);
  final dh4 = receiver.opkPk != null
      ? c.x25519.sharedSecret(ekSk, receiver.opkPk!)
      : Uint8List(0);
  final (kemCt, ssKem) = c.xwing.encaps(receiver.pqspkPk);
  final ikm = _concat([_pqxdhF, dh1, dh2, dh3, dh4, ssKem]);
  final masterSecret = c.hkdf.derive(
      Uint8List(32), ikm, Uint8List.fromList('pqxdh-external'.codeUnits.toList()), 32);
  return (masterSecret, PqxdhExternalEnvelope(senderIkPk, ekPk, kemCt));
}

Uint8List pqxdhExternalReceive(
    Crypto c, KeyPackageSk receiverSk, Uint8List senderIkPk, PqxdhExternalEnvelope env) {
  final dh1 = c.x25519.sharedSecret(receiverSk.spkSk, senderIkPk);
  final dh2 = c.x25519.sharedSecret(receiverSk.ikSk, env.ekPk);
  final dh3 = c.x25519.sharedSecret(receiverSk.spkSk, env.ekPk);
  final dh4 = receiverSk.opkSk != null
      ? c.x25519.sharedSecret(receiverSk.opkSk!, env.ekPk)
      : Uint8List(0);
  final ssKem = c.xwing.decaps(receiverSk.pqspkSk, env.kemCt);
  final ikm = _concat([_pqxdhF, dh1, dh2, dh3, dh4, ssKem]);
  return c.hkdf.derive(
      Uint8List(32), ikm, Uint8List.fromList('pqxdh-external'.codeUnits.toList()), 32);
}
