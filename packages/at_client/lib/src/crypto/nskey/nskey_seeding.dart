import 'dart:async' show unawaited;
import 'dart:convert' show base64Encode;
import 'dart:typed_data' show Uint8List;

import 'package:at_client/at_client.dart' show AtClient;
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
import 'package:at_client/src/crypto/nskey/published_nskey_key_ring.dart';
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart'
    show PairwiseSecretSharing;
import 'package:at_client/src/secret_sharing/key_package.dart' show KeyPackage;
import 'package:at_client/src/secret_sharing/secret_store.dart' show Secret;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental, visibleForTesting;

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
  /// not a list that can be minted — a wildcard enrollment mints on demand
  /// when it writes into a specific one instead. `__manage` is skipped for the
  /// same reason it is not an app namespace.
  @visibleForTesting
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
        if (await ring.currentPublic(owner, namespace) != null) continue;
        final advertisement = await ring.mintAndPublish(namespace);
        minted.add(namespace);
        await _convey(namespace, advertisement.nskeyKid);
      } catch (e) {
        // One namespace failing must not stop the others: a partly seeded
        // atSign is strictly better than an unseeded one, and the next start
        // retries whatever is still missing.
        _logger.warning('Could not seed $owner:$namespace this start: $e');
      }
    }
    return minted;
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
    final Map<String, Map<String, Uint8List>> held;
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
          value: base64Encode(entry.value),
        ));
        hydrated++;
      }
    }
    return hydrated;
  }

  /// Pulls the nskey privates this enrollment is entitled to and does not
  /// hold, from whichever enrollments currently do.
  ///
  /// The other half of the self-heal ruling (`decisions.md` 38): [seed] mints
  /// when no key exists; this asks when one does. It is what heals an
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
            .waitForSecret(namespace, name, timeout: const Duration(minutes: 5))
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
              value: base64Encode(entry.value),
            ));
        sent++;
      }
    }
    return sent;
  }

  /// Sends the minted private to the atSign's other enrollments.
  ///
  /// Read back from the durable store rather than passed along from the mint:
  /// what is conveyed is then exactly what this client will itself use, and a
  /// private that failed to persist is never sent to anyone.
  Future<void> _convey(String namespace, String nskeyKid) async {
    final sharing = this.sharing;
    final private = await privateFiling?.read(namespace, nskeyKid);
    if (sharing == null || private == null) return;

    await sharing.pushSecretToNamespaceMembers(Secret(
      namespace: namespace,
      name: '${NskeyPrivateFiling.secretNamePrefix}$nskeyKid',
      value: base64Encode(private),
    ));
  }
}
