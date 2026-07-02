import 'dart:convert' show jsonDecode;

import 'package:at_client/at_client.dart' show AtClient;
import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:at_client/src/secret_sharing/key_package.dart';
import 'package:meta/meta.dart' show experimental;

/// One enrollment authorised for a namespace, as returned by
/// [EnrollmentDirectory.listForNamespace]: its access level and the key
/// package of its APKAM keypair.
///
/// Enrollment cardinality is **1:1:1** — one enrollment has exactly one APKAM
/// keypair and therefore exactly one key package — so [keyPackages] holds at
/// most one element (empty if the enrollment advertised none). It is kept a
/// list only so a sender can iterate uniformly; a sender seals once per key
/// package, reaching the enrollment.
@experimental
class NamespaceMember {
  final String enrollmentId;

  /// The access level the atServer reports for this enrollment on the queried
  /// namespace (e.g. `r`, `rw`). A holder of read access still receives the
  /// key — reading the data requires it.
  final String access;

  /// This enrollment's key package(s): 0 or 1 element under 1:1:1.
  final List<KeyPackage> keyPackages;

  NamespaceMember({
    required this.enrollmentId,
    required this.access,
    required this.keyPackages,
  });
}

/// The atServer-backed directory of per-enrollment key packages.
///
/// Discovery of key packages lives behind this seam so the secret-sharing
/// substrate above it is independent of the wire protocol and fully
/// unit-testable with a fake. The concrete [VerbEnrollmentDirectory] talks to
/// the gated `enroll:listns` verb; tests substitute their own implementation.
///
/// There is no registration method: a key package is conveyed into its
/// enrollment record by riding `enroll:request` as opaque
/// `EnrollParams.metadata` at enrollment time (there is no post-enrollment
/// metadata write, and no `enroll:metadata` verb).
@experimental
abstract class EnrollmentDirectory {
  /// The enrollments authorised for [namespace] (the caller's own enrollment
  /// must hold at least read access — the atServer gates the verb), each with
  /// the key package to seal to. [excludeEnrollmentIds] drops revoked
  /// enrollments before they ever enter a roster.
  Future<List<NamespaceMember>> listForNamespace(
    String namespace, {
    Set<String> excludeEnrollmentIds = const {},
  });
}

/// [EnrollmentDirectory] backed by the atServer's `enroll:listns` verb.
///
/// **Wire shape:** the server returns one flat record per approved enrollment
/// authorised for the namespace (1:1:1 — no nested `apkam[]` array). Each
/// record carries the enrollment's access level, its single APKAM public key,
/// and its opaque `metadata` map (stored verbatim by the server from the
/// enrollment's `enroll:request`). Key packages live in `metadata.keyPackages`,
/// a map keyed by key-package format id ([SecretSharingAlgos.keyPackageType])
/// so formats can evolve without server changes:
///
///     enroll:listns:<ns>
///       -> data:[{"enrollmentId":..,"access":"rw","apkamPubKey":..,
///                 "metadata":{"keyPackages":{"x-wing-v1":{..}}}}]
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
        ?.executeCommand('enroll:listns:$namespace\n', auth: true);
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
      final keyPackages = <KeyPackage>[];
      final apkamPubKey = e['apkamPubKey'];
      final metadata = e['metadata'];
      if (metadata is Map) {
        final pkgs = metadata['keyPackages'];
        if (pkgs is Map) {
          final payload = pkgs[SecretSharingAlgos.keyPackageType];
          if (payload != null) {
            try {
              keyPackages.add(KeyPackage.fromPayload(
                payload,
                enrollmentId: enrollmentId,
                apkamId: apkamPubKey is String ? apkamPubKey : null,
              ));
            } catch (_) {
              // skip a malformed/unknown-format package; a newer client may
              // have written one this version doesn't understand
            }
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
