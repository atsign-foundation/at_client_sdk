import 'dart:async';

import 'package:at_auth/at_auth.dart' show AtEnrollment, AtKeysIo;
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/service/enrollment_service.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_client/src/storage/at_client_storage.dart';
import 'package:at_lookup/at_lookup.dart';

/// Builds a client for [atSign] and wires its notification, sync and
/// enrollment services.
///
/// The caller owns the client's lifetime and ends it with [stop]. Code that
/// wants the shared current-atSign client goes on calling
/// [AtClientManager.setCurrentAtSign], whose behaviour is unchanged.
///
/// ⚠️ The client is NOT invisible to [AtClientManager]. It is filed in
/// `AtClientImpl.atClientInstanceMap` like any other, so a later
/// [AtClientManager.setCurrentAtSign] for the same atSign adopts THIS client
/// rather than building its own — and adopting it replaces its notification,
/// sync and enrollment services without stopping the ones it had, then stops
/// it on the next atSign switch. Until that is separated, do not mix this
/// factory and the manager for one atSign in one process.
///
/// [storage] is borrowed by default, so [stop] detaches from it without
/// closing it and the caller closes it when done; a bundle built with
/// `closedByClient: true` is closed by the client instead, which is what an
/// app with no teardown of its own wants. Supplying none falls back to a Hive
/// store under the deprecated `preference.hiveStoragePath`.
///
/// Each builder replaces one service with the caller's own; by default each
/// service is the real one.
///
/// Throws a [StateError] when a client for [atSign] is already live, rather
/// than handing back one this caller does not own. [stop] releases it.
///
/// A failure while building leaves nothing behind: the part-built client is
/// stopped, which unfiles it and releases its claim on [storage].
Future<AtClient> buildAtClient({
  required String atSign,
  required AtClientPreference preference,
  String? namespace,
  AtClientStorage? storage,
  AtKeysIo? atKeysIo,
  String? enrollmentId,
  AtLookUp? atLookUp,
  SecondaryAddressFinder? secondaryAddressFinder,
  FutureOr<NotificationService> Function(AtClient)? notificationServiceBuilder,
  FutureOr<SyncService> Function(AtClient)? syncServiceBuilder,
  FutureOr<EnrollmentService> Function(AtClient)? enrollmentServiceBuilder,
}) async {
  if (AtClientImpl.holdsLiveClient(atSign)) {
    throw StateError(
        'A client for $atSign is already live. AtClient.create builds a '
        'client the caller owns, so it will not hand back one owned '
        'elsewhere; stop() the existing client first.');
  }
  if (storage != null && !preference.isLocalStoreRequired) {
    throw ArgumentError.value(
        storage,
        'storage',
        'preference.isLocalStoreRequired is false for $atSign, so this '
            'storage would never be opened');
  }
  final client = await AtClientImpl.create(
    atSign,
    namespace,
    preference,
    atKeysIo: atKeysIo,
    atLookUp: atLookUp,
    enrollmentId: enrollmentId,
    storage: storage,
  );
  // The client is already filed in `AtClientImpl.atClientInstanceMap` by the
  // time the services are wired, so a throw here would leave an entry no
  // caller holds a reference to, still claiming its storage. `stop()`
  // unfiles it and releases that claim.
  try {
    client.notificationService = notificationServiceBuilder == null
        ? await NotificationServiceImpl.create(client,
            secondaryAddressFinder: secondaryAddressFinder)
        : await notificationServiceBuilder(client);
    client.syncService = syncServiceBuilder == null
        ? await SyncServiceImpl.create(client)
        : await syncServiceBuilder(client);
    client.enrollmentService = enrollmentServiceBuilder == null
        ? EnrollmentServiceImpl(client, AtEnrollment.create())
        : await enrollmentServiceBuilder(client);
  } catch (_) {
    await client.stop();
    rethrow;
  }
  return client;
}
