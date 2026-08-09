import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show AtChopsUtil, EncryptionKeyType;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart'
    show NskeySeeding;
import 'package:at_commons/at_builders.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;

final _logger = AtSignLogger('EnrollmentServiceImpl');

class EnrollmentServiceImpl implements EnrollmentService {
  final AtClient _atClient;
  final AtEnrollment _atEnrollmentImpl;

  EnrollmentServiceImpl(this._atClient, this._atEnrollmentImpl);

  @override
  Future<List<Enrollment>> fetchEnrollmentRequests(
      {EnrollmentListRequestParam? enrollmentListParams}) async {
    EnrollVerbBuilder enrollBuilder = EnrollVerbBuilder()
      ..operation = EnrollOperationEnum.list
      ..appName = enrollmentListParams?.appName
      ..deviceName = enrollmentListParams?.deviceName
      ..enrollmentStatusFilter = enrollmentListParams?.enrollmentListFilter;

    String? response = await _atClient
        .getRemoteSecondary()!
        .executeCommand(enrollBuilder.buildCommand(), auth: true);

    return _formatEnrollListResponse(response!);
  }

  String extractEnrollmentId(String enrollmentKey) {
    return enrollmentKey.split('.')[0];
  }

  List<Enrollment> _formatEnrollListResponse(String response) {
    response = response.replaceFirst(RegExp('^data:'), '');
    Map<String, dynamic> enrollRequests = jsonDecode(response);
    List<Enrollment> enrollRequestsFormatted = [];
    for (MapEntry enrollmentRequest in enrollRequests.entries) {
      Enrollment enrollmentRequestResponse =
          Enrollment.fromJSON(enrollmentRequest.value);
      enrollmentRequestResponse.enrollmentId =
          extractEnrollmentId(enrollmentRequest.key);
      enrollRequestsFormatted.add(enrollmentRequestResponse);
    }
    return enrollRequestsFormatted;
  }

  /// Seals every secret [enrollment]'s namespaces authorise to the key package
  /// it advertised on its `enroll:request`, so the newly approved device can
  /// read what it has just been authorised for.
  ///
  /// Runs **after** the approval, because the atServer publishes the
  /// enrollment's `_apsk` at that point and the package cannot be verified
  /// before it exists.
  ///
  /// Throws when a package was advertised and **refused** — the approver
  /// should learn that it has just approved a device that will be unable to
  /// decrypt anything, and can revoke. An enrollment that advertised nothing,
  /// or something this version cannot read, is left alone: the first is
  /// ordinary during rollout and for the self-retrofit path, and neither is
  /// anything the approver can fix.
  Future<void> _shareSecretsWith(Enrollment enrollment,
      {String? mintedApkamSymmetricKey}) async {
    final advertised = enrollment.metadata?['keyPackage'];
    if (advertised == null) return;

    final atSign = _atClient.getCurrentAtSign()!;
    final (keyPackage, status) = await verifyAdvertisedKeyPackage(
      advertised,
      signer: AtClientEnvelopeSigner(_atClient),
      signerAtSign: atSign,
      enrollmentId: enrollment.enrollmentId!,
    );

    if (status == KeyPackageStatus.rejected) {
      throw AtEnrollmentException(
          'Enrollment ${enrollment.enrollmentId} is approved, but the key '
          'package it advertised does not verify against its _apsk, so no '
          'secrets were shared with it and it will be unable to decrypt '
          'anything. Revoke it unless this is understood.');
    }
    if (keyPackage == null) return;

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
          ));
    }

    // Vouch for the enrollment this approver has just approved, so a verifier
    // can walk from its key up to the atSign's signing root. Conveyed rather
    // than published, because `_apsk` accepts writes only from its own
    // enrollment's connection — this approver is the signer and the child is
    // the only permitted writer, so the child stamps it on first run.
    //
    // Best-effort by design: an enrollment whose link never lands is simply
    // unsigned, which verifiers already tolerate during the changeover, and
    // that is a far better outcome than failing an approval that has already
    // happened on the atServer.
    final link = await PqSigningChain.signLinkFor(
        _atClient, sharing, enrollment.enrollmentId!);
    if (link != null) {
      await sharing.shareSecretWith(
          keyPackage,
          Secret(
            namespace: _conveyanceNamespaceFor(enrollment),
            name: PqSigningChain.linkSecretName,
            value: PqSigningChain.encodeLink(link),
          ));
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
      final root = PqSigningRoot(_atClient, keysIo: _atClient.atKeysIo);
      final private = await root.privateHalf(atSign);
      if (private != null) {
        await sharing.shareSecretWith(
            keyPackage,
            Secret(
              namespace: _conveyanceNamespaceFor(enrollment),
              name: PqSigningRoot.secretName,
              value: base64Encode(private),
            ));
      }
    }

    // The nskey privates for the approved namespaces, read from AtKeys rather
    // than the in-memory store the next call shares from. The store is a
    // transit buffer: after a restart it holds nothing, so an approver relying
    // on it alone conveys a new enrollment none of the privates without which
    // it cannot read the very namespaces it was just approved for — the
    // conveyance hole of decisions.md 38. Best-effort like the chain link: an
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
  }

  /// Signs and conveys approval-chain links for approved enrollments that
  /// lack one — the chain sweep of `decisions.md` 38, decision 3.
  ///
  /// A scoped enrollment can never anchor itself (not fully privileged —
  /// correctly), and its approver is often the legacy parent enrollment,
  /// which can sign nothing. Left alone, *chained-but-unanchored is its
  /// permanent state*, costing the defence-in-depth the chain exists for. A
  /// fully privileged client is the one party that can repair that, so it
  /// sweeps: every approved enrollment with a discoverable key package and no
  /// published link gets one signed and conveyed. The enrollment stamps it
  /// onto its own `_apsk` at its next start (`publishPendingLink`) — this
  /// client cannot stamp it directly, because `_apsk` accepts writes only
  /// from its own enrollment's connection, and that restriction is the very
  /// guarantee the chain hangs off.
  ///
  /// The caller is responsible for privilege: a link signed by an unanchored
  /// enrollment adds a hop without reaching the root. Returns how many links
  /// were conveyed.
  Future<int> sweepUnanchoredEnrollments() async {
    final sharing = AtClientSecretSharing.forClient(_atClient);
    if (!sharing.isRegistered) {
      // Sealing a conveyance stamps this client's own key package id, so an
      // unregistered sweeper cannot convey anything it signs.
      _logger.info('Not sweeping chain links: this client has no registered '
          'key package to seal conveyances from');
      return 0;
    }
    final ownEnrollmentId =
        _atClient.getRemoteSecondary()?.atLookUp.enrollmentId;

    final approved = await fetchEnrollmentRequests(
        enrollmentListParams: EnrollmentListRequestParam()
          ..enrollmentListFilter = [EnrollmentStatus.approved]);

    int conveyed = 0;
    for (final enrollment in approved) {
      final id = enrollment.enrollmentId;
      if (id == null || id == ownEnrollmentId) continue;
      try {
        // Already vouched for, either way: a chain link, or a direct root
        // anchor (a privileged enrollment that holds the root needs no hop).
        if (await PqSigningChain.readLink(_atClient, id) != null) continue;
        if (await PqSigningChain.readRootLink(_atClient, id) != null) continue;

        // No key package, no conveyance channel: a legacy enrollment cannot
        // receive a link and has no PQ key for one to vouch for.
        final advertised = enrollment.metadata?['keyPackage'];
        if (advertised == null) continue;
        final (keyPackage, status) = await verifyAdvertisedKeyPackage(
          advertised,
          signer: AtClientEnvelopeSigner(_atClient),
          signerAtSign: _atClient.getCurrentAtSign()!,
          enrollmentId: id,
        );
        if (keyPackage == null || status == KeyPackageStatus.rejected) {
          continue;
        }

        final link = await PqSigningChain.signLinkFor(_atClient, sharing, id);
        if (link == null) continue;
        await sharing.shareSecretWith(
            keyPackage,
            Secret(
              namespace: _conveyanceNamespaceFor(enrollment),
              name: PqSigningChain.linkSecretName,
              value: PqSigningChain.encodeLink(link),
            ));
        conveyed++;
      } catch (e) {
        // One enrollment failing must not stop the sweep; it is retried at
        // every privileged start.
        _logger.warning('Could not sweep a chain link for enrollment $id: $e');
      }
    }
    if (conveyed > 0) {
      _logger.info('Swept chain links to $conveyed unanchored enrollment(s); '
          'each stamps its own _apsk at its next start');
    }
    return conveyed;
  }

  /// Whether [namespaces] grant `rw` on both `*` and `__manage` — the class
  /// that may hold the signing root ([decisions.md 18.2][]).
  ///
  /// Read off the granted namespaces rather than trusted from the caller: this
  /// decides who receives the key that vouches for every enrollment on the
  /// atSign.
  ///
  /// [decisions.md 18.2]: ../../../../../docs/projects/pq/decisions.md
  static bool isFullyPrivileged(Map<String, dynamic>? namespaces) {
    if (namespaces == null) return false;
    bool grantsWrite(String ns) => '${namespaces[ns] ?? ''}'.contains('w');
    return grantsWrite('*') && grantsWrite('__manage');
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

  @override
  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision enrollmentRequestDecision) async {
    // Read the pending record before approving. A request that sent no wrapped
    // symmetric key is one that expects this approver to mint it — that
    // absence is the whole signal, and it is only visible while the record is
    // still the one the enrollee wrote. Its advertised key package alone would
    // not do: every mode may carry one, because a package is also how existing
    // secrets are sealed to a new device.
    final pending =
        await _enrollmentById(enrollmentRequestDecision.enrollmentId);
    final bool mintsSymmetricKey =
        (pending?.encryptedAPKAMSymmetricKey?.isEmpty ?? true) &&
            pending?.metadata?['keyPackage'] != null;

    String? mintedApkamSymmetricKey;
    var decision = enrollmentRequestDecision;
    if (mintsSymmetricKey) {
      mintedApkamSymmetricKey =
          AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256).key;
      decision = EnrollmentRequestDecision.approvedWithMintedKey(
        enrollmentId: enrollmentRequestDecision.enrollmentId,
        apkamSymmetricKey: mintedApkamSymmetricKey,
        atSign: enrollmentRequestDecision.atSign,
      );
    }

    final response = await _atEnrollmentImpl.approve(
        decision, _atClient.getRemoteSecondary()!.atLookUp);

    // Re-read the record rather than trusting the decision object: the
    // decision carries only the id and the symmetric key, while conveyance
    // needs the granted namespaces and the advertised key package, and both
    // live on the enrollment the atServer just approved. Re-read *after*
    // approval specifically, because the atServer publishes the enrollment's
    // _apsk at that point and the package cannot be verified before it exists.
    final enrollment =
        await _enrollmentById(enrollmentRequestDecision.enrollmentId);
    if (enrollment != null) {
      await _shareSecretsWith(enrollment,
          mintedApkamSymmetricKey: mintedApkamSymmetricKey);
    }

    return response;
  }

  Future<Enrollment?> _enrollmentById(String enrollmentId) async =>
      (await fetchEnrollmentRequests())
          .where((e) => e.enrollmentId == enrollmentId)
          .firstOrNull;

  @override
  Future<AtEnrollmentResponse> deny(
      EnrollmentRequestDecision enrollmentRequestDecision) async {
    return _atEnrollmentImpl.deny(
        enrollmentRequestDecision, _atClient.getRemoteSecondary()!.atLookUp);
  }

  @override
  Future<AtEnrollmentResponse> revoke(
      EnrollmentRequestDecision enrollmentRequestDecision) async {
    return _atEnrollmentImpl.revoke(
        enrollmentRequestDecision, _atClient.getRemoteSecondary()!.atLookUp);
  }
}
