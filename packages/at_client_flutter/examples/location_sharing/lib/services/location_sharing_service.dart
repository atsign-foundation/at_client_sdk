import 'dart:async';

import 'package:at_client/at_client.dart';

import '../models/location_share.dart';

typedef LocationProvider = Future<LocationPoint?> Function();

class LocationSharingService {
  LocationSharingService({
    required this.atClient,
    required this.locationProvider,
  }) {
    _sharedWithMeController =
        StreamController<List<CItem<LocationShare>>>.broadcast(
          onListen: () {
            final latest = _latestSharedWithMe;
            if (latest != null) _sharedWithMeController.add(latest);
          },
        );
    _ownedByMeController =
        StreamController<List<CItem<LocationShare>>>.broadcast(
          onListen: () {
            final latest = _latestOwnedByMe;
            if (latest != null) _ownedByMeController.add(latest);
          },
        );
  }

  static const namespaceSuffix = 'location_sharing.demos';
  static const defaultExpiration = Duration(minutes: 30);

  final AtClient atClient;
  final LocationProvider locationProvider;

  late final AtCollection<LocationShare> shares;

  final StreamController<bool> _publishStateController =
      StreamController<bool>.broadcast();
  late final StreamController<List<CItem<LocationShare>>>
  _sharedWithMeController;
  late final StreamController<List<CItem<LocationShare>>> _ownedByMeController;

  List<CItem<LocationShare>>? _latestSharedWithMe;
  List<CItem<LocationShare>>? _latestOwnedByMe;
  StreamSubscription<CEvent>? _sharesSubscription;
  Future<void> _refreshQueue = Future<void>.value();

  Atsign get self => atClient.atSign;

  Future<void> init() async {
    await setUpCollections();
    _sharesSubscription = shares.watch().listen(
      (_) => _queueRefresh(),
      onError: (Object error, StackTrace stackTrace) {
        _addListError(error, stackTrace);
      },
    );
    await _refreshShareStreams();
    _publishStateController.add(false);
  }

  Future<void> setUpCollections() async {
    final namespace = atClient.getPreferences()!.namespace!;
    shares = await atClient.collection<LocationShare>(
      'shares.$namespace',
      defaultExpiration,
      eventSource: EventSource.both,
      fromJson: LocationShare.fromJson,
      typeTag: 'LocationShare',
      cleanupOrphansOnCreation: true,
    );
  }

  Stream<List<CItem<LocationShare>>> watchSharesSharedWithMe() {
    return _sharedWithMeController.stream;
  }

  Stream<List<CItem<LocationShare>>> watchSharesOwnedByMe() {
    return _ownedByMeController.stream;
  }

  Query<LocationShare> _activeSharesSharedWithMeQuery() {
    return shares
        .query()
        .where((item) => item.owner != self)
        .wherePath(LocationShareFields.status.eq(LocationShareStatus.active))
        .orderBy((item) => item.obj.updatedAt, descending: true);
  }

  Query<LocationShare> _activeSharesOwnedByMeQuery() {
    return shares
        .query()
        .where((item) => item.owner == self)
        .wherePath(LocationShareFields.status.eq(LocationShareStatus.active))
        .orderBy((item) => item.obj.updatedAt, descending: true);
  }

  void _emitSharedWithMe(List<CItem<LocationShare>> shares) {
    _latestSharedWithMe = shares;
    if (!_sharedWithMeController.isClosed) {
      _sharedWithMeController.add(shares);
    }
  }

  void _emitOwnedByMe(List<CItem<LocationShare>> shares) {
    _latestOwnedByMe = shares;
    if (!_ownedByMeController.isClosed) {
      _ownedByMeController.add(shares);
    }
  }

  void _queueRefresh() {
    _refreshQueue = _refreshQueue.then((_) => _refreshShareStreams());
    unawaited(_refreshQueue);
  }

  Future<void> _refreshShareStreams() async {
    try {
      _emitSharedWithMe(await _activeSharesSharedWithMeQuery().get());
    } catch (error, stackTrace) {
      if (!_sharedWithMeController.isClosed) {
        _sharedWithMeController.addError(error, stackTrace);
      }
    }

    try {
      _emitOwnedByMe(await _activeSharesOwnedByMeQuery().get());
    } catch (error, stackTrace) {
      if (!_ownedByMeController.isClosed) {
        _ownedByMeController.addError(error, stackTrace);
      }
    }
  }

  void _addListError(Object error, StackTrace stackTrace) {
    if (!_sharedWithMeController.isClosed) {
      _sharedWithMeController.addError(error, stackTrace);
    }
    if (!_ownedByMeController.isClosed) {
      _ownedByMeController.addError(error, stackTrace);
    }
  }

  Stream<CItem<LocationShare>?> watchShare({
    required String id,
    required Atsign owner,
  }) {
    return shares
        .query()
        .where((item) => item.id == id && item.owner == owner)
        .watch()
        .map((items) => items.isEmpty ? null : items.first);
  }

  Stream<bool> watchPublishState() => _publishStateController.stream;

  Future<CItem<LocationShare>> startSharingWith(
    Atsign atSign, {
    Duration duration = defaultExpiration,
  }) async {
    final now = DateTime.now().toUtc();
    final point = await locationProvider();
    final share = await shares.create(
      obj: LocationShare(
        status: LocationShareStatus.active,
        latestPoint: point,
        updatedAt: now,
      ),
      sharedWith: {atSign},
      expiresAt: now.add(duration),
    );
    await _publishCurrentLocationIfAvailable();
    return share;
  }

  Future<void> stopSharingWith(Atsign atSign) async {
    final ownedShares = await shares
        .query()
        .where((item) => item.owner == self)
        .where((item) => item.sharedWith.contains(atSign))
        .get();

    for (final share in ownedShares) {
      final updatedAudience = Set<Atsign>.from(share.sharedWith)
        ..remove(atSign);
      if (updatedAudience.isEmpty) {
        await shares.delete(share);
      } else {
        await shares.updateSharedWith(share, updatedAudience);
      }
    }
  }

  Future<void> publishFromProvider() async {
    await _publishCurrentLocationIfAvailable();
  }

  Future<void> publishCurrentLocation(LocationPoint point) async {
    _publishStateController.add(true);
    try {
      final ownedShares = await shares
          .query()
          .where((item) => item.owner == self)
          .wherePath(LocationShareFields.status.eq(LocationShareStatus.active))
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
            sharedWith: Set<Atsign>.from(share.sharedWith),
            expiresAt: share.expiresAt,
          ),
        );
      }
    } finally {
      _publishStateController.add(false);
    }
  }

  Future<void> _publishCurrentLocationIfAvailable() async {
    final point = await locationProvider();
    if (point == null) return;
    await publishCurrentLocation(point);
  }

  void dispose() {
    _sharesSubscription?.cancel();
    _sharedWithMeController.close();
    _ownedByMeController.close();
    _publishStateController.close();
  }
}
