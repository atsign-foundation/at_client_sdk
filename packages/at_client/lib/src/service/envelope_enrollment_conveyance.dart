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
          namespace: _conveyanceNamespaceFor(pending, await _ownGrants()),
          name: enrollmentApkamSymmetricKeySecretName,
          value: apkamSymmetricKey,
        ),
        inReplyTo: EnvelopeAddressing.unsolicited);
  }

  /// Links [enrollment]'s keys, then seals every secret its namespaces
  /// authorise to the key package it advertised on its `enroll:request`, so
  /// the newly approved device can read what it has just been authorised for.
  ///
  /// Runs **after** the approval, because the atServer publishes the
  /// enrollment's `_apsk` at that point and neither the keys nor the package
  /// can be read before it exists.
  @override
  Future<KeyPackageStatus> conveySecretsTo(Enrollment enrollment) async {
    await _linkKeysOf(enrollment);

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
    final ownGrants = await _ownGrants();
    late final envelopeNamespace =
        _conveyanceNamespaceFor(enrollment, ownGrants);

    final rootPrivate =
        (await PqSigningRoot(_atClient, keysIo: _atClient.atKeysIo)
                .signingKey(atSign))
            ?.private;

    // NOTE: the signing root's private half goes only to a fully privileged
    // enrollment, and under a per-enrollment name so shareAllSecretsWith never
    // forwards it on to the next enrollment sharing that namespace.
    if (isFullyPrivileged(enrollment.namespace)) {
      final private = rootPrivate;
      if (private != null) {
        await sharing.shareSecretWith(
            package,
            Secret(
              namespace: envelopeNamespace,
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
        late final PublishedNskeyKeyRing ring;
        final filing = NskeyPrivateFiling.checkedAgainst(() => ring,
            keysIo: keysIo, atSign: atSign);
        ring = PublishedNskeyKeyRing(_atClient, privateFiling: filing);
        final sent = await NskeySeeding(
          atClient: _atClient,
          ring: ring,
          sharing: sharing,
          privateFiling: filing,
        ).conveyHeldPrivatesTo(package, enrollment.namespace ?? const {},
            ownGrants: ownGrants);
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
        approvedNamespaces: enrollment.namespace,
        senderMayWrite: (namespace) => mayWriteIn(ownGrants, namespace));

    return status;
  }

  /// Links [enrollment]'s keys through `enroll:link`, with the signing root
  /// when this approver holds it and is fully privileged, else with one of its
  /// own keys that walks to the root.
  ///
  /// Never fails the approval: an approver with neither links nothing, and a
  /// refused or failed write is logged, leaving a root holder's sweep to link
  /// the enrollment.
  Future<void> _linkKeysOf(Enrollment enrollment) async {
    final id = enrollment.enrollmentId!;
    try {
      final chain = PqSigningChain(_atClient);
      final sharing = AtClientSecretSharing.forClient(_atClient);
      final voucher = await chain.voucher(sharing,
          isFullyPrivileged: _privilege.isFullyPrivileged);
      if (voucher == null) {
        _logger.info('Not linking the keys of enrollment $id: this approver '
            'holds neither the signing root nor a key of its own that walks '
            'to it, so a root holder\'s sweep links them');
        return;
      }
      var record = await chain.readRecord(id);
      for (var attempt = 1;
          record == null && attempt < verifyAttempts && !_atClient.isStopped;
          attempt++) {
        await Future<void>.delayed(verifyRetryPause);
        record = await chain.readRecord(id);
      }
      if (record == null) {
        _logger.warning('Enrollment $id is approved but its _apsk could not '
            'be read, so none of its keys was linked; a root holder\'s sweep '
            'links them');
        return;
      }
      final linked = await chain.linkKeysOf(record, voucher,
          authenticationKey: enrollment.apkamPublicKey, verifier: sharing);
      if (linked.isNotEmpty) {
        _logger.info('Linked key(s) ${linked.join(', ')} of enrollment $id '
            'with ${voucher.isRoot ? 'the signing root' : 'a key of this '
                'approver'}');
      }
    } on Exception catch (e) {
      if (e is StoppedException) rethrow;
      _logger.warning('Could not link the keys of enrollment $id; a root '
          'holder\'s sweep links them: $e');
    }
  }

  /// The anchoring sweep: see
  /// [EnrollmentConveyance.sweepUnanchoredEnrollments] for why it exists and
  /// who may run it.
  ///
  /// Writes **root** links only: a client that does not hold the signing root
  /// links nothing this pass, and the sweep runs again at every privileged
  /// start. It stops once this client's atServer has refused `enroll:link` as
  /// a command it does not know, naming the enrollments it leaves unswept.
  @override
  Future<int> sweepUnanchoredEnrollments() async {
    final chain = PqSigningChain(_atClient);
    final sharing = AtClientSecretSharing.forClient(_atClient);
    // NOTE: privilege is the caller's to check, as the interface says.
    final voucher =
        await chain.voucher(sharing, isFullyPrivileged: () async => true);
    if (voucher == null || !voucher.isRoot) {
      _logger.warning('Not sweeping root links: this client holds no '
          'published signing-root private yet; its next start pulls or '
          'publishes one first');
      return 0;
    }

    final ownEnrollmentId = _atClient.enrollmentId;
    final approved = await _listEnrollments(
        enrollmentListParams: EnrollmentListRequestParam()
          ..enrollmentListFilter = [EnrollmentStatus.approved]);

    final sweeping = [
      for (final enrollment in approved)
        if (!isAtSignCredential(enrollment.enrollmentId) &&
            enrollment.enrollmentId != ownEnrollmentId)
          enrollment
    ];
    var linked = 0;
    for (var i = 0; i < sweeping.length; i++) {
      if (chain.lacksEnrollLink) {
        _logger.warning('Stopped the root-link sweep: this atServer links no '
            'keys, so enrollment(s) '
            '${sweeping.skip(i).map((e) => e.enrollmentId).join(', ')} were '
            'not swept; a later start sweeps them again');
        break;
      }
      final enrollment = sweeping[i];
      final id = enrollment.enrollmentId!;
      try {
        final record = await chain.readRecord(id);
        if (record == null) continue;
        final kids = await chain.linkKeysOf(record, voucher,
            authenticationKey: enrollment.apkamPublicKey, verifier: sharing);
        if (kids.isNotEmpty) linked++;
      } on Exception catch (e) {
        if (e is StoppedException) rethrow;
        _logger.warning('Could not sweep root links for enrollment $id: $e');
      }
    }
    if (linked > 0) {
      _logger.info('Root-linked keys on $linked enrollment(s)');
    }
    return linked;
  }

  /// A namespace [enrollment] may read and this approver, granted [own], may
  /// write, for an envelope addressed to it.
  ///
  /// The envelope is a key in an ordinary namespace, so the atServer's
  /// namespace gating decides both who may write it and who may fetch it.
  /// Tried in order: the namespaces [enrollment] was granted, this client's
  /// `preference.namespace`, then the namespaces this client was granted — so
  /// an enrollment granted only `*` fetches it from the approver's namespace.
  /// Throws when none qualifies.
  String _conveyanceNamespaceFor(
      Enrollment enrollment, Map<String, dynamic>? own) {
    final granted = enrollment.namespace ?? const <String, dynamic>{};
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
  /// The atSign's own credential is treated as the atSign itself, with no
  /// limit; for a record the list does not carry, the atServer's refusal of
  /// the write is what reports a namespace this client may not write.
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
