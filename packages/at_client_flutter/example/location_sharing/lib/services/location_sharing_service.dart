import 'package:at_client/at_client.dart';

import '../models/location_share.dart';

/// All `AtCollection<LocationShare>` interaction for this example lives
/// here. It wraps one collection — `shares.<namespace>` — and exposes three
/// things an app needs for a location-sharing feature: starting a share,
/// publishing fresh points to it, and watching both directions (shares this
/// atSign owns, and shares other atSigns have sent it).
///
/// Takes an already-open [shares] rather than opening one itself, so tests
/// can hand it a collection wired to injected event streams (see
/// `collectionWithInjectedNotifications` in `package:at_client`) without
/// mocking `AtClient.collection`.
class LocationSharingService {
  LocationSharingService({required this.shares});

  static const namespaceSuffix = 'location_sharing';
  static const defaultExpiration = Duration(hours: 1);

  /// Opens the `shares.<namespace>` collection this service wraps.
  static Future<AtCollection<LocationShare>> openCollection(AtClient atClient) {
    final namespace = atClient.getPreferences()!.namespace!;
    return atClient.collection<LocationShare>(
      'shares.$namespace',
      defaultExpiration,
      fromJson: LocationShare.fromJson,
      typeTag: 'LocationShare',
      cleanupOrphansOnCreation: true,
    );
  }

  final AtCollection<LocationShare> shares;

  Atsign get self => shares.atSign;

  /// Live list of active shares another atSign has sent to [self].
  Stream<List<CItem<LocationShare>>> watchSharesSharedWithMe() {
    return _activeSharesQuery().where((item) => item.owner != self).watch();
  }

  /// Live list of active shares [self] owns (one per recipient audience
  /// started via [startSharingWith]).
  Stream<List<CItem<LocationShare>>> watchSharesOwnedByMe() {
    return _activeSharesQuery().where((item) => item.owner == self).watch();
  }

  Query<LocationShare> _activeSharesQuery() {
    return shares
        .query()
        .wherePath($LocationShare.status.eq(LocationShareStatus.active))
        .orderBy((item) => item.obj.updatedAt, descending: true);
  }

  /// Starts a new share with [atSign], seeded with [point] if one is
  /// available yet. Returns the created item; call [publishCurrentLocation]
  /// afterwards to keep it updated.
  Future<CItem<LocationShare>> startSharingWith(
    Atsign atSign, {
    LocationPoint? point,
    Duration expiresIn = defaultExpiration,
  }) {
    return shares.create(
      obj: LocationShare(
        status: LocationShareStatus.active,
        latestPoint: point,
        updatedAt: DateTime.now().toUtc(),
      ),
      sharedWith: {atSign},
      expiresAt: DateTime.now().toUtc().add(expiresIn),
    );
  }

  /// Stops sharing with [atSign]: removes it from every owned share's
  /// audience, deleting shares that would otherwise end up with no
  /// recipients.
  Future<void> stopSharingWith(Atsign atSign) async {
    final ownedShares = await shares
        .query()
        .where((item) => item.owner == self && item.sharedWith.contains(atSign))
        .get();

    for (final share in ownedShares) {
      final remaining = Set<Atsign>.from(share.sharedWith)..remove(atSign);
      if (remaining.isEmpty) {
        await shares.delete(share);
      } else {
        await shares.updateSharedWith(share, remaining);
      }
    }
  }

  /// Pushes [point] as the latest position on every active share [self]
  /// owns. A periodic caller (e.g. a `Timer`) drives the "live" feel of the
  /// demo.
  ///
  /// Each publish also renews the share's `expiresAt` to `now +
  /// [defaultExpiration]`. Without this, a share created with the default
  /// one-hour expiry would vanish for the recipient an hour after
  /// [startSharingWith] even though the owner's `Timer` keeps publishing
  /// fresh points — a live share is expected to last as long as the owner
  /// keeps it alive, not for a fixed window from creation.
  Future<void> publishCurrentLocation(LocationPoint point) async {
    final ownedShares = await shares
        .query()
        .where((item) => item.owner == self)
        .wherePath($LocationShare.status.eq(LocationShareStatus.active))
        .get();

    final now = DateTime.now().toUtc();
    for (final share in ownedShares) {
      await shares.update(
        shares.draft(
          obj: LocationShare(
            status: share.obj.status,
            latestPoint: point,
            updatedAt: now,
          ),
          id: share.id,
          sharedWith: share.sharedWith,
          expiresAt: now.add(defaultExpiration),
        ),
      );
    }
  }
}
