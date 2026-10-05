import 'dart:convert';
import 'package:meta/meta.dart';

import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart'
    show NskeySeeding;
import 'package:at_client/src/enroll/at_sign_credential.dart';
import 'package:at_client/src/enroll/authorised_namespaces.dart'
    show accessIn, isSeedableNamespace, mayWriteIn;
import 'package:at_client/src/enroll/enrollment_conveyance.dart';
import 'package:at_client/src/enroll/privilege_resolver.dart'
    show EnrollmentPrivilegeResolver, isFullyPrivileged;
import 'package:at_client/src/mixins/at_client_envelope_signer.dart';
import 'package:at_client/src/response/enrollment.dart';
import 'package:at_client/src/secret_sharing/secret_sharing.dart';
import 'package:at_client/src/secret_sharing/enrollment_directory.dart'
    show readAdvertisedKeyPackage;
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

  /// How many times the advertised key package is checked before a check
  /// that could not be completed is reported, and the pause between checks.
  /// The atServer writes the enrollment's `_apsk` at approval, so the first
  /// fetch can land before it is readable.
  @visibleForTesting
  static int verifyAttempts = 3;
  @visibleForTesting
  static Duration verifyRetryPause = const Duration(seconds: 1);

  @override
  Future<void> conveyMintedApkamSymmetricKey(
      Enrollment pending, String apkamSymmetricKey) async {
    // NOTE: sealing stamps this approver's own key package id on the envelope,
    // so it must hold one — and it is deliberately not registered on its
    // behalf. With no persistence wired, register() mints a fresh seed, so an
    // implicit call would rotate the advertised package underneath the
    // approver and orphan anything already sealed to the old one.
    final sharing = AtClientSecretSharing.forClient(_atClient);
    if (!sharing.isRegistered) {
      throw AtEnrollmentException(
          'Enrollment ${pending.enrollmentId} expects this approver to '
          'convey its symmetric key, but this client has not registered a key '
          'package to seal it from. Call register() on '
          'AtClientSecretSharing.forClient(atClient) before approving.');
    }
    final (package, status) = readAdvertisedKeyPackage(
        pending.metadata?['keyPackage'],
        enrollmentId: pending.enrollmentId!);
    // NOTE: refused before the approval, which is spent once it lands: a
    // package that is not one can never be sealed to, so approving would
    // authorise a device that can never decrypt anything and no later
    // approval would repair it. A package this version merely cannot READ is
    // a version skew and approves as it always did.
    if (status == KeyPackageStatus.rejected) {
      throw AtEnrollmentException(
          'Enrollment ${pending.enrollmentId} advertised a key package that '
          'is not one, so its symmetric key cannot be sealed to anything. It '
          'stays pending: approve it once the enrolling device advertises a '
          'package that can be read.');
    }
    if (package == null) return;
    await sharing.shareSecretWith(
        package,
        Secret(
          namespace: await _conveyanceNamespaceFor(pending),
          name: enrollmentApkamSymmetricKeySecretName,
          value: apkamSymmetricKey,
        ),
        inReplyTo: EnvelopeAddressing.unsolicited);
  }

  /// Seals every secret [enrollment]'s namespaces authorise to the key package
  /// it advertised on its `enroll:request`, so the newly approved device can
  /// read what it has just been authorised for.
  ///
  /// Runs **after** the approval, because the atServer publishes the
  /// enrollment's `_apsk` at that point and the package cannot be verified
  /// before it exists.
  @override
  Future<KeyPackageStatus> conveySecretsTo(Enrollment enrollment) async {
    final advertised = enrollment.metadata?['keyPackage'];
    if (advertised == null) return KeyPackageStatus.absent;

    final atSign = _atClient.getCurrentAtSign()!;
    var (keyPackage, status) = await verifyAdvertisedKeyPackage(
      advertised,
      signer: AtClientEnvelopeSigner(_atClient),
      signerAtSign: atSign,
      enrollmentId: enrollment.enrollmentId!,
    );
    for (var attempt = 1;
        status == KeyPackageStatus.unverified &&
            attempt < verifyAttempts &&
            !_atClient.isStopped;
        attempt++) {
      await Future<void>.delayed(verifyRetryPause);
      (keyPackage, status) = await verifyAdvertisedKeyPackage(
        advertised,
        signer: AtClientEnvelopeSigner(_atClient),
        signerAtSign: atSign,
        enrollmentId: enrollment.enrollmentId!,
      );
    }

    if (keyPackage == null) return status;
    final KeyPackage package = keyPackage;

    final sharing = AtClientSecretSharing.forClient(_atClient);
    late final envelopeNamespace = _conveyanceNamespaceFor(enrollment);

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
            package,
            Secret(
              namespace: await envelopeNamespace,
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
              package,
              Secret(
                namespace: await envelopeNamespace,
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
            package,
            Secret(
              namespace: await envelopeNamespace,
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
        ).conveyHeldPrivatesTo(package, enrollment.namespace ?? const {},
            ownGrants: await _ownGrants());
        if (sent > 0) {
          _logger.info('Conveyed $sent held nskey private(s) to enrollment '
              '${enrollment.enrollmentId}');
        }
      } catch (e) {
        if (e is StoppedException) rethrow;
        _logger.warning('Could not convey held nskey privates to enrollment '
            '${enrollment.enrollmentId}; it can pull them at its next start: '
            '$e');
      }
    }

    await sharing.shareAllSecretsWith(package,
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
          'published signing-root private yet; its next start pulls or '
          'publishes one first');
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
              namespace: await _conveyanceNamespaceFor(enrollment),
              name: PqSigningChain.rootLinkSecretName,
              value: PqSigningChain.encodeLink(link),
            ),
            inReplyTo: EnvelopeAddressing.unsolicited);
        conveyed++;
      } catch (e) {
        if (e is StoppedException) rethrow;
        _logger.warning('Could not sweep a root link for enrollment $id: $e');
      }
    }
    if (conveyed > 0) {
      _logger.info('Swept root links to $conveyed unanchored enrollment(s); '
          'each stamps its own _apsk at its next start');
    }
    return conveyed;
  }

  /// A namespace [enrollment] may read and this approver may write, for an
  /// envelope addressed to it.
  ///
  /// The envelope is a key in an ordinary namespace, so the atServer's
  /// namespace gating decides both who may write it and who may fetch it.
  /// Tried in order: the namespaces [enrollment] was granted, this client's
  /// `preference.namespace`, then the namespaces this client was granted — so
  /// an enrollment granted only `*` fetches it from the approver's namespace.
  /// Throws when none qualifies.
  Future<String> _conveyanceNamespaceFor(Enrollment enrollment) async {
    final granted = enrollment.namespace ?? const <String, dynamic>{};
    final own = await _ownGrants();
    final preferred = _atClient.getPreferences()?.namespace;
    final candidates = [
      ...granted.keys,
      if (preferred != null) preferred,
      ...?own?.keys,
    ].where(isSeedableNamespace);
    for (final namespace in candidates) {
      if (accessIn(granted, namespace) == null) continue;
      if (!mayWriteIn(own, namespace)) continue;
      return namespace;
    }
    throw AtEnrollmentException(
        'Enrollment ${enrollment.enrollmentId} may read no namespace this '
        'approver may write, so there is nowhere to put the envelopes '
        'addressed to it. Give this approver a preference.namespace the '
        'enrollment is granted.');
  }

  /// The namespaces this client's own enrollment was granted, or null when it
  /// may write anywhere or its record cannot be found.
  ///
  /// The atSign's own credential has no record and no limit; for a record the
  /// list does not carry, the atServer's refusal of the write is what reports
  /// a namespace this client may not write.
  Future<Map<String, dynamic>?> _ownGrants() async {
    final enrollmentId = _atClient.enrollmentId;
    if (isAtSignCredential(enrollmentId)) return null;
    final approved = await _listEnrollments(
        enrollmentListParams: EnrollmentListRequestParam()
          ..enrollmentListFilter = [EnrollmentStatus.approved]);
    for (final enrollment in approved) {
      if (enrollment.enrollmentId == enrollmentId) {
        return enrollment.namespace ?? const {};
      }
    }
    return null;
  }
}
