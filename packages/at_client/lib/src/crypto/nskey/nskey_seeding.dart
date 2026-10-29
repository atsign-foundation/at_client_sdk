import 'dart:convert' show base64Encode;

import 'package:at_client/src/enroll/at_sign_credential.dart';
import 'package:at_client/src/enroll/authorised_namespaces.dart';
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
import 'package:at_client/src/crypto/nskey/pre_publish_conveyance.dart';
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart'
    show NskeyAdvertisement, NskeySeed;
import 'package:at_client/src/crypto/nskey/nskey_rotation.dart'
    show NskeyRotation;
import 'package:at_client/src/crypto/nskey/rotation_policy.dart';
import 'package:at_client/src/crypto/nskey/published_nskey_key_ring.dart';
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart'
    show PairwiseSecretSharing;
import 'package:at_client/src/secret_sharing/algo_ids.dart'
    show SecretSharingAlgos;
import 'package:at_client/src/secret_sharing/envelope_addressing.dart'
    show EnvelopeAddressing;
import 'package:at_client/src/secret_sharing/key_package.dart' show KeyPackage;
import 'package:at_client/src/secret_sharing/secret_store.dart'
    show Secret, SecretStore;
import 'package:at_commons/at_commons.dart' show StoppedException;
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
/// What [NskeySeeding.seedNamespace] did for one namespace.
@experimental
enum NskeySeedOutcome {
  /// This call minted the key, conveyed its private and published it.
  minted,

  /// A key was already published, by this client or another enrollment.
  alreadyPublished,

  /// This client's enrollment carries no key package, so it can be conveyed no
  /// private and minted none.
  noKeyPackage,

  /// This client has no secret-sharing substrate to convey a private over, or
  /// no key source to file one in, so it minted none.
  cannotConvey,
}

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

  // NOTE: read once, here. The startup that seeds runs unawaited, so a
  // namespace an application sets on the client after building it would
  // otherwise redirect the seed to wherever the app's own records go.
  final String? _ownNamespace;

  NskeySeeding({
    required this.atClient,
    required this.ring,
    this.sharing,
    this.privateFiling,
    this.rotationPolicy = rotateNskeyAfterOneYear,
  }) : _ownNamespace = atClient.getPreferences()?.namespace;

  /// The namespaces this client should hold a key for; see
  /// [authorisedNamespacesOf]. Empty when the enrollment record cannot be read.
  Future<Set<String>> authorisedNamespaces() async {
    try {
      return await authorisedNamespacesOf(atClient,
          ownNamespace: _ownNamespace);
    } catch (e) {
      if (e is StoppedException) rethrow;
      _logger.info('Could not read this enrollment to find its namespaces, so '
          'nothing is seeded this start: $e');
      return const {};
    }
  }

  /// Whether [namespace] can hold a namespace key of its own; see
  /// [isSeedableNamespace].
  static bool isSeedable(String namespace) => isSeedableNamespace(namespace);

  /// Mints for every authorised namespace that has no key yet, conveying each
  /// new private before publishing it. Returns the namespaces this start
  /// published fresh material for — a cold-start mint, or a rotation a
  /// revocation owed.
  ///
  /// A namespace this enrollment may only read is skipped, since every step
  /// here writes to it. One its grants let it write without naming it, such as
  /// `chat.app` under a grant on `app`, is rotated where this client holds its
  /// key and a revocation is owed there, and is otherwise left alone.
  Future<Set<String>> seed() async {
    final owner = atClient.getCurrentAtSign();
    if (owner == null) return const {};

    final Map<String, dynamic>? grants;
    try {
      grants = await ownGrantsOf(atClient);
    } catch (e) {
      if (e is StoppedException) rethrow;
      _logger.info('Could not read this enrollment to find its namespaces, so '
          'nothing is seeded this start: $e');
      return const {};
    }
    final namespaces =
        authorisedNamespacesIn(grants, ownNamespace: _ownNamespace);

    final minted = <String>{};
    final readOnly = <String>{};
    for (final namespace in namespaces) {
      if (!mayWriteIn(grants, namespace)) {
        readOnly.add(namespace);
        continue;
      }
      try {
        // NOTE: before the seed, not after — a rotation mints every algorithm
        // this client is configured for, so seeding behind one would find
        // nothing missing and would ask the policy about a brand-new generation.
        if (await rotateIfRevoked(owner, namespace)) {
          minted.add(namespace);
          continue;
        }
        if (await seedNamespace(owner, namespace) == NskeySeedOutcome.minted) {
          minted.add(namespace);
        }
      } catch (e) {
        if (e is StoppedException) rethrow;
        _logger.warning('Could not seed $owner:$namespace this start: $e');
      }
    }
    for (final namespace in await _writableHeld(grants, named: namespaces)) {
      try {
        if (await rotateIfRevoked(owner, namespace)) minted.add(namespace);
      } catch (e) {
        if (e is StoppedException) rethrow;
        _logger.warning('Could not check $owner:$namespace for a revocation '
            'it is owed this start: $e');
      }
    }
    if (readOnly.isNotEmpty) {
      _logger.info('Not minting or rotating the nskey for $owner in '
          '${readOnly.join(', ')}: this enrollment may only read there, so '
          'that is left to an enrollment that may write there');
    }
    return minted;
  }

  /// The namespaces this client holds a key for and [grants] let it write,
  /// other than those in [named]: `chat.app` under a grant on `app`.
  ///
  /// Empty for the atSign's own credential, whose start asks about no
  /// revocation, and, logged, when the keyfile cannot be read.
  Future<Set<String>> _writableHeld(Map<String, dynamic>? grants,
      {required Set<String> named}) async {
    final filing = privateFiling;
    if (grants == null || filing == null) return const {};
    try {
      return (await filing.readAllWhere((namespace) =>
              !named.contains(namespace) && mayWriteIn(grants, namespace)))
          .keys
          .toSet();
    } catch (e) {
      if (e is StoppedException) rethrow;
      _logger.warning('Could not read which namespace keys this client holds, '
          'so no namespace its grants reach without naming it is checked for '
          'a revocation this start: $e');
      return const {};
    }
  }

  /// Mints, conveys and publishes the key for **one** namespace unless one is
  /// already published, throwing rather than logging, and says what it did.
  ///
  /// The private is pushed to every enrollment listed for the namespace before
  /// the key is published; one the push cannot reach is named in a warning,
  /// and the key is published anyway. A client whose own enrollment carries no
  /// verified key package mints nothing and answers
  /// [NskeySeedOutcome.noKeyPackage]; one with nothing to convey over or file
  /// in answers [NskeySeedOutcome.cannotConvey].
  ///
  /// ⚠️ Concurrent callers of the SAME enrolment are safe only where they share a
  /// mint-lock instance — the wire lock's value is the enrolment id, so two
  /// racers of one enrolment each read back their own and each mint — while
  /// [askRotationPolicy] false suppresses putting an already-published generation
  /// to [rotationPolicy], for a caller that only wants this atSign reachable.
  Future<NskeySeedOutcome> seedNamespace(String owner, String namespace,
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
      return NskeySeedOutcome.alreadyPublished;
    }
    final conveyance = await _conveyanceFor(namespace);
    if (conveyance == null) {
      return _canConvey
          ? NskeySeedOutcome.noKeyPackage
          : NskeySeedOutcome.cannotConvey;
    }
    final minted = await ring.mintAndPublish(namespace,
        conveyFirst: conveyance.convey,
        afterPublish: conveyance.afterPublish,
        lockTtl: conveyance.lockTtlFor(
            margin: ring.lockTtl,
            perMember: ring.lockBudgetPerMember,
            kids: ring.wantedKeyAlgorithms().length,
            conveyances: 2));
    // NOTE: a lost election adopts the winner's generation, which this call
    // neither minted nor conveyed.
    return minted.keys.every((key) => conveyance.conveyedKids.contains(key.kid))
        ? NskeySeedOutcome.minted
        : NskeySeedOutcome.alreadyPublished;
  }

  /// Whether this client has a substrate to convey a private over and a key
  /// source to file one in.
  bool get _canConvey =>
      sharing != null && (privateFiling ?? ring.privateFiling) != null;

  /// The conveyance a mint in [namespace] hands its ring, or null when this
  /// client may mint nothing there, logged.
  Future<PrePublishConveyance?> _conveyanceFor(String namespace) async {
    final sharing = this.sharing;
    final filing = privateFiling ?? ring.privateFiling;
    if (sharing == null || filing == null) {
      _logger.info('Not minting the nskey for $namespace: this client has no '
          '${sharing == null ? 'secret-sharing substrate to convey over' : 'key source to file in'}, '
          'so no other enrollment could be given the private');
      return null;
    }
    return PrePublishConveyance.prepare(sharing, filing, namespace);
  }

  /// Adds this client's own missing key-establishment material to a generation
  /// that already exists, and conveys **only what was added**.
  ///
  /// Failure is logged, not thrown: this atSign is reachable either way, and an
  /// add only buys peers configured for the added algorithm the ability to seal
  /// under it.
  Future<void> _addMissing(
      String owner, String namespace, NskeyAdvertisement published) async {
    final missing = ring.missingKeyAlgorithms(published);
    if (missing.isEmpty) return;
    final conveyance = await _conveyanceFor(namespace);
    if (conveyance == null) return;
    try {
      // NOTE: the ring conveys only what this add mints, before it publishes;
      // an entry already published was conveyed when it was minted.
      await ring.add(namespace,
          conveyFirst: conveyance.convey,
          lockTtl: conveyance.lockTtlFor(
              margin: ring.lockTtl,
              perMember: ring.lockBudgetPerMember,
              kids: missing.length,
              conveyances: 1));
    } catch (e) {
      if (e is StoppedException) rethrow;
      _logger.warning('Could not add this client\'s missing key material to '
          'the nskey for $owner:$namespace; the generation already published '
          'is unchanged and the next start tries again: $e');
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
      if (e is StoppedException) rethrow;
      _logger.warning('The rotation policy asked for a fresh namespace key for '
          '$owner:$namespace and it did not happen; the published generation '
          'is unchanged and the next start will ask again: $e');
      return false;
    }
  }

  /// Rotates [namespace] when a revocation has touched an enrollment granted it
  /// since that namespace's advertisement was last rotated, or when this
  /// client's keyfile records that the published generation owes a rotation,
  /// and returns whether it did.
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
      if (e is StoppedException) rethrow;
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
      if (e is StoppedException) rethrow;
      _logger.warning('A revocation touched $owner:$namespace at $revokedAt, '
          'and what it published could not be read, so nothing is rotated '
          'this start: $e');
      return false;
    }
    if (record == null) return false;

    final owed = await _rotationOwed(owner, namespace, record.advertisement);
    final rotatedAt = record.updatedAt;
    if (!owed && rotatedAt != null && !revokedAt.isAfter(rotatedAt)) {
      return false;
    }

    _logger.info(owed
        ? 'Rotating $owner:$namespace: this keyfile records that '
            '${record.advertisement.nskeyKid} owes a rotation for a '
            'revocation that touched it after it was conveyed'
        : 'Rotating $owner:$namespace: a revocation touched it at '
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
      if (e is StoppedException) rethrow;
      _logger.warning('A revocation touched $owner:$namespace at $revokedAt '
          'and the rotation it owes did not happen; the published generation '
          'is unchanged and the next start asks again: $e');
      return false;
    }
  }

  /// Whether this client's keyfile records that [published] owes a rotation;
  /// false, logged, when the keyfile cannot be read.
  Future<bool> _rotationOwed(
      String owner, String namespace, NskeyAdvertisement published) async {
    final filing = privateFiling;
    if (filing == null) return false;
    try {
      return await filing
          .rotationOwed(namespace, [for (final key in published.keys) key.kid]);
    } catch (e) {
      if (e is StoppedException) rethrow;
      _logger.warning('Could not read whether this keyfile records a rotation '
          '$owner:$namespace owes, so the stamps alone decide this start: $e');
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
        // NOTE: every entry the advertisement carries, not only the one a
        // sender would pick: a key added under a second algorithm, or a
        // generation a rotation retired, opens values this enrollment is owed
        // too, and nothing else asks for its private.
        final missing = <String>[];
        for (final entry in advertised.keys) {
          if (entry.use != SecretSharingAlgos.useEnc ||
              !SecretSharingAlgos.keyAlgos.contains(entry.alg)) {
            continue;
          }
          if (await ring.heldPrivateHalf(owner, namespace, entry.kid) != null) {
            continue;
          }
          missing.add(entry.kid);
        }
        if (missing.isEmpty) continue;
        final names = [
          for (final kid in missing)
            '${NskeyPrivateFiling.secretNamePrefix}$kid'
        ];

        final sent =
            await sharing.requestSecretsFromNamespace(namespace, names: names);
        if (sent == 0) {
          _logger.info('Wanted the nskey private for $owner:$namespace but '
              'found no other key package to ask; the next start retries');
          continue;
        }
        asked.add(namespace);

        // NOTE: never awaited — a holder may be offline for days, and neither
        // this sweep nor the client's start may wait on one.
        for (final kid in missing) {
          final name = '${NskeyPrivateFiling.secretNamePrefix}$kid';
          ring.noteOutstandingAsk(
              namespace,
              kid,
              sharing
                  .waitForSecret(namespace, name,
                      timeout: NskeyPrivateFiling.conveyanceWait)
                  .then((secret) => filing.file(secret))
                  .then((filed) {
                if (filed) {
                  _logger.info('Healed the nskey private $name for '
                      '$owner:$namespace from another enrollment');
                }
              }).catchError((Object e) {
                if (e is StoppedException) {
                  _logger.warning('Stopped waiting for the nskey private $name '
                      'for $owner:$namespace: the client stopped, and the next '
                      'start asks again');
                  return;
                }
                _logger.info('No holder answered for $name in '
                    '$owner:$namespace within the wait; a later answer is '
                    'filed as it arrives ($e)');
              }));
        }
      } catch (e) {
        if (e is StoppedException) rethrow;
        _logger.warning(
            'Could not request the nskey private for $owner:$namespace: $e');
      }
    }
    return asked;
  }

  /// Whether this client holds the private half of every key [advertisement]
  /// offers peers to seal to in [owner]'s [namespace].
  ///
  /// Asks no other enrollment for a private it lacks. False for an
  /// advertisement offering no key at all.
  Future<bool> holdsPrivatesFor(
      String owner, String namespace, NskeyAdvertisement advertisement) async {
    var offered = 0;
    for (final entry in advertisement.keys) {
      // NOTE: every offered entry, not only the one this build would pick: a
      // peer seals under its own algorithm list, so any of them can be chosen.
      if (entry.use != SecretSharingAlgos.useEnc ||
          !entry.offeredForNewOperations) {
        continue;
      }
      offered++;
      if (await ring.heldPrivateHalf(owner, namespace, entry.kid) == null) {
        return false;
      }
    }
    return offered > 0;
  }

  /// Sends every nskey private this client holds, in every namespace [grants]
  /// covers, to one newly approved enrollment.
  ///
  /// [grants] is the enrollment's namespace-to-access map, and covers a
  /// namespace as [SecretStore.namespaceAuthorizes] says: `*`, the namespace
  /// itself, or any namespace it is a dot-suffix of. Read from `AtKeys` rather
  /// than the secret store, which is in-memory by design and holds nothing
  /// after a restart — an approver relying on it would convey a new enrollment
  /// **nothing**.
  ///
  /// An approver holds privates for namespaces it may only read, and cannot
  /// write an envelope into one. [ownGrants] is the approver's own grants, and
  /// a namespace it may not write is skipped up front, with a warning naming
  /// it; null means no recorded limit. Where the atServer still refuses a
  /// write, that private is logged and skipped rather than ending the loop.
  /// Returns how many were sent.
  Future<int> conveyHeldPrivatesTo(
      KeyPackage keyPackage, Map<String, dynamic> grants,
      {required Map<String, dynamic>? ownGrants}) async {
    final sharing = this.sharing;
    final filing = privateFiling;
    if (sharing == null || filing == null) return 0;

    final unwritable = <String>{};
    final held = await filing.readAllWhere((namespace) {
      if (!SecretStore.namespaceAuthorizes(grants, namespace)) return false;
      if (mayWriteIn(ownGrants, namespace)) return true;
      unwritable.add(namespace);
      return false;
    });
    if (unwritable.isNotEmpty) {
      _logger.warning('Not conveying the nskey privates held for '
          '${unwritable.join(', ')} to enrollment ${keyPackage.enrollmentId}: '
          'this approver may not write there, so that enrollment is left to '
          'pull them from another holder');
    }
    int sent = 0;
    for (final MapEntry(key: namespace, value: privates) in held.entries) {
      for (final MapEntry(key: kid, value: seed) in privates.entries) {
        try {
          await sharing.shareSecretWith(
              keyPackage,
              Secret(
                namespace: namespace,
                name: '${NskeyPrivateFiling.secretNamePrefix}$kid',
                value: base64Encode(seed.bytes),
              ),
              inReplyTo: EnvelopeAddressing.unsolicited);
          sent++;
        } on Exception catch (e) {
          if (e is StoppedException) rethrow;
          _logger.warning('Could not convey the nskey private $namespace:$kid '
              'to the new enrollment, going on with the rest: $e');
        }
      }
    }
    return sent;
  }
}
