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

  /// How the sweep enumerates this atSign's enrollments — injected so this
  /// class stays independent of the verb wrapper that owns `enroll:list`.
  final Future<List<Enrollment>> Function(
      {EnrollmentListRequestParam? enrollmentListParams}) _listEnrollments;

  /// This client's own privilege — the same injected seam the startup steps
  /// consult.
  ///
  /// ⚠️ **Privilege alone no longer decides which flavour an approval
  /// conveys; possession decides with it.** A fully privileged approver signs
  /// a root link when it holds the signing-root private, a chain link under
  /// its own data signing key when it does not, and nothing at all when it
  /// holds neither. Everyone else signs a chain link — the branch is in
  /// [conveySecretsTo].
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

    // Covers rejected and unsupported alongside absent: whichever way the
    // package is unusable, there is nothing to seal to, and what that means
    // for the approval is the caller's decision, not this class's.
    if (keyPackage == null) return status;

    final sharing = AtClientSecretSharing.forClient(_atClient);

    // Sealing stamps this approver's own key package id on the envelope, so it
    // must hold one. Checked here rather than left to fail inside the
    // substrate: an approver that has never registered otherwise meets a bare
    // `Bad state: register() has not been called` three frames down, having
    // just approved an enrollment that will now never receive its key.
    //
    // Deliberately not registered on its behalf. Registering publishes a key
    // package, and with no persistence wired it mints a fresh seed — so an
    // implicit call could rotate the advertised package underneath the
    // approver and orphan anything already sealed to the old one. When to
    // mint is the caller's decision.
    if (mintedApkamSymmetricKey != null && !sharing.isRegistered) {
      throw AtEnrollmentException(
          'Enrollment ${enrollment.enrollmentId} expects this approver to '
          'convey its symmetric key, but this client has not registered a key '
          'package to seal it from. Call register() on '
          'AtClientSecretSharing.forClient(atClient) before approving.');
    }

    // The symmetric key goes first. Everything else this enrollment is about
    // to receive is useless until it holds the key that unwraps its own
    // encryption private key, and it is blocked in waitForApproval polling for
    // exactly this envelope.
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

    // Vouch for the enrollment this approver has just approved, so a verifier
    // can walk from its key to the atSign's signing root. Conveyed rather
    // than published, because `_apsk` accepts writes only from its own
    // enrollment's connection — this approver is the signer and the child is
    // the only permitted writer, so the child stamps it on first run.
    //
    // The flavour is a THREE-way branch on privilege and possession:
    //
    // - fully privileged and holding the signing-root private — a **root**
    //   link, one hop, verified against the published signing root, so the
    //   enrollment is born anchored;
    // - fully privileged, no root private, but holding a data signing key of
    //   its own — a **chain** link signed with it, which the sweep later
    //   upgrades. Provisional beats absent: nothing re-attempts a link for an
    //   enrollment approved while its approver was unpossessed, so without
    //   this the enrollment stays unsigned until some privileged root-holder
    //   next starts up, which is unbounded for a long-running approver. A
    //   chain link cannot mask a root one — they stamp into distinct `_apsk`
    //   fields and a verifier reads the root field first;
    // - holding neither — **nothing**, and this is the arm that must not
    //   guess. `signingKeys` falls back to the APKAM authentication key when
    //   the enrollment holds no signing key, and that key is *dropped* from
    //   the advertisement rather than retired, so a link signed with it
    //   becomes permanently unverifiable. Silence is the honest outcome.
    //
    // An approver outside the fully privileged class signs a chain link with
    // its own signing keys, as it always has.
    //
    // Best-effort by design: an enrollment whose link never lands is simply
    // unsigned, which verifiers already tolerate during the changeover, and
    // that is a far better outcome than failing an approval that has already
    // happened on the atServer.
    final root = PqSigningRoot(_atClient, keysIo: _atClient.atKeysIo);
    final rootSigner = await root.signingKey(atSign);
    final rootPrivate = rootSigner?.private;

    /// The provisional flavour, signed with whatever signing key this
    /// approver holds. One definition for both arms that convey one, so the
    /// entitled and unentitled cases cannot drift apart in what they stamp.
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

    // A fully privileged enrollment gets the signing root's private half, so
    // it can anchor its own key and vouch for others. Only that class: the
    // root vouches for every enrollment on the atSign, and a namespace-scoped
    // one has no business holding it.
    //
    // Conveyed under a per-enrollment name so shareAllSecretsWith never
    // forwards it on. Without that it would sit in the recipient's store like
    // any other secret and reach the next enrollment that shared its
    // namespace, privileged or not.
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

    // The nskey privates for the approved namespaces, read from AtKeys rather
    // than the in-memory store the next call shares from. The store is a
    // transit buffer: after a restart it holds nothing, so an approver relying
    // on it alone conveys a new enrollment none of the privates without which
    // it cannot read the very namespaces it was just approved for.
    // Best-effort like the chain link: an
    // enrollment this misses heals itself by pulling at its next start.
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
  /// The sweeper's privilege is the caller's gate, and that class signs
  /// **root** links: the private is read from this client's keys, and a
  /// fully privileged client that has not received it yet conveys nothing.
  ///
  /// ⚠️ **That is deliberately not what an APPROVAL does in the same state,
  /// and the difference is what each is for.** An approval is an enrolment's
  /// only chance to be vouched for — nothing re-attempts it — so an approver
  /// holding a data signing key but no root private conveys a chain link
  /// rather than leaving the enrolment unsigned. This sweep exists to reach
  /// enrolments that were missed and to upgrade provisional links to root
  /// anchors, and it runs again at every start of every privileged client, so
  /// a sweeper without the private has simply nothing to do this pass. The
  /// earlier reasoning here — that a chain link from the entitled class would
  /// demote the design rather than bridge it — is retired; it is exactly what
  /// the approval path now does.
  @override
  Future<int> sweepUnanchoredEnrollments() async {
    final sharing = AtClientSecretSharing.forClient(_atClient);
    if (!sharing.isRegistered) {
      // Sealing a conveyance stamps this client's own key package id, so an
      // unregistered sweeper cannot convey anything it signs.
      _logger.info('Not sweeping root links: this client has no registered '
          'key package to seal conveyances from');
      return 0;
    }

    // Possession is checked before the roster fetch because it is a local
    // AtKeys read where the fetch costs a round trip — and without the
    // private there is nothing this sweep may sign.
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

    final ownEnrollmentId =
        _atClient.getRemoteSecondary()?.atLookUp.enrollmentId;

    final approved = await _listEnrollments(
        enrollmentListParams: EnrollmentListRequestParam()
          ..enrollmentListFilter = [EnrollmentStatus.approved]);

    final chain = PqSigningChain(_atClient);
    int conveyed = 0;
    for (final enrollment in approved) {
      final id = enrollment.enrollmentId;
      if (id == null || id == ownEnrollmentId) continue;
      try {
        // Root-anchored is the terminal state. A chain link alone does NOT
        // skip: it is provisional, and upgrading it to a root anchor is as
        // much this sweep's job as anchoring the unsigned.
        if (await chain.readRootLink(id) != null) continue;

        // No key package, no conveyance channel: a legacy enrollment cannot
        // receive a link and has no PQ key for one to vouch for.
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
        // One enrollment failing must not stop the sweep; it is retried at
        // every privileged start.
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
  /// which rules out `__manage` (a device enrollment is not granted it) and
  /// `*` (not a namespace the key can live in). The atServer requires every
  /// new-client request to name at least one namespace, so there is always a
  /// candidate.
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
