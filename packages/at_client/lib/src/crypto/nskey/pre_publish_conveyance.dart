import 'dart:convert' show base64Encode;

import 'package:at_client/src/client/server_mutex.dart' show maxServerMutexTtl;
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
import 'package:at_client/src/secret_sharing/enrollment_directory.dart';
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart'
    show PairwiseSecretSharing;
import 'package:at_client/src/secret_sharing/secret_store.dart' show Secret;
import 'package:at_commons/at_commons.dart' show StoppedException;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('PrePublishConveyance');

/// Conveys a generation's privates to the enrollments listed for its namespace
/// before the generation is published, so publishing is the commit point.
///
/// [prepare] reads the roster before the mint lock is taken, which sizes the
/// lock as a ceiling ([lockTtlFor]); [convey] is what a mint hands the ring as
/// `conveyFirst`.
@experimental
class PrePublishConveyance {
  final PairwiseSecretSharing sharing;
  final NskeyPrivateFiling filing;
  final String namespace;

  /// The enrollments listed for [namespace] when the conveyance was prepared.
  final List<NamespaceMember> roster;

  /// The namespace's last revocation when the conveyance was prepared; null
  /// when none, or when it could not be read.
  final DateTime? revokedAt;

  /// Whether [revokedAt] was read, so a revocation can be told from a value
  /// that was never known.
  final bool revocationKnown;

  /// Enrollments conveyed nothing even while listed: a rotation's revoked one.
  final Set<String> excludeEnrollmentIds;

  /// The generations [convey] has conveyed.
  final Set<String> conveyedKids = {};

  /// How many key packages the last push reached.
  int pushedTo = 0;

  PrePublishConveyance._(this.sharing, this.filing, this.namespace, this.roster,
      this.revokedAt, this.revocationKnown, this.excludeEnrollmentIds);

  /// Reads [namespace]'s roster and last revocation, or answers null when this
  /// client's own entry carries no verified key package, so it can be conveyed
  /// nothing and mints nothing.
  static Future<PrePublishConveyance?> prepare(PairwiseSecretSharing sharing,
      NskeyPrivateFiling filing, String namespace,
      {Set<String> excludeEnrollmentIds = const {}}) async {
    final roster = await sharing.directory.listForNamespace(namespace);
    _logger.info('The roster for $namespace before minting: '
        '${roster.map((m) => '${m.enrollmentId} ${m.keyPackageStatus.name} '
            'kpid ${m.keyPackage?.kpid}').join('; ')}');
    final selfId = sharing.enrollmentId;
    final self = roster.where((m) => m.enrollmentId == selfId).firstOrNull;
    if (self == null || self.keyPackageStatus != KeyPackageStatus.present) {
      _logger.info('Not minting the nskey for $namespace: this enrollment '
          '($selfId) carries no verified key package in its record, so it '
          'can be conveyed no private and mints none');
      return null;
    }
    DateTime? revokedAt;
    var revocationKnown = true;
    try {
      revokedAt = await sharing.directory.lastRevokedAt(namespace);
    } catch (e) {
      if (e is StoppedException) rethrow;
      revocationKnown = false;
      _logger.info('Could not read when $namespace was last revoked, so a '
          'revocation during this mint cannot be detected: $e');
    }
    return PrePublishConveyance._(sharing, filing, namespace, roster, revokedAt,
        revocationKnown, excludeEnrollmentIds);
  }

  /// The mint lock's ttl: [margin], the ring's own, plus [perMember] for each
  /// listed enrollment, and never more than an atServer mutex allows.
  Duration lockTtlFor({required Duration margin, required Duration perMember}) {
    final sized = margin + perMember * roster.length;
    return sized > maxServerMutexTtl ? maxServerMutexTtl : sized;
  }

  /// Conveys the filed private of each of [nskeyKids] to every enrollment
  /// listed for the namespace, then refuses the publish, retiring what it
  /// filed, if a revocation touched the namespace since [prepare].
  Future<void> convey(List<String> nskeyKids) async {
    for (final nskeyKid in nskeyKids) {
      final seed = await filing.readSeed(namespace, nskeyKid);
      if (seed == null) {
        throw StateError('the nskey private $namespace:$nskeyKid cannot be '
            'read back, so it is not conveyed and the generation is not '
            'published');
      }
      final secret = Secret(
        namespace: namespace,
        name: '${NskeyPrivateFiling.secretNamePrefix}$nskeyKid',
        value: base64Encode(seed.bytes),
      );
      // NOTE: into this client's own store as well, which the request-answer
      // path serves from.
      await sharing.secretStore.putIfNewer(secret);
      pushedTo = await sharing.pushSecretToNamespaceMembers(secret,
          excludeEnrollmentIds: excludeEnrollmentIds);
      _logger.info('Conveyed the $namespace private $nskeyKid to $pushedTo '
          'key package(s) before publishing it');
      conveyedKids.add(nskeyKid);
    }
    if (!revocationKnown) return;
    final DateTime? now;
    try {
      now = await sharing.directory.lastRevokedAt(namespace);
    } catch (e) {
      if (e is StoppedException) rethrow;
      _logger.info('Could not re-read when $namespace was last revoked, so the '
          'mint publishes on what it read before: $e');
      return;
    }
    if (now != revokedAt) {
      await filing.retire(namespace, nskeyKids);
      throw StateError('a revocation touched $namespace at $now, after this '
          'mint read its roster, so the generation '
          '${nskeyKids.join(', ')} is not published and is retired: an '
          'enrollment revoked meanwhile may hold it. The next mint is a fresh '
          'one');
    }
  }
}
