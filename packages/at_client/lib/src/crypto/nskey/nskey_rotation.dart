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
/// [conveyedTo] is the number of key packages the successor private was pushed
/// to, and it is deliberately allowed to be zero: a single-enrollment atSign
/// has nobody to push to, and a holder that was offline picks the generation up
/// from the pull backstop instead.
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

/// The nskey-keypair rotation lever (`design.md` §1.7 B5b) and the revocation
/// it composes with (B6).
///
/// **This is the expensive lever, and it is not the forward-secrecy one.**
/// Rotating the keypair buys namespace-granular post-compromise security and is
/// how an enrollment is cut off from *future* data; it costs one conveyance per
/// surviving enrollment. Coarse forward secrecy — making already-written data
/// unreadable — is the content-key lever, is O(1), and rides ordinary sync
/// rather than the substrate. Conflating them is the mistake this class is
/// named to prevent.
///
/// **Rotation is never automatic.** Store-and-forward cannot tell "no holder
/// exists" from "the holder is offline", so a failed pull must not trigger a
/// re-mint — a namespace whose last private-holder is genuinely lost is
/// recovered by an operator calling [rotateNamespaceKey] explicitly, and the
/// records sealed to the lost generation stay unreadable. Rotation replaces the
/// key; it does not decrypt the past.
///
/// **Who may call it** is the same bar the atServer already enforces on the
/// advertisement write: `rw` on the namespace. No separate privilege check
/// lives here, because a second gate that disagreed with the atServer's would
/// only ever be the wrong one.
@experimental
class NskeyRotation {
  final AtClient atClient;
  final PublishedNskeyKeyRing ring;

  /// Where the successor private is filed before it is published, and where it
  /// is read back from to convey — so what other enrollments receive is exactly
  /// what this client will itself use.
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
  /// Throws if the client has no `AtKeysIo`. Rotation without one would file
  /// the successor private in memory and lose it at exit, leaving every peer
  /// sealing to a generation this atSign can no longer open — strictly worse
  /// than not rotating, so it is refused rather than attempted.
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
  /// **What the exclusion is, and what it is not.** It stops *this* client
  /// pushing the successor to the named enrollments. It cannot stop another
  /// holder answering their pull, because a holder honours only what the
  /// atServer tells it — and the atServer's own signal for "this enrollment
  /// gets nothing" is revocation, not a list one client happens to be holding.
  /// So exclusion alone is a courtesy, exactly as
  /// `PairwiseSecretSharing.shareAllSecretsWith`'s namespace filter is; the
  /// enforcement is [revokeEnrollmentAndRotate]'s revoke-first ordering, after
  /// which the excluded enrollment is absent from every roster and refused at
  /// every serve without any client having to remember it.
  ///
  /// **Peers notice by re-fetching, not by being told.** A sender never sees a
  /// recipient's decapsulation fail, so the advertisement's freshness window is
  /// the only thing that makes a rotation take effect for inbound data. Until a
  /// peer re-`plookup`s and sees the changed `nskeyKid`, it keeps sealing
  /// content keys to the superseded generation — which the excluded enrollment
  /// can still open. That window is the rotation's exposure, and it is bounded
  /// by `PublishedNskeyKeyRing.advertisementTtl` plus one content-key lifetime.
  Future<NskeyRotationOutcome> rotateNamespaceKey(
    String namespace, {
    Set<String> excludeEnrollmentIds = const {},
  }) async {
    final owner = atClient.getCurrentAtSign();
    if (owner == null) {
      throw StateError('cannot rotate $namespace: no current atSign');
    }
    // The cold-start refusal is [PublishedNskeyKeyRing.rotate]'s, which has to
    // make the same check anyway and reads the atServer rather than local
    // storage to make it. Asking here as well put the same question to the
    // atServer twice, one round trip apart, with nothing able to act on a
    // difference between the two answers.
    final outcome = await ring.rotate(namespace);
    final advertisement = outcome.rotated;

    // Read back the durable copy rather than trusting the mint's return: a
    // private that failed to persist must never be conveyed, and this is the
    // same discipline the mint-time push uses. The SEED, never the expanded
    // decapsulation key — the receiver re-derives the published public half
    // from what arrives, which only the seed can do.
    final private =
        await privateFiling.readSeed(namespace, advertisement.nskeyKid);
    if (private == null) {
      throw StateError(
          'rotated $owner:$namespace to ${advertisement.nskeyKid} but cannot '
          'read the successor private back, so it is deliberately not conveyed '
          '— the other enrollments keep the superseded generation and a later '
          'rotation supersedes this one');
    }

    final secret = Secret(
      namespace: namespace,
      name: '${NskeyPrivateFiling.secretNamePrefix}'
          '${advertisement.nskeyKid}',
      value: base64Encode(private.bytes),
    );

    // Into this client's own store before the fan-out, for the same reason
    // the mint-time convey does it: the request-answer path serves from the
    // secret store, and the store is filled from the keyfile only by
    // `hydrateStoreFromFiling` at bootstrap — which has already run by the
    // time anything rotates. Without this the enrollment that rotated is the
    // one enrollment certain to hold the successor and the only one that
    // cannot serve it, until it restarts, and it fails silently: a holder
    // with no matching candidate writes no envelope and logs nothing.
    //
    // It grants nothing the fan-out below does not already grant — that sends
    // these exact bytes, unsolicited, to every key package on the roster,
    // minus [excludeEnrollmentIds]. ⚠️ Serving a later PULL is not filtered by
    // that exclusion, so an enrollment excluded from the rotation can still
    // ask for the successor and be answered. Rotation-to-exclude is therefore
    // not a revocation on its own; revoking the enrollment is what stops it
    // being on the roster the answer path resolves against.
    await sharing.secretStore.putIfNewer(secret);

    // Outside the mint lock deliberately. The lock serialises *minting*, and a
    // concurrent rotation is already refused by the time this runs; holding it
    // across a per-enrollment fan-out would make an atSign's lock-held window
    // scale with its enrollment count for no interlock gained.
    final conveyedTo = await sharing.pushSecretToNamespaceMembers(
      secret,
      excludeEnrollmentIds: excludeEnrollmentIds,
    );

    _logger.info('Rotated $owner:$namespace to ${advertisement.nskeyKid} and '
        'conveyed the successor to $conveyedTo key package(s)'
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
  /// excluding it — the revocation composition of `design.md` §1.7 (B6).
  ///
  /// **The ordering is the enforcement.** Revoking first drops the enrollment
  /// out of `enroll:listns` at the atServer, so by the time any rotation runs
  /// it is absent from every roster and refused at every serve — including
  /// pulls answered by holders that have never heard of this operation. Rotate
  /// first and the same enrollment could simply request the successor private
  /// from another holder in the gap, undoing the rotation it was the point of.
  ///
  /// **What it does not undo.** An enrollment id may have any number of live
  /// holders — a copied keyfile is cryptographically indistinguishable from its
  /// original — so revocation cuts *every* clone of that id, and the exclusion
  /// excludes every clone or none. Nothing here can unwind what one particular
  /// device holds. Per-device revocability exists only where each device holds
  /// its own enrollment id.
  ///
  /// **And it does not reach the past.** The revoked enrollment keeps whatever
  /// generations it already held, so data sealed to those still opens for it.
  /// Denying it already-written data is the content-key lever's job (delete the
  /// superseded `__ck` conveyance), and even that is bounded by what it may
  /// have cached.
  ///
  /// Namespaces are read *before* the revoke, because the enrollment record is
  /// what names them and a revoked record is not something to depend on being
  /// readable. `*` and `__manage` are skipped: neither is a namespace with an
  /// nskey to rotate. A wildcard enrollment is therefore reported rather than
  /// silently under-rotated — "every namespace" is not a list, and the caller
  /// has to say which ones it meant.
  ///
  /// Returns one outcome per namespace rotated. A namespace that fails to
  /// rotate is logged at `severe` and the rest are still attempted: the revoke
  /// has already landed by then, and abandoning the remainder would leave the
  /// atSign in the worst of both states.
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

    // Named before anything is attempted, because the two halves of this
    // composition ask for DIFFERENT privileges and only one of them is
    // obvious. Rotating needs `rw` on the namespace — the bar the atServer
    // already enforces on the advertisement write, and a scoped enrollment
    // clears it. Revoking needs `__manage`, and a client without it also
    // cannot *enumerate* enrollments: `enroll:list` returns it only its own
    // record. So the missing privilege would otherwise surface as "no
    // enrollment <id> to revoke", which reads as a wrong id and sends the
    // caller looking in the wrong place entirely.
    final callerEnrollmentId =
        atClient.getRemoteSecondary()?.atLookUp.enrollmentId;
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
        // Loud, and then on to the next: the revoke has already landed, so
        // abandoning the remaining namespaces would leave the atSign in the
        // worst of both states — an enrollment cut off from the server but
        // still holding every live namespace key it ever had.
        //
        // **The likeliest cause is the mint lock's cooldown**, and it is the
        // one a caller can act on: nothing releases that lock but its ttl, so
        // a namespace minted or rotated within `mintLockTtl` refuses this
        // rotation. The retry is not immediate — it has to wait the ttl out.
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
  /// `*` authorises every namespace and is not itself one — there is no
  /// `public:__nskey.*` to overwrite — and `__manage` is enrollment
  /// administration rather than an app namespace.
  static bool isRotatable(String namespace) =>
      namespace.isNotEmpty && namespace != '*' && namespace != '__manage';
}
