import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/src/storage/at_client_storage.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/secondary_address_finder_source.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/service/enrollment_service.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_client/src/listener/switch_at_sign_event.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_lookup/at_lookup_io.dart';
import 'package:at_utils/at_utils.dart';
import 'package:meta/meta.dart';

/// Holds the current [AtClient] and tells the switch listeners when it
/// changes.
///
/// ```dart
/// final client = await Atsign('@alice').open(keys: keys, preference: preference);
/// AtClientManager.getInstance().use(client);
/// ```
///
/// `AtClientManager.getInstance().atClient` is the current client; its
/// `syncService` and `notificationService` are that client's.
class AtClientManager {
  final AtSignLogger _logger = AtSignLogger('AtClientManager');

  late String _atSign;
  AtClient? _currentAtClient;

  AtClient get atClient {
    if (_currentAtClient == null) {
      throw StateError('No atClient yet');
    } else {
      return _currentAtClient!;
    }
  }

  @Deprecated('Use atClientManager.atClient.syncService')
  SyncService get syncService => atClient.syncService;

  @Deprecated('Use atClientManager.atClient.notificationService')
  NotificationService get notificationService => atClient.notificationService;

  SecondaryAddressFinder? secondaryAddressFinder;
  final _changeListeners = <AtSignChangeListener>[];

  static final AtClientManager _singleton = AtClientManager._internal();

  AtClientManager._internal() {
    _registerAddressFinderSource();
  }

  factory AtClientManager.getInstance() {
    return _singleton;
  }

  // ignore: no_leading_underscores_for_local_identifiers
  AtClientManager(this._atSign) {
    _registerAddressFinderSource();
  }

  /// Points `RemoteSecondary`'s process-wide finder source at the singleton
  /// manager's field, so it need not import this class. Every constructor
  /// registers the same closure, so registering again is harmless.
  static void _registerAddressFinderSource() {
    registerSecondaryAddressFinderSource(
        () => AtClientManager.getInstance().secondaryAddressFinder);
  }

  void setSecondaryAddressFinder(
      {SecondaryAddressFinder? secondaryAddressFinder}) {
    if (secondaryAddressFinder != null) {
      this.secondaryAddressFinder = secondaryAddressFinder;
    }
  }

  /// Makes [client], which the caller built and owns, the current client.
  ///
  /// The previous current client is not stopped: it is its owner's to stop,
  /// and an application that keeps two clients open and switches between
  /// them has not finished with either. The switch listeners are notified.
  /// Making the current client current again does nothing.
  void use(AtClient client) {
    final previous = _currentAtClient;
    if (identical(previous, client)) return;
    _atSign = client.getCurrentAtSign()!;
    _currentAtClient = client;
    _logger.info('use: ${previous?.getCurrentAtSign()} -> $_atSign');
    _notifyListeners(SwitchAtSignEvent(previous, client));
  }

  void listenToAtSignChange(AtSignChangeListener listener) {
    if (!_changeListeners.contains(listener)) {
      _changeListeners.add(listener);
    }
  }

  void _notifyListeners(SwitchAtSignEvent switchAtSignEvent) {
    // Copying the items in _changeListener to a new list to avoid
    // concurrent modification exception when removing the previous
    // atSign listeners
    List<AtSignChangeListener> copyOfChangeListeners =
        List.from(_changeListeners);
    for (var listener in copyOfChangeListeners) {
      listener.listenToAtSignChange(switchAtSignEvent);
    }
  }

  /// Removes the given listener from the list of listeners,
  /// that are notified whenever the @sign is switched
  void removeChangeListeners(AtSignChangeListener atSignChangeListener) {
    _changeListeners.remove((atSignChangeListener));
  }

  /// NOT A PART of API. Added for unit tests
  @visibleForTesting
  int getChangeListenersSize() {
    return _changeListeners.length;
  }

  /// NOT A PART of API. Added for unit tests
  @visibleForTesting
  Iterator<dynamic> getItemsInChangeListeners() {
    return _changeListeners.iterator;
  }

  /// NOT A PART of API. Added for unit tests
  @visibleForTesting
  void removeAllChangeListeners() {
    _changeListeners.clear();
  }

  // NOT a part of API. For functional tests.
  void reset() {
    removeAllChangeListeners();
    _currentAtClient = null;
  }
}

/// Abstraction over the construction of the core services managed by [AtClientManager].
///
/// The default production implementation is [DefaultAtServiceFactory].
/// Override this in tests to inject fakes or mocks without subclassing [AtClientManager].
abstract class AtServiceFactory {
  Future<AtClient> atClient(
    String atSign,
    String? namespace,
    AtClientPreference preference,
    AtClientManager atClientManager, {
    AtKeysIo? atKeysIo,
    AtLookUp? atLookUp,
    AtLookUpFactory? lookUps,
    String? enrollmentId,
    required AtClientStorage storage,
  });

  Future<NotificationService> notificationService(
      AtClient atClient,
      @Deprecated('no longer needed. will be removed in a future release')
      AtClientManager atClientManager,
      {SecondaryAddressFinder? secondaryAddressFinder});

  /// The [notificationService] parameter is ignored — the sync service retrieves
  /// its notification dependency directly from [atClient] after construction.
  Future<SyncService> syncService(AtClient atClient,
      AtClientManager atClientManager, NotificationService notificationService);

  EnrollmentService enrollmentService(AtClient atClient);
}

class DefaultAtServiceFactory implements AtServiceFactory {
  @override
  Future<AtClient> atClient(
    String atSign,
    String? namespace,
    AtClientPreference preference,
    AtClientManager atClientManager, {
    AtKeysIo? atKeysIo,
    AtLookUp? atLookUp,
    AtLookUpFactory? lookUps,
    String? enrollmentId,
    required AtClientStorage storage,
  }) async {
    return await AtClientImpl.create(
      atSign,
      namespace,
      preference,
      atClientManager: atClientManager,
      atKeysIo: atKeysIo,
      atLookUp: atLookUp,
      lookUps: lookUps,
      enrollmentId: enrollmentId,
      storage: storage,
    );
  }

  @override
  Future<NotificationService> notificationService(
      AtClient atClient, AtClientManager atClientManager,
      {SecondaryAddressFinder? secondaryAddressFinder}) async {
    return await NotificationServiceImpl.create(atClient,
        secondaryAddressFinder: secondaryAddressFinder,
        // NOTE: the concrete client's, and only when the client is one: a
        // test double implementing the interface has no state to report into.
        connection: atClient is AtClientImpl ? atClient.connection : null,
        lookUps: atClient is AtClientImpl ? atClient.lookUps : null);
  }

  @override
  Future<SyncService> syncService(
      AtClient atClient,
      @Deprecated('no longer needed. will be removed in a future release')
      AtClientManager atClientManager,
      NotificationService notificationService) async {
    return await SyncServiceImpl.create(atClient);
  }

  @override
  EnrollmentService enrollmentService(AtClient atClient) {
    AtEnrollment atEnrollment = AtEnrollment.create();
    return EnrollmentServiceImpl(atClient, atEnrollment);
  }
}
