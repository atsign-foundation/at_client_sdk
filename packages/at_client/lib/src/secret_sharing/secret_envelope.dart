import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:at_client/src/secret_sharing/client_key_bundle.dart';

/// The encrypted payload one client sends to another client of the same
/// atSign. The whole envelope is additionally wrapped in an APKAM signature
/// (see EnvelopeSigning) which receivers verify before decrypting.
///
/// Algorithm ids ([keyAlg], [encAlg]) and the recipient key id ([kid]) are
/// explicit for crypto agility: today [encryptedKey] holds an X-Wing KEM
/// encapsulation ciphertext (the encapsulated shared secret is the content
/// key) and [encAlg] is AES-256-GCM; a future suite changes the ids, not
/// the schema.
class SecretEnvelope {
  static const int currentVersion = 1;

  final int v;
  final String fromClientId;
  final String fromEnrollmentId;

  /// The recipient's clientId.
  final String to;

  /// How [encryptedKey] protects the content key; an id from
  /// [SecretSharingAlgos.keyAlgos].
  final String keyAlg;

  /// Which of the recipient's published [BundleKey]s was used.
  final String kid;

  /// The content key, protected per [keyAlg].
  final String encryptedKey;

  /// How [ciphertext] was produced from the payload; an id from
  /// [SecretSharingAlgos.encAlgos].
  final String encAlg;

  /// Initialisation vector for [encAlg], base64.
  final String iv;

  /// The encrypted payload, base64.
  final String ciphertext;

  SecretEnvelope({
    required this.fromClientId,
    required this.fromEnrollmentId,
    required this.to,
    required this.keyAlg,
    required this.kid,
    required this.encryptedKey,
    required this.encAlg,
    required this.iv,
    required this.ciphertext,
    this.v = currentVersion,
  });

  Map<String, Object?> toJson() => {
        'v': v,
        'from': {
          'clientId': fromClientId,
          'enrollmentId': fromEnrollmentId,
        },
        'to': to,
        'keyAlg': keyAlg,
        'kid': kid,
        'encryptedKey': encryptedKey,
        'encAlg': encAlg,
        'iv': iv,
        'ciphertext': ciphertext,
      };

  static SecretEnvelope fromJson(Object? json) {
    if (json is! Map) {
      throw FormatException('SecretEnvelope: expected a Map, got $json');
    }
    final v = json['v'];
    final from = json['from'];
    final to = json['to'];
    final keyAlg = json['keyAlg'];
    final kid = json['kid'];
    final encryptedKey = json['encryptedKey'];
    final encAlg = json['encAlg'];
    final iv = json['iv'];
    final ciphertext = json['ciphertext'];
    if (v is! int ||
        from is! Map ||
        from['clientId'] is! String ||
        from['enrollmentId'] is! String ||
        to is! String ||
        keyAlg is! String ||
        kid is! String ||
        encryptedKey is! String ||
        encAlg is! String ||
        iv is! String ||
        ciphertext is! String) {
      throw FormatException('SecretEnvelope: malformed envelope $json');
    }
    return SecretEnvelope(
      v: v,
      fromClientId: from['clientId'],
      fromEnrollmentId: from['enrollmentId'],
      to: to,
      keyAlg: keyAlg,
      kid: kid,
      encryptedKey: encryptedKey,
      encAlg: encAlg,
      iv: iv,
      ciphertext: ciphertext,
    );
  }
}
