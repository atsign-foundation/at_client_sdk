import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/hive_store.dart';
import 'test_utils/no_keys.dart';
import 'test_utils/transport.dart';

/// `buildAtClient` wires the monitor's connection through `notificationLookUps`
/// when given, so a browser can hand the monitor a tab-shared factory while
/// the client's own requests keep their per-tab one.
void main() {
  const atSign = '@notification_lookups';
  final preference = AtClientPreference()
    ..hiveStoragePath = 'test/hive/notification_lookups';

  late _CountingLookUps clientLookUps;
  late _CountingLookUps notificationLookUps;
  AtClient? client;

  setUp(() {
    clientLookUps = _CountingLookUps('client');
    notificationLookUps = _CountingLookUps('notification');
  });

  tearDown(() async {
    await (client as AtClientImpl?)?.stop();
    client = null;
  });

  Future<AtClient> build({AtLookUpFactory? notificationLookUps}) =>
      buildAtClient(
        atSign: atSign,
        namespace: 'test',
        preference: preference,
        lookUps: clientLookUps.call,
        notificationLookUps: notificationLookUps,
        secondaryAddressFinder: defaultAtDirectory,
        atKeysIo: noKeysFor(atSign),
        storage: hiveStoreFor(atSign, preference),
      );

  AtLookupMuxable monitorLookUpOf(AtClient client) =>
      (client.notificationService as NotificationServiceImpl).monitor.lookUp;

  test(
      'with notificationLookUps, the monitor\'s muxable is the one it built '
      'and the client\'s own factory built none of it', () async {
    client = await build(notificationLookUps: notificationLookUps.call);

    final monitorLookUp = monitorLookUpOf(client!);
    expect(notificationLookUps.built, [same(monitorLookUp)],
        reason: 'the notification factory builds exactly the monitor\'s '
            'connection, nothing else');
    expect(clientLookUps.built, isNot(contains(same(monitorLookUp))),
        reason: 'the client\'s factory keeps building its own connections '
            'and no longer the monitor\'s');
  });

  test(
      'without notificationLookUps, the monitor\'s muxable comes from the '
      'client\'s own factory, as before', () async {
    client = await build();

    expect(clientLookUps.built, contains(same(monitorLookUpOf(client!))));
    expect(notificationLookUps.built, isEmpty);
  });
}

/// An [AtLookUpFactory] that remembers every muxable it built.
class _CountingLookUps {
  _CountingLookUps(this.name);

  final String name;
  final built = <AtLookupMuxable>[];

  AtLookupMuxable call({
    required String atSign,
    required AtRootDomain rootDomain,
    required AtAuthenticator? authenticator,
    SecondaryAddressFinder? secondaryAddressFinder,
  }) {
    final muxable = _InertMuxable(name);
    built.add(muxable);
    return muxable;
  }
}

/// A muxable that never connects: enough surface for `buildAtClient` to wire
/// it and for `stop()` to tear it down.
class _InertMuxable extends Fake implements AtLookupMuxable {
  _InertMuxable(this.builtBy);

  final String builtBy;
  final _notifications = StreamController<String>.broadcast();
  final _up = StreamController<bool>.broadcast();

  @override
  Stream<String> get notifications => _notifications.stream;

  @override
  Stream<bool> get notificationConnectionUp => _up.stream;

  @override
  bool get isNotifying => false;

  /// The client installs its credentials on the connection it builds.
  @override
  AtAuthenticator? authenticator;

  @override
  Duration heartbeatInterval = Duration.zero;

  @override
  Duration heartbeatResponseTimeout = Duration.zero;

  @override
  Future<void> startNotifications({
    String? regex,
    Future<int?> Function()? getLastNotificationTime,
    bool selfNotificationsEnabled = true,
  }) async {}

  @override
  Future<void> stopNotifications() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> close() async {}

  @override
  String toString() => '_InertMuxable(builtBy: $builtBy)';
}
