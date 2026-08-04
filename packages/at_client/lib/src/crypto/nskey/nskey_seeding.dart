import 'dart:convert' show base64Encode;

import 'package:at_client/at_client.dart' show AtClient;
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
import 'package:at_client/src/crypto/nskey/published_nskey_key_ring.dart';
import 'package:at_client/src/crypto/rollout/crypto_rollout.dart';
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

  /// Publishes the capability marker alongside the namespace key. Both are
  /// rollout actions for the same namespace list, so they share the one round
  /// trip that establishes it.
  final CryptoRollout rollout;

  NskeySeeding({
    required this.atClient,
    required this.ring,
    this.sharing,
    this.privateFiling,
    CryptoRollout? rollout,
  }) : rollout = rollout ?? CryptoRollout(atClient);

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

  /// Advertises this atSign as not-ready, then mints and publishes for every
  /// authorised namespace that has no key yet, conveying each new private.
  /// Returns the namespaces minted.
  ///
  /// The two halves are the same rollout step seen from the two sides of a
  /// write: the key is what a *sender* seals to, the marker is what tells that
  /// sender whether it may. Publishing the key without the marker leaves the
  /// atSign readable-to but never negotiated-with; publishing the marker
  /// without the key would advertise a scheme with nothing to seal to. They
  /// also share the round trip that establishes which namespaces this client is
  /// authorised for, which is the expensive part.
  Future<Set<String>> seed() async {
    final owner = atClient.getCurrentAtSign();
    if (owner == null) return const {};

    final minted = <String>{};
    for (final namespace in await authorisedNamespaces()) {
      try {
        // Before the `continue` below, because a namespace whose key already
        // exists may still have no marker — and an atSign nobody can negotiate
        // with is one nobody ever writes post-quantum to.
        await rollout.publishNotReadyIfAbsent(namespace);

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
