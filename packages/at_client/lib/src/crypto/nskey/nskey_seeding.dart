import 'dart:async' show unawaited;
import 'dart:convert' show base64Encode;

import 'package:at_client/src/enroll/at_sign_credential.dart';
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_commons/at_commons.dart' show EnrollmentConstants;
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart'
    show NskeyAdvertisement, NskeySeed;
import 'package:at_client/src/crypto/nskey/nskey_rotation.dart'
    show NskeyRotation;
import 'package:at_client/src/crypto/nskey/rotation_policy.dart';
import 'package:at_client/src/crypto/nskey/published_nskey_key_ring.dart';
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart'
    show PairwiseSecretSharing;
import 'package:at_client/src/secret_sharing/envelope_addressing.dart'
    show EnvelopeAddressing;
import 'package:at_client/src/secret_sharing/key_package.dart' show KeyPackage;
import 'package:at_client/src/secret_sharing/secret_store.dart' show Secret;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('NskeySeeding');

/// Mints and publishes this atSign's namespace keys at client start, and
/// conveys each private to the atSign's other enrollments.
///
/// At start rather than on first write, so a recipient that has ever run a
/// PQ-capable client for a namespace is already reachable for it, and
/// best-effort throughout: nothing here throws into a client's startup, and a
/// namespace that cannot be minted now is minted at the next start.
@experimental
class NskeySeeding {
  final AtClient atClient;
  final PublishedNskeyKeyRing ring;

  /// Conveys a minted private to the atSign's other enrollments. Null skips
  /// conveyance, leaving the minting client the only holder.
  final PairwiseSecretSharing? sharing;

  /// Reads back what was minted, so conveyance sends the durable copy rather
  /// than a value held only in this call.
  final NskeyPrivateFiling? privateFiling;

  /// Asked, once per authorised namespace at every client start, whether this
  /// atSign's namespace key should be replaced.
  final NskeyRotationPolicy rotationPolicy;

  NskeySeeding({
    required this.atClient,
    required this.ring,
    this.sharing,
    this.privateFiling,
    this.rotationPolicy = neverRotateNskey,
  });

  /// The namespaces this client should hold a key for.
  ///
  /// An APKAM client is told by its own enrollment record, all the atServer
  /// returns without `__manage`, while a legacy PKAM client has no enrollment
  /// and names exactly one — its `preference.namespace`, which is also what a
  /// grant of `*` seeds, `__manage` being skipped either way.
  Future<Set<String>> authorisedNamespaces() async {
    final own = atClient.getPreferences()?.namespace;
    final ownNamespace =
        (own == null || own.isEmpty) ? const <String>{} : {own};
    final enrollmentId = atClient.enrollmentId;
    if (isAtSignCredential(enrollmentId)) return ownNamespace;

    try {
      final mine = (await atClient.enrollmentService!.fetchEnrollmentRequests())
          .where((e) => e.enrollmentId == enrollmentId);
      final granted = {
        for (final enrollment in mine) ...?enrollment.namespace?.keys
      };
      return {
        ...granted.where(isSeedable),
        if (granted.contains(EnrollmentConstants.allNamespaces))
          ...ownNamespace,
      };
    } catch (e) {
      _logger.info('Could not read this enrollment to find its namespaces, so '
          'nothing is seeded this start: $e');
      return const {};
    }
  }

  /// Whether [namespace] can hold a namespace key of its own.
  ///
  /// `*` and `__manage` are grants over *other* namespaces rather than
  /// namespaces data lives in, so nothing ever mints for them; the answer comes
  /// from the argument alone and no later start can change it.
  static bool isSeedable(String namespace) =>
      namespace != '*' && namespace != '__manage' && namespace.isNotEmpty;

  /// Mints and publishes for every authorised namespace that has no key yet,
  /// then conveys each new private. Returns the namespaces this start published
  /// fresh material for — a cold-start mint, or a rotation a revocation owed.
  Future<Set<String>> seed() async {
    final owner = atClient.getCurrentAtSign();
    if (owner == null) return const {};

    final minted = <String>{};
    for (final namespace in await authorisedNamespaces()) {
      try {
        // NOTE: before the seed, not after — a rotation mints every algorithm
        // this client is configured for, so seeding behind one would find
        // nothing missing and would ask the policy about a brand-new generation.
        if (await rotateIfRevoked(owner, namespace)) {
          minted.add(namespace);
          continue;
        }
        if (await seedNamespace(owner, namespace)) minted.add(namespace);
      } catch (e) {
        _logger.warning('Could not seed $owner:$namespace this start: $e');
      }
    }
    return minted;
  }

  /// Mints, publishes and conveys the key for **one** namespace unless one is
  /// already published, throwing rather than logging, and returns whether this
  /// call minted.
  ///
  /// ⚠️ Concurrent callers of the SAME enrolment are safe only where they share a
  /// mint-lock instance — the wire lock's value is the enrolment id, so two
  /// racers of one enrolment each read back their own and each mint — while
  /// [askRotationPolicy] false suppresses putting an already-published generation
  /// to [rotationPolicy], for a caller that only wants this atSign reachable.
  Future<bool> seedNamespace(String owner, String namespace,
      {bool askRotationPolicy = true}) async {
    if (!isSeedable(namespace)) {
      throw ArgumentError.value(
          namespace,
          'namespace',
          'is a grant over other namespaces rather than one data lives in, so '
              'no key is ever minted for it');
    }

    // NOTE: the atServer, not local storage — a namespace another enrollment
    // minted a moment ago is absent locally until sync catches up, and reading
    // that absence as a cold start publishes a second key over the first.
    final published = await ring.publishedAdvertisement(owner, namespace);
    if (published != null) {
      final rotated = askRotationPolicy &&
          await rotateIfPolicyAsks(owner, namespace, published: published);
      if (!rotated) await _addMissing(owner, namespace, published);
      return false;
    }
    final advertisement = await ring.mintAndPublish(namespace);

    // NOTE: the conveyance is guarded separately because publishing alone makes
    // this atSign reachable, while conveying only hands its other enrollments
    // the private half, which they can also pull. A legacy PKAM client cannot
    // enumerate members at all — `enroll:listns` is APKAM-gated — so reporting
    // that as a failure to seed would call a reachable atSign unreachable.
    try {
      // NOTE: every key the generation carries, not only the id the
      // advertisement's getter names — an unconveyed key is one peers seal to
      // and nobody else can open.
      for (final key in advertisement.keys) {
        await _convey(namespace, key.kid);
      }
    } catch (e) {
      _logger.warning(
          'Published the nskey for $owner:$namespace, but could not convey '
          'its private to this atSign\'s other enrollments — they will pull '
          'it at their next start. Peers can seal here either way: $e');
    }
    return true;
  }

  /// Adds this client's own missing key-establishment material to a generation
  /// that already exists, and conveys **only what was added**.
  ///
  /// Failure is logged, not thrown: this atSign is reachable either way, and an
  /// add only buys peers configured for the added algorithm the ability to seal
  /// under it.
  Future<void> _addMissing(
      String owner, String namespace, NskeyAdvertisement published) async {
    final before = published.keys.map((key) => key.kid).toSet();
    final NskeyAdvertisement? widened;
    try {
      widened = await ring.add(namespace);
    } catch (e) {
      _logger.warning('Could not add this client\'s missing key material to '
          'the nskey for $owner:$namespace; the generation already published '
          'is unchanged and the next start tries again: $e');
      return;
    }
    if (widened == null) return;

    for (final key in widened.keys) {
      // NOTE: an entry already in `before` was conveyed when it was minted, so
      // re-sending it costs one envelope each for material they can open.
      if (before.contains(key.kid)) continue;
      try {
        await _convey(namespace, key.kid);
      } catch (e) {
        _logger.warning('Added ${key.alg} to the nskey for $owner:$namespace '
            'but could not convey its private to this atSign\'s other '
            'enrollments — they will pull it at their next start. Peers can '
            'seal under it either way: $e');
      }
    }
  }

  /// Puts [rotationPolicy] the question for a namespace that already has a
  /// generation, replaces it if the answer is yes, and returns whether it did.
  ///
  /// [published] is the generation already read where the caller has it, and any
  /// failure returns false rather than throwing — the published generation stays
  /// published, and the question is put again at the next start.
  @experimental
  Future<bool> rotateIfPolicyAsks(String owner, String namespace,
      {NskeyAdvertisement? published}) async {
    final generation =
        published ?? await ring.publishedAdvertisement(owner, namespace);
    if (generation == null) return false;

    final bool replace;
    try {
      replace = await rotationPolicy(NskeyRotationContext(
        namespace: namespace,
        nskeyKid: generation.nskeyKid,
        createdAt: generation.createdAt,
        now: DateTime.now().toUtc(),
      ));
    } catch (e) {
      _logger.warning('The nskey rotation policy threw for $owner:$namespace, '
          'so nothing was rotated: $e');
      return false;
    }
    if (!replace) return false;

    // NOTE: the policy is asked before this check, so that a client with
    // nowhere to convey the successor refuses out loud rather than swallowing
    // the application's yes. Replacing without a substrate would publish a
    // generation only this client can open.
    final substrate = sharing;
    final filing = privateFiling;
    if (substrate == null || filing == null) {
      _logger.warning('The rotation policy asked for a fresh namespace key for '
          '$owner:$namespace and this client has no substrate to convey the '
          'successor over, so nothing was replaced: a generation only this '
          'client could open would be worse than the one already published');
      return false;
    }

    _logger.info('The rotation policy asked for a fresh namespace key for '
        '$owner:$namespace, replacing generation ${generation.nskeyKid} '
        'minted at ${generation.createdAt}');
    try {
      await NskeyRotation(
        atClient: atClient,
        ring: ring,
        privateFiling: filing,
        sharing: substrate,
      ).rotateNamespaceKey(namespace);
      return true;
    } catch (e) {
      _logger.warning('The rotation policy asked for a fresh namespace key for '
          '$owner:$namespace and it did not happen; the published generation '
          'is unchanged and the next start will ask again: $e');
      return false;
    }
  }

  /// Rotates [namespace] when a revocation has touched an enrollment granted it
  /// since that namespace's advertisement was last rotated, and returns whether
  /// it did.
  ///
  /// Unconditional rather than [rotationPolicy]'s question, because only a fresh
  /// generation cuts a revoked enrollment off from what is sealed next; both
  /// moments compared are stamped by the atServer — the revocation's and the
  /// record's `updatedAt`, never the generation's own `createdAt`, which would
  /// compare two clocks — and establishing no cause rotates nothing, while a
  /// published record whose stamp cannot be read does rotate.
  @experimental
  Future<bool> rotateIfRevoked(String owner, String namespace) async {
    final substrate = sharing;
    final filing = privateFiling;
    if (substrate == null || filing == null) return false;

    // NOTE: the atSign's own credential is not an enrollment the atServer will
    // answer about, and the verb behind the lookup is APKAM-gated.
    if (isAtSignCredential(atClient.enrollmentId)) {
      return false;
    }

    final DateTime? revokedAt;
    try {
      revokedAt = await substrate.directory.lastRevokedAt(namespace);
    } catch (e) {
      _logger.warning('Could not read whether a revocation has touched '
          '$owner:$namespace, so nothing is rotated for it this start — a '
          'revoked enrollment that still holds this generation goes on '
          'reading until a start establishes otherwise: $e');
      return false;
    }
    if (revokedAt == null) return false;

    final ({NskeyAdvertisement advertisement, DateTime? updatedAt})? record;
    try {
      record = await ring.publishedRecord(owner, namespace);
    } catch (e) {
      _logger.warning('A revocation touched $owner:$namespace at $revokedAt, '
          'and what it published could not be read, so nothing is rotated '
          'this start: $e');
      return false;
    }
    if (record == null) return false;

    final rotatedAt = record.updatedAt;
    if (rotatedAt != null && !revokedAt.isAfter(rotatedAt)) return false;

    _logger.info('Rotating $owner:$namespace: a revocation touched it at '
        '$revokedAt, and what is published there was stamped '
        '${rotatedAt ?? 'at a moment the atServer did not report'}');
    try {
      await NskeyRotation(
        atClient: atClient,
        ring: ring,
        privateFiling: filing,
        sharing: substrate,
      ).rotateNamespaceKey(namespace);
      return true;
    } catch (e) {
      _logger.warning('A revocation touched $owner:$namespace at $revokedAt '
          'and the rotation it owes did not happen; the published generation '
          'is unchanged and the next start asks again: $e');
      return false;
    }
  }

  /// Primes the in-memory secret store with the nskey privates this client
  /// holds durably, so the request-answer path can serve them.
  ///
  /// That path reads the secret store, a transit buffer emptied by every
  /// restart, so without this a holder that restarted since the mint holds the
  /// private in AtKeys and answers every request with nothing; re-priming a name
  /// is a no-op under `putIfNewer`, and the return is how many were primed.
  Future<int> hydrateStoreFromFiling(PairwiseSecretSharing sharing) async {
    final filing = privateFiling;
    if (filing == null) return 0;

    int hydrated = 0;
    // NOTE: off the keyfile, not off the enrollment record — this runs during
    // client construction, before the enrollment service is wired, so asking
    // the atServer what this client is authorised for would fail and silently
    // prime nothing. What a holder can answer with is what it holds anyway.
    final Map<String, Map<String, NskeySeed>> held;
    try {
      held = await filing.readAll();
    } catch (e) {
      _logger.warning('Could not read held nskey privates to prime them: $e');
      return 0;
    }
    for (final namespace in held.keys) {
      for (final entry in held[namespace]!.entries) {
        await sharing.secretStore.putIfNewer(Secret(
          namespace: namespace,
          name: '${NskeyPrivateFiling.secretNamePrefix}${entry.key}',
          value: base64Encode(entry.value.bytes),
        ));
        hydrated++;
      }
    }
    return hydrated;
  }

  /// Pulls the nskey privates this enrollment is entitled to and does not hold,
  /// from whichever enrollments currently do, and returns the namespaces a
  /// request went out for.
  ///
  /// The other half of the self-heal — [seed] mints when no key exists, this asks
  /// when one does — broadcast to the namespace's key packages rather than
  /// addressed to a minter that may be long gone, and store-and-forward on both
  /// legs, so an answer arriving after this client exits is filed by the next
  /// start's sweep.
  Future<Set<String>> requestMissingPrivates(
      PairwiseSecretSharing sharing) async {
    final owner = atClient.getCurrentAtSign();
    final filing = privateFiling;
    if (owner == null || filing == null) return const {};

    final asked = <String>{};
    for (final namespace in await authorisedNamespaces()) {
      try {
        final advertised = await ring.currentPublic(owner, namespace);
        if (advertised == null) continue;
        if (await ring.privateHalf(owner, namespace, advertised.nskeyKid) !=
            null) {
          continue;
        }

        final name =
            '${NskeyPrivateFiling.secretNamePrefix}${advertised.nskeyKid}';
        final sent =
            await sharing.requestSecretsFromNamespace(namespace, names: [name]);
        if (sent == 0) {
          _logger.info('Wanted the nskey private for $owner:$namespace but '
              'found no other key package to ask; the next start retries');
          continue;
        }
        asked.add(namespace);

        // NOTE: unawaited on purpose — a holder may be offline for days, and
        // neither this sweep nor the client's start may wait on one.
        unawaited(sharing
            .waitForSecret(namespace, name,
                timeout: NskeyPrivateFiling.conveyanceWait)
            .then((secret) => filing.file(secret))
            .then((filed) {
          if (filed) {
            _logger.info(
                'Healed the nskey private for $owner:$namespace from another '
                'enrollment');
          }
        }).catchError((Object e) {
          _logger.info('No holder answered for $owner:$namespace within the '
              'wait; a later answer is filed at the next start ($e)');
        }));
      } catch (e) {
        _logger.warning(
            'Could not request the nskey private for $owner:$namespace: $e');
      }
    }
    return asked;
  }

  /// Sends every nskey private this client holds for [approvedNamespaces] to
  /// one newly approved enrollment.
  ///
  /// Read from `AtKeys` rather than the secret store, which is in-memory by
  /// design and holds nothing after a restart — an approver relying on it would
  /// convey a new enrollment **nothing**.
  Future<int> conveyHeldPrivatesTo(
      KeyPackage keyPackage, Iterable<String> approvedNamespaces) async {
    final sharing = this.sharing;
    final filing = privateFiling;
    if (sharing == null || filing == null) return 0;

    int sent = 0;
    for (final namespace in approvedNamespaces.where(isSeedable)) {
      final held = await filing.readAllFor(namespace);
      for (final entry in held.entries) {
        await sharing.shareSecretWith(
            keyPackage,
            Secret(
              namespace: namespace,
              name: '${NskeyPrivateFiling.secretNamePrefix}${entry.key}',
              value: base64Encode(entry.value.bytes),
            ),
            inReplyTo: EnvelopeAddressing.unsolicited);
        sent++;
      }
    }
    return sent;
  }

  /// Sends the minted private to the atSign's other enrollments, and puts it
  /// in this client's own secret store so it can answer for it.
  ///
  /// The private is read back from the durable store, so one that failed to
  /// persist is never sent, and the store write is what lets the minter serve a
  /// later pull — the secret store the answering path reads is otherwise filled
  /// only at bootstrap, before the mint — but ⚠️ a generation minted inside
  /// [PublishedNskeyKeyRing] never reaches this method, leaving that client's
  /// store unprimed for it.
  Future<void> _convey(String namespace, String nskeyKid) async {
    final sharing = this.sharing;
    // NOTE: the SEED, never the expanded decapsulation key — a receiver
    // validates an arrival by re-deriving the published public half, which only
    // the seed allows. For X-Wing the two are the same bytes; for ML-KEM the
    // expanded form is refused on arrival and nobody else gets the key.
    final seed = await privateFiling?.readSeed(namespace, nskeyKid);
    if (sharing == null || seed == null) return;

    final secret = Secret(
      namespace: namespace,
      name: '${NskeyPrivateFiling.secretNamePrefix}$nskeyKid',
      value: base64Encode(seed.bytes),
    );
    await sharing.secretStore.putIfNewer(secret);
    await sharing.pushSecretToNamespaceMembers(secret);
  }
}
