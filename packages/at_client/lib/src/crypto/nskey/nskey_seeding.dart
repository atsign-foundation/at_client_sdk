import 'dart:async' show unawaited;
import 'dart:convert' show base64Encode;

import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart' show NskeySeed;
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
/// **Why at start rather than on first write.** The rollout mints and
/// publishes while clients are still *writing legacy*, so that by the time the
/// PQ flag flips the keys are already everywhere. Minting on first write would
/// seed only as traffic happened, leaving early senders cold-starting against
/// recipients who simply had not written yet. It is also what makes the
/// sender-side rule honest: if a recipient has ever run a PQ-capable client
/// for a namespace, the key is there.
///
/// Seeding is best-effort by construction. A namespace that cannot be minted
/// now is minted at the next start, and a cold-start failure on the write path
/// is already a named, recoverable error — so nothing here throws into a
/// client's startup.
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

  NskeySeeding({
    required this.atClient,
    required this.ring,
    this.sharing,
    this.privateFiling,
  });

  /// The namespaces this client should hold a key for.
  ///
  /// An APKAM client is told by its own enrollment record — the atServer
  /// returns only that record unless the caller holds `__manage`. A legacy
  /// PKAM client has no enrollment at all and can name exactly one namespace,
  /// its `preference.namespace`; those clients are most of the fleet during
  /// the rollout, so that is where seeding coverage actually comes from.
  ///
  /// `*` is skipped. It authorises every namespace, and "every namespace" is
  /// not a list that can be minted. `__manage` is skipped for the same reason
  /// it is not an app namespace.
  ///
  /// ⚠️ **A wildcard enrollment therefore seeds NOTHING, and nothing else
  /// mints for it.** This said "a wildcard enrollment mints on demand when it
  /// writes into a specific one instead", and there is no such path: the only
  /// production caller of `PublishedNskeyKeyRing.mintAndPublish` is [seed]
  /// below, and the ring's `_mintUnlessPublished` is reachable only from that
  /// same method. Writing does not mint — an outbound share resolves the
  /// **recipient's** nskey (`NskeyProvider._nskeyOwnerOf` is
  /// `atKey.sharedWith ?? recordOwner`), so a sender consults its own key only
  /// for self data, and consulting is not minting.
  ///
  /// The consequence is that an atSign reachable only through a wildcard
  /// enrollment publishes no advertisement, so nobody can seal to it in any
  /// namespace. Whether that is reachable in practice depends on what the
  /// atServer grants a first enrollment, which is not this package's to
  /// assert.
  ///
  /// No longer test-only: `AtClient.ensureReachable` asks this to tell "this
  /// enrollment cannot hold a key for that namespace" apart from "the mint
  /// failed". Without the distinction a wildcard-only enrollment — which is
  /// what a first CRAM onboard produces — reports an error for a namespace it
  /// was never going to seed, which is the wrong thing to hand an app author
  /// hunting a failure.
  Future<Set<String>> authorisedNamespaces() async {
    final enrollmentId = atClient.getRemoteSecondary()?.atLookUp.enrollmentId;
    if (enrollmentId == null || enrollmentId.isEmpty) {
      final own = atClient.getPreferences()?.namespace;
      return (own == null || own.isEmpty) ? const {} : {own};
    }

    try {
      final mine = (await atClient.enrollmentService!.fetchEnrollmentRequests())
          .where((e) => e.enrollmentId == enrollmentId);
      return {
        for (final enrollment in mine)
          ...?enrollment.namespace?.keys.where(_isSeedable)
      };
    } catch (e) {
      _logger.info('Could not read this enrollment to find its namespaces, so '
          'nothing is seeded this start: $e');
      return const {};
    }
  }

  static bool _isSeedable(String namespace) =>
      namespace != '*' && namespace != '__manage' && namespace.isNotEmpty;

  /// Mints and publishes for every authorised namespace that has no key yet,
  /// then conveys each new private. Returns the namespaces minted.
  Future<Set<String>> seed() async {
    final owner = atClient.getCurrentAtSign();
    if (owner == null) return const {};

    final minted = <String>{};
    for (final namespace in await authorisedNamespaces()) {
      try {
        if (await seedNamespace(owner, namespace)) minted.add(namespace);
      } catch (e) {
        // One namespace failing must not stop the others: a partly seeded
        // atSign is strictly better than an unseeded one, and the next start
        // retries whatever is still missing.
        _logger.warning('Could not seed $owner:$namespace this start: $e');
      }
    }
    return minted;
  }

  /// Mints, publishes and conveys the key for **one** namespace, unless one is
  /// already published. Returns whether this call minted.
  ///
  /// Split out of [seed] so a caller that wants a single namespace ready —
  /// `AtClient.ensureReachable` — does not have to seed every other namespace
  /// this enrollment happens to be authorised for as a side effect of asking
  /// about one.
  ///
  /// Throws rather than logging: [seed] contains a failure so that one
  /// namespace cannot stop the others, while a caller asking about one
  /// namespace wants the reason.
  ///
  /// Safe to call concurrently with [seed] and with another client's mint. The
  /// published check below and the mint lock inside [PublishedNskeyKeyRing.mintAndPublish]
  /// both re-read under the lock, so the loser adopts rather than minting a
  /// second generation.
  Future<bool> seedNamespace(String owner, String namespace) async {
    // The atServer, not local storage: a namespace another enrollment minted a
    // moment ago is absent locally until sync catches up, and reading that
    // absence as a cold start is what publishes a second key over the first.
    if (await ring.publishedAdvertisement(owner, namespace) != null) {
      return false;
    }
    final advertisement = await ring.mintAndPublish(namespace);

    // ⚠️ **The conveyance is guarded separately, and the boundary is the
    // point.** Publishing is what makes this atSign reachable — a peer seals
    // to the advertisement and needs nothing else. Conveying is what gives
    // this atSign's OTHER enrollments the private half, and an enrollment that
    // misses the push pulls at its next start. So a conveyance failure is not
    // a failure to seed, and reporting it as one tells a caller its atSign is
    // unreachable when it is reachable.
    //
    // Not hypothetical: a legacy PKAM client has no APKAM keypair, the
    // conveyance enumerates members with `enroll:listns`, and the atServer
    // refuses that without APKAM authentication. Measured 2026-08-27, where it
    // turned a successful publish into a reported failure.
    try {
      await _convey(namespace, advertisement.nskeyKid);
    } catch (e) {
      _logger.warning(
          'Published the nskey for $owner:$namespace, but could not convey '
          'its private to this atSign\'s other enrollments — they will pull '
          'it at their next start. Peers can seal here either way: $e');
    }
    return true;
  }

  /// Primes the in-memory secret store with the nskey privates this client
  /// holds durably, so the request-answer path can serve them.
  ///
  /// The pull's answering side reads the SECRET STORE, and the store is a
  /// transit buffer: in memory, empty after every restart. Without this, a
  /// holder that had restarted since the mint held the private in AtKeys and
  /// answered requests with nothing — the self-heal's whole supply side gone,
  /// invisibly, the moment the minting process exited. (Found by the live
  /// two-enrollment test, not by any unit test: the unit fixtures put secrets
  /// straight into the store, which is exactly the state a restart destroys.)
  ///
  /// Idempotent: nskey privates are immutable per generation, so re-priming
  /// the same name is a no-op under `putIfNewer`. Returns how many were
  /// primed.
  Future<int> hydrateStoreFromFiling(PairwiseSecretSharing sharing) async {
    final filing = privateFiling;
    if (filing == null) return 0;

    int hydrated = 0;
    // Off the keyfile, not off the enrollment record. What a holder can answer
    // with is what it HOLDS; asking the atServer which namespaces it is
    // authorised for would add a round trip, and — because this runs during
    // client construction, before the manager has wired the enrollment
    // service — would fail and silently prime nothing.
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

  /// Pulls the nskey privates this enrollment is entitled to and does not
  /// hold, from whichever enrollments currently do.
  ///
  /// The other half of the self-heal: [seed] mints when no key exists, and
  /// this asks when one does. It is what heals an
  /// enrollment that missed the mint-time push — a device approved after the
  /// namespace was minted, a clone upgrading late — and it runs at client
  /// start, unconditionally on any client that can file the answer, because
  /// "created after the mint" is the ordinary second device and not an edge.
  ///
  /// Broadcast to the namespace's key packages, not addressed to the minter:
  /// any current holder answers, and the creator may be long gone. Both legs
  /// are store-and-forward, so nothing needs two devices up at once. When an
  /// answer arrives while this client still runs it is filed immediately;
  /// one that arrives later is filed by the next start's sweep.
  ///
  /// Returns the namespaces a request went out for.
  Future<Set<String>> requestMissingPrivates(
      PairwiseSecretSharing sharing) async {
    final owner = atClient.getCurrentAtSign();
    final filing = privateFiling;
    if (owner == null || filing == null) return const {};

    final asked = <String>{};
    for (final namespace in await authorisedNamespaces()) {
      try {
        final advertised = await ring.currentPublic(owner, namespace);
        // No published key is cold start — minting's business, not pulling's.
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

        // File the answer the moment it lands, so the heal completes within
        // this run rather than at the next start. Unawaited: a holder may be
        // offline for days, and this client's start (and this sweep) must not
        // wait on that.
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
        // One namespace failing must not stop the others, matching [seed].
        _logger.warning(
            'Could not request the nskey private for $owner:$namespace: $e');
      }
    }
    return asked;
  }

  /// Sends every nskey private this client holds for [approvedNamespaces] to
  /// one newly approved enrollment.
  ///
  /// Reads them from `AtKeys` rather than the secret store. The store is a
  /// transit buffer and is in-memory by design, so after a restart it holds
  /// nothing — an approver relying on it would convey a new enrollment
  /// **nothing**, including the very privates without which it can read
  /// anything at all.
  Future<int> conveyHeldPrivatesTo(
      KeyPackage keyPackage, Iterable<String> approvedNamespaces) async {
    final sharing = this.sharing;
    final filing = privateFiling;
    if (sharing == null || filing == null) return 0;

    int sent = 0;
    for (final namespace in approvedNamespaces.where(_isSeedable)) {
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
  /// Read back from the durable store rather than passed along from the mint:
  /// what is conveyed is then exactly what this client will itself use, and a
  /// private that failed to persist is never sent to anyone.
  ///
  /// The store write is what lets the minter serve a later pull. The answering
  /// path reads the secret store (`_candidatesFor`), and the store is filled
  /// from the filing only by `hydrateStoreFromFiling` at bootstrap — which
  /// runs before the mint, not after. Without this the enrollment that minted
  /// the generation holds it in its filing, offers an empty candidate list to
  /// every request for it, and answers nothing until the process restarts:
  /// silently, because a holder with no matching candidate writes no envelope
  /// and logs nothing.
  ///
  /// It grants no access the push below does not already grant — that fans
  /// these exact bytes, unsolicited, to every key package on the same roster,
  /// so serving them to a roster member that *asks* is strictly less.
  ///
  /// ⚠️ Not closed here: `PublishedNskeyKeyRing._mint` is a second mint path
  /// that never reaches this method, so a generation minted during rotation
  /// still leaves that client's store unprimed. The ring holds no sharing
  /// instance, so closing it there is a wider change than this.
  Future<void> _convey(String namespace, String nskeyKid) async {
    final sharing = this.sharing;
    // The SEED, never the expanded decapsulation key: the receiver validates
    // an arrival by re-deriving the published public half from it, which only
    // the seed can do. For X-Wing the two are the same bytes, which is the
    // accident that let this path read the expanded form and still work; for
    // ML-KEM the expanded form is refused on arrival and the other
    // enrollments never get the key.
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
