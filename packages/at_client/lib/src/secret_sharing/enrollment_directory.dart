import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:at_client/at_client.dart' show AtClient;
import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:at_client/src/secret_sharing/key_package.dart';
import 'package:meta/meta.dart' show experimental;

/// One enrollment authorised for a namespace, as returned by
/// [EnrollmentDirectory.listForNamespace]: its access level and the key
/// packages of every APKAM keypair it has registered.
///
/// An enrollment can expose several [keyPackages] — one per APKAM keypair
/// (the keyfile copied to another device mints its own). A sender seals once
/// per key package, so every client sharing the enrollment receives the
/// secret.
@experimental
class NamespaceMember {
  final String enrollmentId;

  /// The access level the atServer reports for this enrollment on the queried
  /// namespace (e.g. `r`, `rw`). A holder of read access still receives the
  /// key — reading the data requires it.
  final String access;

  /// One [KeyPackage] per APKAM keypair of this enrollment that advertised one.
  final List<KeyPackage> keyPackages;

  NamespaceMember({
    required this.enrollmentId,
    required this.access,
    required this.keyPackages,
  });
}

/// The atServer-backed directory of per-APKAM key packages.
///
/// Discovery and storage of key packages live behind this seam so the
/// secret-sharing substrate above it is independent of the wire protocol and
/// fully unit-testable with a fake. The concrete [VerbEnrollmentDirectory]
/// talks to the gated `enroll:listfornamespace` verb and the enrollment
/// record; tests substitute their own implementation.
@experimental
abstract class EnrollmentDirectory {
  /// The enrollments authorised for [namespace] (the caller's own enrollment
  /// must hold at least read access — the atServer gates the verb), each with
  /// the per-APKAM key packages to seal to. [excludeEnrollmentIds] drops
  /// revoked enrollments before they ever enter a roster.
  Future<List<NamespaceMember>> listForNamespace(
    String namespace, {
    Set<String> excludeEnrollmentIds = const {},
  });

  /// Records [keyPackage] in this client's enrollment record (filed by the
  /// atServer under whichever APKAM keypair authenticated the write), so peers
  /// discover it via [listForNamespace]. Idempotent.
  Future<void> registerKeyPackage(KeyPackage keyPackage);
}

/// [EnrollmentDirectory] backed by the atServer's `enroll:listfornamespace`
/// verb and enrollment-record metadata.
///
/// **Wire shape (assumed):** the server stores an opaque `metadata` JSON map
/// per APKAM keypair and returns it verbatim — it has no opinion on the
/// contents, only on the auth info it needs to verify PKAM. Key packages live
/// in `metadata.keyPackages`, a map keyed by key-package format id
/// ([SecretSharingAlgos.keyPackageType]) so formats can evolve without server
/// changes:
///
///     enroll:listfornamespace:<ns>
///       -> data:[{"enrollmentId":..,"access":"rw",
///                 "apkam":[{"apkamId":..,"apkamPubKey":..,
///                           "metadata":{"keyPackages":{"x-wing-v1":{..}}}}]}]
@experimental
class VerbEnrollmentDirectory implements EnrollmentDirectory {
  final AtClient atClient;

  VerbEnrollmentDirectory(this.atClient);

  @override
  Future<List<NamespaceMember>> listForNamespace(
    String namespace, {
    Set<String> excludeEnrollmentIds = const {},
  }) async {
    final String? raw = await atClient
        .getRemoteSecondary()
        ?.executeCommand('enroll:listfornamespace:$namespace\n', auth: true);
    final decoded = _data(raw);
    if (decoded is! List) {
      return const [];
    }
    final members = <NamespaceMember>[];
    for (final e in decoded) {
      if (e is! Map) continue;
      final enrollmentId = e['enrollmentId'];
      final access = e['access'];
      if (enrollmentId is! String || access is! String) continue;
      if (excludeEnrollmentIds.contains(enrollmentId)) continue;
      final apkams = e['apkam'];
      final keyPackages = <KeyPackage>[];
      if (apkams is List) {
        for (final a in apkams) {
          if (a is! Map) continue;
          final apkamId = a['apkamId'];
          final metadata = a['metadata'];
          if (metadata is! Map) continue;
          final pkgs = metadata['keyPackages'];
          if (pkgs is! Map) continue;
          final payload = pkgs[SecretSharingAlgos.keyPackageType];
          if (payload == null) continue;
          try {
            keyPackages.add(KeyPackage.fromPayload(
              payload,
              enrollmentId: enrollmentId,
              apkamId: apkamId is String ? apkamId : null,
            ));
          } catch (_) {
            // skip a malformed/unknown-format package; a newer client may
            // have written one this version doesn't understand
          }
        }
      }
      members.add(NamespaceMember(
        enrollmentId: enrollmentId,
        access: access,
        keyPackages: keyPackages,
      ));
    }
    return members;
  }

  @override
  Future<void> registerKeyPackage(KeyPackage keyPackage) async {
    // The server stores the metadata opaquely under the authenticating APKAM
    // keypair; the substrate's format lives under `keyPackages.<format-id>`.
    final metadata = jsonEncode({
      'keyPackages': {SecretSharingAlgos.keyPackageType: keyPackage.toJson()}
    });
    await atClient.getRemoteSecondary()?.executeCommand(
        'enroll:metadata:${atClient.enrollmentId}:$metadata\n',
        auth: true);
  }

  /// Strips the at-protocol `data:` prefix and JSON-decodes a verb response.
  static Object? _data(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    final body = trimmed.startsWith('data:')
        ? trimmed.substring('data:'.length)
        : trimmed;
    if (body.isEmpty) return null;
    return jsonDecode(body);
  }
}
