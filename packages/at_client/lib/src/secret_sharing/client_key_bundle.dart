import 'dart:convert' show utf8;

import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:crypto/crypto.dart' show sha256;

/// One public key advertised in a [ClientKeyBundle].
///
/// [kid] is a short identifier for the key (a SHA-256 prefix of [pub]) which
/// envelopes use to say which of the recipient's keys was used. [alg] is an
/// algorithm id from [SecretSharingAlgos]; readers skip entries whose [alg]
/// or [use] they do not recognise, which is what lets bundles advertise new
/// suites without breaking old readers.
class BundleKey {
  final String kid;
  final String use;
  final String alg;
  final String pub;

  BundleKey({
    required this.use,
    required this.alg,
    required this.pub,
    String? kid,
  }) : kid = kid ?? computeKid(pub);

  /// First 8 bytes, hex-encoded, of the SHA-256 of the public key material.
  static String computeKid(String pub) {
    final digest = sha256.convert(utf8.encode(pub));
    return digest.bytes
        .take(8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Map<String, Object?> toJson() => {
        'kid': kid,
        'use': use,
        'alg': alg,
        'pub': pub,
      };

  static BundleKey? fromJson(Object? json) {
    if (json is! Map) return null;
    final kid = json['kid'];
    final use = json['use'];
    final alg = json['alg'];
    final pub = json['pub'];
    if (kid is! String || use is! String || alg is! String || pub is! String) {
      return null;
    }
    return BundleKey(kid: kid, use: use, alg: alg, pub: pub);
  }
}

/// The set of public keys a client publishes so that other clients of the
/// same atSign can share secrets with it.
///
/// A bundle is identified by ([clientId], [enrollmentId]): clientIds are
/// per-client random ids, and several clients may be running against the
/// same enrollment. Bundles are signed (see EnvelopeSigning) with the
/// enrollment's APKAM key, and published in the enrollment's reserved
/// namespace, which only that enrollment may write to.
class ClientKeyBundle {
  static const int currentVersion = 1;

  final int v;
  final String clientId;
  final String enrollmentId;
  final DateTime createdAt;
  final List<BundleKey> keys;

  ClientKeyBundle({
    required this.clientId,
    required this.enrollmentId,
    required this.createdAt,
    required this.keys,
    this.v = currentVersion,
  });

  /// The first key in [supportedAlgos] order (strongest first) that this
  /// bundle advertises for [use]. Returns null if the bundle and
  /// [supportedAlgos] have no algorithm in common.
  BundleKey? bestKeyFor(List<String> supportedAlgos,
      {String use = SecretSharingAlgos.useEnc}) {
    for (final alg in supportedAlgos) {
      for (final key in keys) {
        if (key.alg == alg && key.use == use) {
          return key;
        }
      }
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'v': v,
        'clientId': clientId,
        'enrollmentId': enrollmentId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'keys': keys.map((k) => k.toJson()).toList(),
      };

  /// Parses a bundle, skipping malformed entries in `keys` rather than
  /// throwing — a bundle written by a newer client may carry key entries
  /// (or extra fields) this version does not understand.
  ///
  /// Throws [FormatException] if the fields this version does require are
  /// missing or of the wrong type.
  static ClientKeyBundle fromJson(Object? json) {
    if (json is! Map) {
      throw FormatException('ClientKeyBundle: expected a Map, got $json');
    }
    final v = json['v'];
    final clientId = json['clientId'];
    final enrollmentId = json['enrollmentId'];
    final createdAt = json['createdAt'];
    final keys = json['keys'];
    if (v is! int ||
        clientId is! String ||
        enrollmentId is! String ||
        createdAt is! String ||
        keys is! List) {
      throw FormatException('ClientKeyBundle: malformed bundle $json');
    }
    return ClientKeyBundle(
      v: v,
      clientId: clientId,
      enrollmentId: enrollmentId,
      createdAt: DateTime.parse(createdAt),
      keys: keys.map(BundleKey.fromJson).whereType<BundleKey>().toList(),
    );
  }
}
