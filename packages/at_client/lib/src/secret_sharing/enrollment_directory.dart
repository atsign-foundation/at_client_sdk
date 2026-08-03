import 'dart:convert' show jsonDecode;

import 'package:at_client/at_client.dart' show AtClient;
import 'package:at_client/src/mixins/at_client_envelope_signer.dart';
import 'package:at_client/src/secret_sharing/key_package.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('VerbEnrollmentDirectory');

/// One enrollment authorised for a namespace, as returned by
/// [EnrollmentDirectory.listForNamespace]: its access level and the key
/// package of its APKAM keypair.
///
/// Enrollment cardinality is **1:1:1** — one enrollment has exactly one APKAM
/// keypair and therefore exactly one key package — so each member has exactly
/// one [keyPackage] (null if the enrollment advertised none).
@experimental
class NamespaceMember {
  final String enrollmentId;

  /// The access level the atServer reports for this enrollment on the queried
  /// namespace (e.g. `r`, `rw`). A holder of read access still receives the
  /// key — reading the data requires it.
  final String access;

  /// This enrollment's single key package, or null if it advertised none
  /// (1:1:1).
  final KeyPackage? keyPackage;

  NamespaceMember({
    required this.enrollmentId,
    required this.access,
    this.keyPackage,
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
/// enrollment's `enroll:request`). The enrollment's single key package lives
/// directly under `metadata.keyPackage` (the payload itself — no format-id
/// sub-key):
///
/// **The key package is an APKAM-signed envelope**, so `metadata.keyPackage`
/// holds `{payload, signature, signingAlgo, hashingAlgo, enrollmentId}` and the
/// package itself is the `payload`. It is verified here, against the advertising
/// enrollment's `_apsk`, before the key inside is ever treated as that
/// enrollment's — a key package *is* an encapsulation target, so accepting one
/// on the server's word alone would let whoever served the enrollment record
/// choose who can read the atSign's secrets.
///
///     enroll:listns:<ns>
///       -> data:[{"enrollmentId":..,"access":"rw","apkamPubKey":..,
///                 "metadata":{"keyPackage":{
///                   "payload":{"v":1,"createdAt":..,"keys":[..]},
///                   "signature":..,"signingAlgo":..,"hashingAlgo":..,
///                   "enrollmentId":..}}}]
@experimental
class VerbEnrollmentDirectory implements EnrollmentDirectory {
  final AtClient atClient;

  final AtClientEnvelopeSigner _signer;

  VerbEnrollmentDirectory(this.atClient)
      : _signer = AtClientEnvelopeSigner(atClient);

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
      final apkamPubKey = e['apkamPubKey'];
      final metadata = e['metadata'];
      members.add(NamespaceMember(
        enrollmentId: enrollmentId,
        access: access,
        keyPackage: metadata is Map
            ? await _verifiedKeyPackage(
                metadata['keyPackage'],
                enrollmentId: enrollmentId,
                apkamId: apkamPubKey is String ? apkamPubKey : null,
              )
            : null,
      ));
    }
    return members;
  }

  /// The key package inside [advertised], if its APKAM signature checks out as
  /// [enrollmentId]'s; null otherwise.
  ///
  /// A rejection drops **this member only**, rather than failing the whole
  /// listing. The member is then simply never sealed to — fail-closed for the
  /// enrollment whose advertisement is bad, and no worse for anyone else. The
  /// alternative, throwing, would let a single unparseable record deny every
  /// other enrollment its secrets.
  ///
  /// The distinction that matters is between an enrollment that advertised
  /// **nothing** — ordinary, it has not registered — and one whose
  /// advertisement is present but will not verify. The first is silent; the
  /// second is shouted about, because it is either an attack on the
  /// encapsulation target or a bug, and neither should be inferred from a
  /// member that quietly stops receiving secrets.
  Future<KeyPackage?> _verifiedKeyPackage(
    Object? advertised, {
    required String enrollmentId,
    String? apkamId,
  }) async {
    if (advertised == null) return null;
    if (advertised is! Map) {
      _logger.severe('enrollment $enrollmentId advertised a key package that '
          'is not a map; not sealing to it');
      return null;
    }

    // The envelope names its own signer, and the record names whose enrollment
    // it is advertised under. If those disagree, one enrollment is offering a
    // key package as another's — which would hand it every secret meant for
    // that other enrollment.
    final signer = advertised['enrollmentId'];
    if (signer != enrollmentId) {
      _logger.severe('enrollment $enrollmentId advertised a key package signed '
          'by ${signer ?? "nobody"}; not sealing to it');
      return null;
    }

    try {
      await _signer.verifyEnvelopeSignature(advertised,
          signerAtSign: atClient.getCurrentAtSign()!);
    } catch (e) {
      _logger.severe('the key package advertised by enrollment $enrollmentId '
          'does not verify against its _apsk, so the key it offers is only as '
          'trustworthy as whatever served it; not sealing to it: $e');
      return null;
    }

    try {
      return KeyPackage.fromPayload(
        advertised['payload'],
        enrollmentId: enrollmentId,
        apkamId: apkamId,
      );
    } catch (e) {
      // Signed, so genuinely this enrollment's, but shaped in a way this
      // version cannot read — most likely written by a newer client.
      _logger.info('enrollment $enrollmentId advertised a signed key package '
          'this version cannot parse: $e');
      return null;
    }
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
