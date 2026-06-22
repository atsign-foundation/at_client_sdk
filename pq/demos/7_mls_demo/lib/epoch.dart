import 'dart:typed_data';
import 'package:pq_demo_6/openssl.dart' show HmacSha256;
import 'mls_crypto.dart';

class EpochSecrets {
  final Uint8List senderDataSecret;
  final Uint8List encryptionSecret;    // seeds SecretTree
  final Uint8List exporterSecret;
  final Uint8List authenticationSecret;
  final Uint8List initSecret;          // carries forward-secrecy to next epoch
  final Uint8List resumptionPsk;
  final Uint8List membershipKey;
  final Uint8List externalHpkeSk;     // X25519 sk for external commits, derived from epochSecret

  EpochSecrets({
    required this.senderDataSecret,
    required this.encryptionSecret,
    required this.exporterSecret,
    required this.authenticationSecret,
    required this.initSecret,
    required this.resumptionPsk,
    required this.membershipKey,
    required this.externalHpkeSk,
  });
}

// RFC 9420 §8.1
EpochSecrets deriveEpochSecrets(
    HmacSha256 hmac, Uint8List initSecret, Uint8List commitSecret, Uint8List groupContextBytes) {
  // joinerSecret = ExpandWithLabel(Extract(initSecret, commitSecret), "joiner", groupContext, 32)
  final prk = hkdfExtract(hmac, initSecret, commitSecret);
  final joinerSecret = expandWithLabel(hmac, prk, 'joiner', groupContextBytes, 32);
  final memberSecret = deriveSecret(hmac, joinerSecret, 'member');
  final epochSecret = deriveSecret(hmac, memberSecret, 'epoch');

  return EpochSecrets(
    senderDataSecret: deriveSecret(hmac, epochSecret, 'sender data'),
    encryptionSecret: deriveSecret(hmac, epochSecret, 'encryption'),
    exporterSecret: deriveSecret(hmac, epochSecret, 'exporter'),
    authenticationSecret: deriveSecret(hmac, epochSecret, 'authentication'),
    initSecret: deriveSecret(hmac, epochSecret, 'init'),
    resumptionPsk: deriveSecret(hmac, epochSecret, 'resumption'),
    membershipKey: deriveSecret(hmac, epochSecret, 'membership'),
    externalHpkeSk: deriveSecret(hmac, epochSecret, 'external'),
  );
}

// Welcome key derivation (from joinerSecret)
(Uint8List key, Uint8List nonce) deriveWelcomeKey(HmacSha256 hmac, Uint8List joinerSecret) {
  final welcomeSecret = deriveSecret(hmac, joinerSecret, 'welcome');
  final key = expandWithLabel(hmac, welcomeSecret, 'key', Uint8List(0), 32);
  final nonce = expandWithLabel(hmac, welcomeSecret, 'nonce', Uint8List(0), 12);
  return (key, nonce);
}

// Compute joinerSecret from init_secret + commitSecret (needed for Welcome)
Uint8List computeJoinerSecret(HmacSha256 hmac, Uint8List initSecret, Uint8List commitSecret) {
  final prk = hkdfExtract(hmac, initSecret, commitSecret);
  return expandWithLabel(hmac, prk, 'joiner', Uint8List(0), 32);
}
