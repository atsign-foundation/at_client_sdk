import 'dart:convert';

import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart'
    show NskeySeeding;
import 'package:at_client/src/enroll/enrollment_conveyance.dart';
import 'package:at_client/src/enroll/privilege_resolver.dart'
    show EnrollmentPrivilegeResolver, isFullyPrivileged;
import 'package:at_client/src/mixins/at_client_envelope_signer.dart';
import 'package:at_client/src/response/enrollment.dart';
import 'package:at_client/src/secret_sharing/secret_sharing.dart';
import 'package:at_client/src/secret_sharing/envelope_addressing.dart'
    show EnvelopeAddressing;
import 'package:at_client/src/util/enroll_list_request_param.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;

final _logger = AtSignLogger('EnvelopeEnrollmentConveyance');

/// The production [EnrollmentConveyance]: seals every secret into the
/// secret-sharing substrate's envelopes, addressed to the enrollment's
/// advertised key package.
class EnvelopeEnrollmentConveyance implements EnrollmentConveyance {
  EnvelopeEnrollmentConveyance(this._atClient,
      {required Future<List<Enrollment>> Function(
              {EnrollmentListRequestParam? enrollmentListParams})
          listEnrollments,
      required EnrollmentPrivilegeResolver privilege})
      : _listEnrollments = listEnrollments,
        _privilege = privilege;

  final AtClient _atClient;

  final Future<List<Enrollment>> Function(
      {EnrollmentListRequestParam? enrollmentListParams}) _listEnrollments;

  /// This client's own privilege, not that of the enrollment it is approving.
  final EnrollmentPrivilegeResolver _privilege;

  /// Seals every secret [enrollment]'s namespaces authorise to the key package
  /// it advertised on its `enroll:request`, so the newly approved device can
  /// read what it has just been authorised for.
  ///
  /// Runs **after** the approval, because the atServer publishes the
  /// enrollment's `_apsk` at that point and the package cannot be verified
  /// before it exists.
  @override
  Future<KeyPackageStatus> conveySecretsTo(Enrollment enrollment,
      {String? mintedApkamSymmetricKey}) async {
    final advertised = enrollment.metadata?['keyPackage'];
    if (advertised == null) return KeyPackageStatus.absent;

    final atSign = _atClient.getCurrentAtSign()!;
    final (keyPackage, status) = await verifyAdvertisedKeyPackage(
      advertised,
      signer: AtClientEnvelopeSigner(_atClient),
      signerAtSign: atSign,
      enrollmentId: enrollment.enrollmentId!,
    );

    if (keyPackage == null) return status;

    final sharing = AtClientSecretSharing.forClient(_atClient);

    // NOTE: sealing stamps this approver's own key package id on the envelope,
    // so it must hold one — and it is deliberately not registered on its
    // behalf. With no persistence wired, register() mints a fresh seed, so an
    // implicit call would rotate the advertised package underneath the
    // approver and orphan anything already sealed to the old one.
    if (mintedApkamSymmetricKey != null && !sharing.isRegistered) {
      throw AtEnrollmentException(
          'Enrollment ${enrollment.enrollmentId} expects this approver to '
          'convey its symmetric key, but this client has not registered a key '
          'package to seal it from. Call register() on '
          'AtClientSecretSharing.forClient(atClient) before approving.');
    }

    // NOTE: the symmetric key goes first. Everything else is useless until the
    // enrollment holds the key that unwraps its own encryption private key,
    // and it is blocked in waitForApproval polling for exactly this envelope.
    if (mintedApkamSymmetricKey != null) {
      await sharing.shareSecretWith(
          keyPackage,
          Secret(
            namespace: _conveyanceNamespaceFor(enrollment),
            name: enrollmentApkamSymmetricKeySecretName,
            value: mintedApkamSymmetricKey,
          ),
          inReplyTo: EnvelopeAddressing.unsolicited);
    }

    // NOTE: the link vouching for this enrollment is conveyed rather than
    // published, because `_apsk` accepts writes only from its own
    // enrollment's connection, so the child stamps it on first run. An
    // approver holding neither the signing-root private nor a data signing key
    // of its own conveys no link at all: `signingKeys` falls back to the APKAM
    // authentication key, which is dropped from the advertisement rather than
    // retired, so a link signed with it becomes permanently unverifiable.
    final root = PqSigningRoot(_atClient, keysIo: _atClient.atKeysIo);
    final rootSigner = await root.signingKey(atSign);
    final rootPrivate = rootSigner?.private;

    /// The provisional link, signed with whatever signing key this approver
    /// holds.
    Future<void> conveyChainLink() async {
      final link = await PqSigningChain(_atClient)
          .signLinkFor(sharing, enrollment.enrollmentId!);
      if (link != null) {
        await sharing.shareSecretWith(
            keyPackage,
            Secret(
              namespace: _conveyanceNamespaceFor(enrollment),
              name: PqSigningChain.linkSecretName,
              value: PqSigningChain.encodeLink(link.toJson()),
            ),
            inReplyTo: EnvelopeAddressing.unsolicited);
      }
    }

    if (await _privilege.isFullyPrivileged()) {
      if (rootPrivate != null) {
        final link = await PqSigningChain(_atClient).signRootLinkFor(
            enrollment.enrollmentId!,
            rootPrivate: rootPrivate,
            rootKid: rootSigner!.kid);
        if (link != null) {
          await sharing.shareSecretWith(
              keyPackage,
              Secret(
                namespace: _conveyanceNamespaceFor(enrollment),
                name: PqSigningChain.rootLinkSecretName,
                value: PqSigningChain.encodeLink(link),
              ),
              inReplyTo: EnvelopeAddressing.unsolicited);
        }
      } else if ((await sharing.heldSigningKeys).isNotEmpty) {
        await conveyChainLink();
      } else {
        _logger.info('Not conveying a link for ${enrollment.enrollmentId}: '
            'this fully privileged approver holds neither the signing-root '
            'private nor a data signing key of its own, and a link signed '
            'with the APKAM authentication key would stop verifying the '
            'moment that key leaves the advertisement');
      }
    } else {
      await conveyChainLink();
    }

    // NOTE: the signing root's private half goes only to a fully privileged
    // enrollment, and under a per-enrollment name so shareAllSecretsWith never
    // forwards it on to the next enrollment sharing that namespace.
    if (isFullyPrivileged(enrollment.namespace)) {
      final private = rootPrivate;
      if (private != null) {
        await sharing.shareSecretWith(
            keyPackage,
            Secret(
              namespace: _conveyanceNamespaceFor(enrollment),
              name: PqSigningRoot.secretName,
              value: base64Encode(private),
            ),
            inReplyTo: EnvelopeAddressing.unsolicited);
      }
    }

    // NOTE: the nskey privates come from AtKeys, not the in-memory store the
    // next call shares from. That store is a transit buffer and holds nothing
    // after a restart, so an approver relying on it alone conveys none of the
    // privates the enrollment needs to read what it was just approved for.
    final keysIo = _atClient.atKeysIo;
    if (keysIo != null) {
      try {
        final filing = NskeyPrivateFiling(keysIo: keysIo, atSign: atSign);
        final sent = await NskeySeeding(
          atClient: _atClient,
          ring: PublishedNskeyKeyRing(_atClient, privateFiling: filing),
          sharing: sharing,
          privateFiling: filing,
        ).conveyHeldPrivatesTo(
            keyPackage, enrollment.namespace?.keys ?? const []);
        if (sent > 0) {
          _logger.info('Conveyed $sent held nskey private(s) to enrollment '
              '${enrollment.enrollmentId}');
        }
      } catch (e) {
        _logger.warning('Could not convey held nskey privates to enrollment '
            '${enrollment.enrollmentId}; it can pull them at its next start: '
            '$e');
      }
    }

    await sharing.shareAllSecretsWith(keyPackage,
        approvedNamespaces: enrollment.namespace);

    return status;
  }

  /// The anchoring sweep — see
  /// [EnrollmentConveyance.sweepUnanchoredEnrollments] for why it exists and
  /// who may run it.
  ///
  /// Signs **root** links only, from a private read out of this client's
  /// keys: a client that has not received that private conveys nothing this
  /// pass, and the sweep runs again at every privileged start.
  @override
  Future<int> sweepUnanchoredEnrollments() async {
    final sharing = AtClientSecretSharing.forClient(_atClient);
    if (!sharing.isRegistered) {
      _logger.info('Not sweeping root links: this client has no registered '
          'key package to seal conveyances from');
      return 0;
    }

    final atSign = _atClient.getCurrentAtSign()!;
    final rootSigner =
        await PqSigningRoot(_atClient, keysIo: _atClient.atKeysIo)
            .signingKey(atSign);
    if (rootSigner == null) {
      _logger.warning('Not sweeping root links: this client holds no '
          'signing-root private yet; the pull at its next start heals '
          'possession first');
      return 0;
    }

    final ownEnrollmentId = _atClient.enrollmentId;

    final approved = await _listEnrollments(
        enrollmentListParams: EnrollmentListRequestParam()
          ..enrollmentListFilter = [EnrollmentStatus.approved]);

    final chain = PqSigningChain(_atClient);
    int conveyed = 0;
    for (final enrollment in approved) {
      final id = enrollment.enrollmentId;
      if (id == null || id == ownEnrollmentId) continue;
      try {
        // NOTE: only a root anchor is terminal. A chain link alone does not
        // skip — it is provisional, and upgrading it is as much this sweep's
        // job as anchoring the unsigned.
        if (await chain.readRootLink(id) != null) continue;

        final advertised = enrollment.metadata?['keyPackage'];
        if (advertised == null) continue;
        final (keyPackage, status) = await verifyAdvertisedKeyPackage(
          advertised,
          signer: AtClientEnvelopeSigner(_atClient),
          signerAtSign: atSign,
          enrollmentId: id,
        );
        if (keyPackage == null || status == KeyPackageStatus.rejected) {
          continue;
        }

        final link = await chain.signRootLinkFor(id,
            rootPrivate: rootSigner.private, rootKid: rootSigner.kid);
        if (link == null) continue;
        await sharing.shareSecretWith(
            keyPackage,
            Secret(
              namespace: _conveyanceNamespaceFor(enrollment),
              name: PqSigningChain.rootLinkSecretName,
              value: PqSigningChain.encodeLink(link),
            ),
            inReplyTo: EnvelopeAddressing.unsolicited);
        conveyed++;
      } catch (e) {
        _logger.warning('Could not sweep a root link for enrollment $id: $e');
      }
    }
    if (conveyed > 0) {
      _logger.info('Swept root links to $conveyed unanchored enrollment(s); '
          'each stamps its own _apsk at its next start');
    }
    return conveyed;
  }

  /// A namespace this enrollment is authorised to read, for the envelope
  /// carrying its symmetric key.
  ///
  /// The envelope is a self key in an app namespace, so the atServer's
  /// namespace gating decides whether the enrollment can fetch it at all —
  /// which rules out `__manage` and `*`. Throws when the enrollment is
  /// authorised for no ordinary namespace.
  String _conveyanceNamespaceFor(Enrollment enrollment) {
    final granted = (enrollment.namespace?.keys ?? const <String>[])
        .where((ns) => ns != '*' && ns != '__manage');
    if (granted.isEmpty) {
      throw AtEnrollmentException(
          'Enrollment ${enrollment.enrollmentId} is authorised for no ordinary '
          'namespace, so there is nowhere to put the envelope carrying its '
          'symmetric key that it would be allowed to read.');
    }
    return granted.first;
  }
}
