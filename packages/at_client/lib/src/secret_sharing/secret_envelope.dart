import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:at_client/src/secret_sharing/key_package.dart';
import 'package:meta/meta.dart' show experimental;

/// The encrypted payload one client of an atSign sends to another (addressed
/// to a specific APKAM keypair). The whole envelope is additionally wrapped in
/// an APKAM signature (see EnvelopeSigning) which receivers verify before
/// decrypting.
///
/// The sealing-suite id ([suite]) and recipient key id ([kid]) are explicit
/// for crypto agility: today [sealed] is an at_chops `pqSeal` envelope (KEM
/// encapsulation + AEAD over an HKDF key schedule, suite per the envelope's
/// version byte); a future suite changes the id, not the schema.
@experimental
class SecretEnvelope {
  static const int currentVersion = 1;

  final int v;

  /// The sender's key-package id ([KeyPackage.kpid]) — so the recipient of a
  /// request can seal its reply straight back to this APKAM keypair.
  final String fromKpid;

  /// The sender's enrollment (the envelope is APKAM-signed by it).
  final String fromEnrollmentId;

  /// The recipient key-package id ([KeyPackage.kpid]) this envelope is
  /// addressed to. Routes the envelope (it is the `<kpid>` segment of the
  /// envelope key name) and is what the recipient checks against its own
  /// kpid.
  final String toKpid;

  /// Which sealing suite produced [sealed]; an id from
  /// [SecretSharingAlgos.suites].
  final String suite;

  /// Which of the recipient's advertised [PackageKey]s [sealed] was sealed to.
  /// Equals [toKpid] today (a key package advertises one enc key); kept
  /// distinct for crypto agility (a future package may advertise several).
  final String kid;

  /// The sealed payload (an at_chops `pqSeal` wire envelope — KEM
  /// encapsulation, AEAD ciphertext and tag), base64.
  final String sealed;

  SecretEnvelope({
    required this.fromKpid,
    required this.fromEnrollmentId,
    required this.toKpid,
    required this.suite,
    required this.kid,
    required this.sealed,
    this.v = currentVersion,
  });

  Map<String, Object?> toJson() => {
        'v': v,
        'from': {
          'kpid': fromKpid,
          'enrollmentId': fromEnrollmentId,
        },
        'to': toKpid,
        'suite': suite,
        'kid': kid,
        'sealed': sealed,
      };

  static SecretEnvelope fromJson(Object? json) {
    if (json is! Map) {
      throw FormatException('SecretEnvelope: expected a Map, got $json');
    }
    final v = json['v'];
    final from = json['from'];
    final to = json['to'];
    final suite = json['suite'];
    final kid = json['kid'];
    final sealed = json['sealed'];
    if (v is! int ||
        from is! Map ||
        from['kpid'] is! String ||
        from['enrollmentId'] is! String ||
        to is! String ||
        suite is! String ||
        kid is! String ||
        sealed is! String) {
      throw FormatException('SecretEnvelope: malformed envelope $json');
    }
    return SecretEnvelope(
      v: v,
      fromKpid: from['kpid'],
      fromEnrollmentId: from['enrollmentId'],
      toKpid: to,
      suite: suite,
      kid: kid,
      sealed: sealed,
    );
  }
}
