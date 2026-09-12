import 'dart:async';

import 'package:at_auth/at_auth.dart' show AtEnrollment, AtKeys, AtKeysIo;
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
/// The caller owns the client's lifetime and ends it with [stop].
///
/// ⚠️ The client is filed in `AtClientImpl.atClientInstanceMap` like any
/// other, so a later [AtClientManager.setCurrentAtSign] for the same atSign
/// adopts THIS client, replaces its notification, sync and enrollment
/// services without stopping the ones it had, and stops it on the next atSign
/// switch. Do not mix this factory and the manager for one atSign in one
/// process.
///
/// [storage] is borrowed by default, so [stop] detaches from it without
/// closing it and the caller closes it when done; a bundle built with
/// `closedByClient: true` is closed by the client instead. Supplying none
/// falls back to a Hive store under the deprecated
/// `preference.hiveStoragePath`.
///
/// With [atKeysIo] the enrollment is the keys' own answer,
/// `AtKeys.enrollmentToAuthenticateAs`; an [enrollmentId] that disagrees is
/// logged at shout level and ignored.
///
/// Throws a [StateError] when a client for [atSign] as the same principal
/// (the enrollment the keys name, or the atSign's own credential) is already
/// live, rather than handing back one this caller does not own; [stop]
/// releases it. Another enrollment of the atSign is another principal and
/// builds beside it, on a store of its own. A failure while building leaves
/// nothing behind — the part-built client is stopped, which unfiles it and
/// releases its claim on [storage].
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
  final principal = await _principalOf(atSign, atKeysIo, enrollmentId);
  if (AtClientImpl.holdsLiveClientAs(atSign, principal)) {
    throw StateError(
        'A client for $atSign as ${principal == null ? "its own credential" : "enrollment $principal"} '
        'is already live. buildAtClient builds a client the caller owns, so '
        'it will not hand back one owned elsewhere; stop() the existing '
        'client first.');
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
    exactEnrollment: true,
  );
  try {
    client.notificationService = notificationServiceBuilder == null
        ? await NotificationServiceImpl.create(client,
            secondaryAddressFinder: secondaryAddressFinder ??
                (client is AtClientImpl ? client.secondaryAddressFinder : null),
            connection: client.connection)
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

/// The enrollment the client will run as: the keys' own answer when they
/// hold authentication material, otherwise [enrollmentId]. The same rule
/// `AtClientImpl.create` applies, asked here so the refusal above names the
/// principal that would be built.
Future<String?> _principalOf(
    String atSign, AtKeysIo? atKeysIo, String? enrollmentId) async {
  if (atKeysIo == null) return enrollmentId;
  final AtKeys keys;
  try {
    keys = await atKeysIo.read(atSign);
  } on Exception {
    return enrollmentId;
  }
  if (!keys.holdsAuthenticationMaterial) return enrollmentId;
  return keys.enrollmentToAuthenticateAs();
}
