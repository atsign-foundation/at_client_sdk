import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/transport.dart';

const _atSign = '@alice';

/// The connection a tab would open for its monitor: counts what the shared
/// monitor does to it and lets the test play the atServer.
class _ServerFedMuxable extends Fake implements AtLookupMuxable {
  int startCalls = 0;
  int stopCalls = 0;
  int? startedWithWatermark;

  StreamController<String> _notifications = StreamController<String>();
  StreamController<bool> _up = StreamController<bool>.broadcast();

  @override
  Stream<String> get notifications => _notifications.stream;

  @override
  Stream<bool> get notificationConnectionUp => _up.stream;

  @override
  bool get isReconnectingNotifications => false;

  @override
  Duration heartbeatInterval = const Duration(seconds: 59);

  @override
  Duration heartbeatResponseTimeout = const Duration(seconds: 10);

  @override
  Future<void> startNotifications({
    String? regex,
    Future<int?> Function()? getLastNotificationTime,
    bool selfNotificationsEnabled = true,
  }) async {
    startCalls++;
    startedWithWatermark = await getLastNotificationTime?.call();
    _up.add(true);
  }

  @override
  Future<void> stopNotifications() async {
    stopCalls++;
    final n = _notifications;
    final u = _up;
    _notifications = StreamController<String>();
    _up = StreamController<bool>.broadcast();
    unawaited(n.close());
    unawaited(u.close());
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> close() async {}

  /// The atServer sends [id] at [epochMillis].
  void deliver(String id, int epochMillis) =>
      _notifications.add('notification: '
          '{"id":"$id","from":"$_atSign","to":"$_atSign",'
          '"key":"$id.wavi$_atSign","value":null,"operation":"update",'
          '"epochMillis":$epochMillis,'
          '"messageType":"MessageType.key","isEncrypted":false}');
}

/// A browser tab: its own notification service over its own connection,
/// sharing the monitor with the other tabs through the in-memory ports.
class _Tab {
  _Tab(this.name,
      {required InMemoryMonitorLock lock, required InMemoryChannelHub hub}) {
    muxable = TabMuxable(
      inner,
      lock: lock,
      channels: hub.open,
      lifecycle: InMemoryPageLifecycle(),
      name: name,
    );
  }

  final String name;
  final inner = _ServerFedMuxable();
  late final TabMuxable muxable;
  late final NotificationServiceImpl service;

  /// The ids the tab's subscriber was given, in order.
  final delivered = <String>[];

  Future<void> open() async {
    final atClient = MockAtClientImpl();
    when(() => atClient.getCurrentAtSign()).thenReturn(_atSign);
    when(() => atClient.atSign).thenReturn(_atSign.toAtsign());
    when(() => atClient.getPreferences()).thenReturn(AtClientPreference()
      ..namespace = 'wavi'
      ..fetchOfflineNotifications = false);
    when(() => atClient.atKeysIo).thenReturn(null);
    when(() => atClient.enrollmentId).thenReturn(null);
    when(() => atClient.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((_) async => true);
    service = await NotificationServiceImpl.create(atClient,
        secondaryAddressFinder: defaultAtDirectory,
        lookUps: ({
          required String atSign,
          required AtRootDomain rootDomain,
          required AtAuthenticator? authenticator,
          SecondaryAddressFinder? secondaryAddressFinder,
        }) =>
            muxable) as NotificationServiceImpl;
    service.subscribe(regex: '.*').listen((n) => delivered.add(n.id));
  }

  void close() => service.stopAllSubscriptions();
}

/// Pumps the event queue until [done] holds, or fails.
Future<void> until(bool Function() done, String what) async {
  for (var i = 0; i < 50 && !done(); i++) {
    await pumpEventQueue();
  }
  expect(done(), isTrue, reason: 'waited for $what');
}

/// Two tabs of one atSign share a monitor. When the leading tab closes, the
/// other takes over the connection and resumes from its own watermark; the
/// notification the atServer then replays reaches its subscriber once.
///
/// Catalogue: features/at_client/notification_handoff.feature
void main() {
  setUpAll(() => registerFallbackValue(FakeAtKey()));

  test(
      'a notification relayed before the handoff and replayed after it is '
      'delivered once; the one after it is delivered', () async {
    final lock = InMemoryMonitorLock();
    final hub = InMemoryChannelHub();
    const name = 'at-monitor:@alice:primary';
    final first = _Tab(name, lock: lock, hub: hub);
    final second = _Tab(name, lock: lock, hub: hub);
    await first.open();
    await until(() => first.inner.startCalls == 1, 'the first tab to lead');
    await second.open();
    await until(() => second.muxable.role == TabRole.follower,
        'the second tab to follow');
    addTearDown(second.close);

    final t1 = DateTime.now().millisecondsSinceEpoch;
    first.inner.deliver('n1', t1);
    await until(() => second.delivered.isNotEmpty, 'the relay');
    expect(first.delivered, ['n1']);
    expect(second.delivered, ['n1']);
    expect(second.inner.startCalls, 0, reason: 'one connection for two tabs');

    first.close();
    await until(() => second.inner.startCalls == 1, 'the handoff');
    expect(first.inner.stopCalls, 1);
    expect(second.muxable.role, TabRole.leader);
    expect(second.inner.startedWithWatermark, t1,
        reason: 'the new leader resumes from what its own service delivered');

    // An inclusive since filter: the atServer sends the watermark's
    // notification again, then what came after it.
    second.inner.deliver('n1', t1);
    second.inner.deliver('n2', t1 + 1000);
    await until(() => second.delivered.length >= 2, 'delivery after handoff');
    await pumpEventQueue();
    expect(second.delivered, ['n1', 'n2']);
  });
}
