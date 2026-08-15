import 'dart:convert' show jsonDecode;

import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/mixins/at_client_envelope_signer.dart';
import 'package:at_client/src/secret_sharing/key_package.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show EnvelopeType, SignedEnvelope;
import 'package:at_commons/at_commons.dart'
    show AtSigningVerificationException;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('VerbEnrollmentDirectory');

/// Why a [NamespaceMember] has no usable key package — or that it has one.
///
/// A null `keyPackage` on its own cannot be acted on, because these outcomes
/// call for opposite responses and only one of them is a problem anybody can
/// fix. Distinguishing them is what lets a caller carry on quietly in the
/// ordinary cases and refuse loudly in the one that matters.
@experimental
enum KeyPackageStatus {
  /// Present and verified — safe to seal to.
  present,

  /// The enrollment advertised none. Expected: an older client, or the
  /// self-retrofit path, which needs no conveyance at all. Not an error.
  absent,

  /// Advertised and **refused** — not a map, signed by a different enrollment
  /// than the record it appears on, or a signature that does not verify
  /// against that enrollment's `_apsk`. Either a bug or an attempt to make
  /// this atSign's secrets readable by the wrong key, and in both cases
  /// something a caller should refuse rather than skip.
  rejected,

  /// Signed, and genuinely this enrollment's, but shaped in a way this version
  /// cannot read — almost always a package written by a **newer** client.
  /// Nothing is wrong and nobody can fix it from here, so it behaves like
  /// [absent] rather than [rejected]: refusing would block work purely because
  /// the other end is ahead of us.
  unsupported,
}

/// One enrollment authorised for a namespace, as returned by
/// [EnrollmentDirectory.listForNamespace]: its access level and the key
/// package of its APKAM keypair.
///
/// Enrollment cardinality is **1:1:1** — one enrollment has exactly one APKAM
/// keypair and therefore exactly one key package — so each member has exactly
/// one [keyPackage] (null unless [keyPackageStatus] is
/// [KeyPackageStatus.present]).
@experimental
class NamespaceMember {
  final String enrollmentId;

  /// The access level the atServer reports for this enrollment on the queried
  /// namespace (e.g. `r`, `rw`). A holder of read access still receives the
  /// key — reading the data requires it.
  final String access;

  /// This enrollment's single key package, or null if there is no usable one
  /// (1:1:1). [keyPackageStatus] says why.
  final KeyPackage? keyPackage;

  /// Whether this member has a usable key package, and if not, why not.
  final KeyPackageStatus keyPackageStatus;

  NamespaceMember({
    required this.enrollmentId,
    required this.access,
    this.keyPackage,
    KeyPackageStatus? keyPackageStatus,
  }) : keyPackageStatus = keyPackageStatus ??
            (keyPackage == null
                ? KeyPackageStatus.absent
                : KeyPackageStatus.present);
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
      final (keyPackage, status) = metadata is Map
          ? await _verifiedKeyPackage(
              metadata['keyPackage'],
              enrollmentId: enrollmentId,
              apkamId: apkamPubKey is String ? apkamPubKey : null,
            )
          : (null, KeyPackageStatus.absent);
      members.add(NamespaceMember(
        enrollmentId: enrollmentId,
        access: access,
        keyPackage: keyPackage,
        keyPackageStatus: status,
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
  Future<(KeyPackage?, KeyPackageStatus)> _verifiedKeyPackage(
    Object? advertised, {
    required String enrollmentId,
    String? apkamId,
  }) =>
      verifyAdvertisedKeyPackage(
        advertised,
        signer: _signer,
        signerAtSign: atClient.getCurrentAtSign()!,
        enrollmentId: enrollmentId,
        apkamId: apkamId,
      );
}

/// Verifies an advertised key package against the `_apsk` of the enrollment
/// whose record carries it, and says why if it is unusable.
///
/// Shared by the discovery verb and the approval path, which see the same
/// advertisement from different directions — the roster, and the enrollment
/// request being approved. One copy, because two would be two chances to
/// disagree about which key is authoritative.
///
/// A rejection concerns **this advertisement only** and never throws, so a
/// caller listing a roster can drop one member and keep the rest: the
/// alternative would let a single bad record deny every other enrollment its
/// secrets.
@experimental
Future<(KeyPackage?, KeyPackageStatus)> verifyAdvertisedKeyPackage(
  Object? advertised, {
  required AtClientEnvelopeSigner signer,
  required String signerAtSign,
  required String enrollmentId,
  String? apkamId,
}) async {
  if (advertised == null) return (null, KeyPackageStatus.absent);
  if (advertised is! Map) {
    _logger.severe('enrollment $enrollmentId advertised a key package that '
        'is not a map; not sealing to it');
    return (null, KeyPackageStatus.rejected);
  }
  final SignedEnvelope envelope;
  try {
    envelope = SignedEnvelope.fromJson(advertised);
  } on AtSigningVerificationException catch (e) {
    _logger.severe('enrollment $enrollmentId advertised a key package that is '
        'not a signed envelope; not sealing to it: $e');
    return (null, KeyPackageStatus.rejected);
  }

  // The record names whose enrollment this is, and that is what the _apsk
  // lookup goes on. A package may also name its own signer; if it does and
  // the two disagree, one enrollment is offering a key package as another's
  // — which would hand it every secret meant for that other enrollment.
  //
  // A package that names nobody is not suspicious: one riding
  // `enroll:request` is signed before the atServer has assigned an id, so
  // there is nothing truthful to stamp. Its authority is the signature
  // checking out against this record's own _apsk, plus the record binding
  // the package to the request that created it.
  // Named `claimedSigner`, not `signer`: that is the AtClientEnvelopeSigner
  // parameter, and a Map lookup is dynamic, so shadowing it compiles happily
  // and then fails at runtime on every verification.
  final String? claimedSigner = envelope.signerEnrollmentId;
  if (claimedSigner != null && claimedSigner != enrollmentId) {
    _logger.severe('enrollment $enrollmentId advertised a key package signed '
        'by $claimedSigner; not sealing to it');
    return (null, KeyPackageStatus.rejected);
  }

  try {
    await signer.verifyEnvelopeSignature(envelope,
        signerAtSign: signerAtSign,
        signerEnrollmentId: enrollmentId,
        expecting: EnvelopeType.keyPackage);
  } catch (e) {
    _logger.severe('the key package advertised by enrollment $enrollmentId '
        'does not verify against its _apsk, so the key it offers is only as '
        'trustworthy as whatever served it; not sealing to it: $e');
    return (null, KeyPackageStatus.rejected);
  }

  try {
    return (
      KeyPackage.fromPayload(
        envelope.payload,
        enrollmentId: enrollmentId,
        apkamId: apkamId,
      ),
      KeyPackageStatus.present
    );
  } catch (e) {
    // Signed, so genuinely this enrollment's, but shaped in a way this
    // version cannot read — most likely written by a newer client. Nobody
    // here can fix that, so it is not a refusal.
    _logger.info('enrollment $enrollmentId advertised a signed key package '
        'this version cannot parse: $e');
    return (null, KeyPackageStatus.unsupported);
  }
}

/// Strips the at-protocol `data:` prefix and JSON-decodes a verb response.
Object? _data(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  final body =
      trimmed.startsWith('data:') ? trimmed.substring('data:'.length) : trimmed;
  if (body.isEmpty) return null;
  return jsonDecode(body);
}
