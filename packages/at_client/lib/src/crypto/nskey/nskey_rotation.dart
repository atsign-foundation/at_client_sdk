import 'dart:convert' show base64Encode;

import 'package:at_auth/at_auth.dart' show EnrollmentRequestDecision;
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart'
    show NskeyAdvertisement;
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
import 'package:at_client/src/crypto/nskey/published_nskey_key_ring.dart';
import 'package:at_client/src/secret_sharing/at_client_secret_sharing.dart'
    show AtClientSecretSharing;
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart'
    show PairwiseSecretSharing;
import 'package:at_client/src/secret_sharing/secret_store.dart' show Secret;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('NskeyRotation');

/// What one namespace's rotation did.
///
/// [conveyedTo] may legitimately be zero: a single-enrollment atSign has nobody
/// to push to, and an offline holder picks the generation up by pull instead.
@experimental
typedef NskeyRotationOutcome = ({
  String namespace,

  /// The generation this rotation superseded.
  String supersededKid,

  /// The generation now published and sealed to.
  NskeyAdvertisement advertisement,

  /// Key packages the successor private was pushed to.
  int conveyedTo,

  /// The enrollment ids this rotation deliberately did not push to.
  Set<String> excluded,
});

/// Rotates a namespace's nskey keypair, and composes that with revoking an
/// enrollment.
///
/// The post-compromise lever and not the forward-secrecy one — it cuts an
/// enrollment off from *future* data at one conveyance per surviving
/// enrollment, whereas making already-written data unreadable is the
/// content-key lever's O(1) job — and it is never automatic, never recovers a
/// lost generation, and needs the `rw` on the namespace that the atServer
/// already enforces on the advertisement write.
@experimental
class NskeyRotation {
  final AtClient atClient;
  final PublishedNskeyKeyRing ring;

  /// Where the successor private is filed before it is published, and read back
  /// from to convey.
  final NskeyPrivateFiling privateFiling;

  /// Carries the successor private to the surviving enrollments.
  final PairwiseSecretSharing sharing;

  NskeyRotation({
    required this.atClient,
    required this.ring,
    required this.privateFiling,
    required this.sharing,
  });

  /// Wires a rotation for [atClient] from what the client already holds — its
  /// key storage and its secret-sharing substrate.
  ///
  /// Throws if the client has no `AtKeysIo`: the successor private would live
  /// only in memory, leaving every peer sealing to a generation this atSign can
  /// no longer open.
  factory NskeyRotation.forClient(AtClient atClient,
      {NskeyPrivateFiling? privateFiling, PairwiseSecretSharing? sharing}) {
    final atSign = atClient.getCurrentAtSign();
    if (atSign == null) {
      throw StateError('cannot rotate: this client has no current atSign');
    }
    final keysIo = atClient.atKeysIo;
    if (privateFiling == null && keysIo == null) {
      throw StateError(
          'cannot rotate for $atSign: this client has no AtKeysIo, so the '
          'successor private would live only in memory and die with the '
          'process — leaving every peer sealing to a generation this atSign '
          'can no longer open');
    }
    final filing =
        privateFiling ?? NskeyPrivateFiling(keysIo: keysIo!, atSign: atSign);
    return NskeyRotation(
      atClient: atClient,
      ring: PublishedNskeyKeyRing(atClient, privateFiling: filing),
      privateFiling: filing,
      sharing: sharing ?? AtClientSecretSharing.forClient(atClient),
    );
  }

  /// Rotates [namespace] onto a fresh nskey generation and conveys the
  /// successor private to every enrollment authorised for it, minus
  /// [excludeEnrollmentIds].
  ///
  /// [excludeEnrollmentIds] enforces nothing on its own — another holder still
  /// answers those enrollments' pulls, and [revokeEnrollmentAndRotate]'s
  /// revoke-first ordering is what stops that — while peers, which notice by
  /// re-fetching rather than by being told, go on sealing to the superseded
  /// generation for `PublishedNskeyKeyRing.advertisementTtl` plus one
  /// content-key lifetime.
  Future<NskeyRotationOutcome> rotateNamespaceKey(
    String namespace, {
    Set<String> excludeEnrollmentIds = const {},
  }) async {
    final owner = atClient.getCurrentAtSign();
    if (owner == null) {
      throw StateError('cannot rotate $namespace: no current atSign');
    }
    final outcome = await ring.rotate(namespace);
    final advertisement = outcome.rotated;

    // NOTE: convey the durable SEED read back from filing, one secret per key
    // the generation carries. A private that failed to persist must never be
    // conveyed; only the seed lets a receiver re-derive the published public
    // half; and a key left unconveyed is advertised with its private held by
    // this client alone.
    final secrets = <Secret>[];
    for (final key in advertisement.keys) {
      final private = await privateFiling.readSeed(namespace, key.kid);
      if (private == null) {
        throw StateError(
            'rotated $owner:$namespace to a generation carrying ${key.alg} '
            '${key.kid} but cannot read that private back, so NOTHING is '
            'conveyed — the other enrollments keep the superseded generation '
            'whole rather than a part of the successor, and a later rotation '
            'supersedes this one');
      }
      secrets.add(Secret(
        namespace: namespace,
        name: '${NskeyPrivateFiling.secretNamePrefix}${key.kid}',
        value: base64Encode(private.bytes),
      ));
    }

    // NOTE: into this client's own store before the fan-out. The request-answer
    // path serves from the secret store, which is filled from the keyfile only
    // at bootstrap, so without this the enrollment that rotated cannot serve
    // the successor until it restarts — and it fails silently, writing no
    // envelope and logging nothing.
    for (final secret in secrets) {
      await sharing.secretStore.putIfNewer(secret);
    }

    // NOTE: outside the mint lock — holding it across a per-enrollment fan-out
    // would scale the lock-held window with the enrollment count, and the lock
    // has already refused any concurrent rotation by the time this runs.
    var conveyedTo = 0;
    for (final secret in secrets) {
      conveyedTo = await sharing.pushSecretToNamespaceMembers(
        secret,
        excludeEnrollmentIds: excludeEnrollmentIds,
      );
    }

    _logger.info('Rotated $owner:$namespace to a generation carrying '
        '${advertisement.keys.map((k) => '${k.alg}/${k.kid}').join(', ')} and '
        'conveyed ${secrets.length} private(s) to $conveyedTo key package(s)'
        '${excludeEnrollmentIds.isEmpty ? '' : ', excluding '
            '${excludeEnrollmentIds.join(', ')}'}');

    return (
      namespace: namespace,
      supersededKid: outcome.superseded.nskeyKid,
      advertisement: advertisement,
      conveyedTo: conveyedTo,
      excluded: excludeEnrollmentIds,
    );
  }

  /// Revokes [enrollmentId], then rotates every namespace it could read,
  /// excluding it, and returns one outcome per namespace rotated.
  ///
  /// Revoking first is the enforcement — it drops the enrollment out of
  /// `enroll:listns` before any rotation runs, which is why the namespaces are
  /// read beforehand and why a namespace that fails to rotate is logged at
  /// `severe` instead of abandoning the rest — but it reaches neither the past,
  /// where data already sealed still opens for the revoked enrollment, nor a
  /// single device, a clone of an enrollment id being indistinguishable from its
  /// original.
  Future<List<NskeyRotationOutcome>> revokeEnrollmentAndRotate(
    String enrollmentId, {
    Iterable<String>? namespaces,
  }) async {
    final owner = atClient.getCurrentAtSign();
    if (owner == null) {
      throw StateError('cannot revoke $enrollmentId: no current atSign');
    }
    final service = atClient.enrollmentService;
    if (service == null) {
      throw StateError(
          'cannot revoke $enrollmentId: this client has no enrollment service');
    }

    // NOTE: the two halves ask for different privileges — rotating needs `rw` on
    // the namespace, revoking needs `__manage`. A caller lacking `__manage` also
    // cannot enumerate enrollments, so without this check the missing privilege
    // surfaces as "no enrollment <id> to revoke", which reads as a wrong id.
    final callerEnrollmentId = atClient.enrollmentId;
    final all = await service.fetchEnrollmentRequests();
    if (callerEnrollmentId != null && callerEnrollmentId.isNotEmpty) {
      final me =
          all.where((e) => e.enrollmentId == callerEnrollmentId).firstOrNull;
      if (!'${me?.namespace?['__manage'] ?? ''}'.contains('w')) {
        throw StateError(
            'enrollment $callerEnrollmentId cannot revoke $enrollmentId on '
            '$owner: revocation needs rw on __manage, which this enrollment '
            'was not granted. Nothing was revoked and nothing was rotated. '
            '(Rotating alone needs only rw on the namespace — see '
            'rotateNamespaceKey.)');
      }
    }

    final Set<String> rotatable;
    if (namespaces != null) {
      rotatable = namespaces.where(isRotatable).toSet();
    } else {
      final target =
          all.where((e) => e.enrollmentId == enrollmentId).firstOrNull;
      if (target == null) {
        throw StateError(
            'no enrollment $enrollmentId on $owner to revoke — nothing was '
            'revoked and nothing was rotated');
      }
      final granted = target.namespace?.keys.toSet() ?? const <String>{};
      rotatable = granted.where(isRotatable).toSet();
      if (granted.contains('*')) {
        _logger.warning('Enrollment $enrollmentId holds "*", so the '
            'namespaces it could read are not a list this can enumerate; '
            'rotating only ${rotatable.isEmpty ? 'nothing' : rotatable.join(', ')}. '
            'Name the namespaces explicitly to rotate the rest');
      }
    }

    await service
        .revoke(EnrollmentRequestDecision.revoked(enrollmentId, owner));
    _logger.info('Revoked enrollment $enrollmentId; rotating '
        '${rotatable.isEmpty ? 'nothing' : rotatable.join(', ')} to deny it '
        'the keys that protect data written from now on');

    final outcomes = <NskeyRotationOutcome>[];
    for (final namespace in rotatable) {
      try {
        outcomes.add(await rotateNamespaceKey(namespace,
            excludeEnrollmentIds: {enrollmentId}));
      } catch (e) {
        _logger.severe('Revoked $enrollmentId but could not rotate '
            '$namespace, so it still holds that namespace\'s live generation '
            'and can open data written under it. Rotate it explicitly, after '
            'the mint lock\'s ttl if that is what refused: $e');
      }
    }
    return outcomes;
  }

  /// Whether [namespace] names something with an nskey to rotate.
  ///
  /// `*` authorises every namespace without being one, and `__manage` is
  /// enrollment administration rather than an app namespace.
  static bool isRotatable(String namespace) =>
      namespace.isNotEmpty && namespace != '*' && namespace != '__manage';
}
