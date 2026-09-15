import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/at_notification.dart' as at_notification;
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';

/// An AtClient double whose atSign and preferences are concrete overrides, so
/// they answer the same way in every test and cannot be stubbed with `when`.
class MockAtClient extends Mock implements AtClient {
  @override
  String? getCurrentAtSign() => '@alice';

  @override
  AtClientPreference getPreferences() => AtClientPreference();
}

/// A NotificationServiceImpl double whose `subscribe` is a concrete override
/// returning a stream that never emits, so no test can stub it into emitting.
class MockNotificationServiceImpl extends Mock
    implements NotificationServiceImpl {
  @override
  Stream<at_notification.AtNotification> subscribe(
      {String? regex, bool shouldDecrypt = false}) {
    return StreamController<at_notification.AtNotification>().stream;
  }
}

/// Pins that `stop()` actually stops: a sync run parked on its opening network
/// read (the stats fetch inside `_isInSync`) when `stop()` is called does no
/// further sync work when it resumes, and its request is answered as stopped
/// rather than left dangling.
void main() {
  late MockAtClient atClient;
  late MockRemoteSecondary remote;
  late MockLocalSecondary local;
  late SyncServiceImpl service;

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(StatsVerbBuilder());
    registerFallbackValue(PutRequestOptions());
  });

  setUp(() async {
    atClient = MockAtClient();
    remote = MockRemoteSecondary();
    local = MockLocalSecondary();
    final notificationService = MockNotificationServiceImpl();

    when(() => atClient.notificationService).thenReturn(notificationService);
    when(() => atClient.getLocalSecondary()).thenReturn(local);
    when(() => atClient.get(any()))
        .thenAnswer((_) async => AtValue()..value = '7');
    when(() => local.syncQueueSize).thenAnswer((_) async => 5);
    when(() => local.peekSyncQueue(limit: any(named: 'limit')))
        .thenAnswer((_) async => <String>[]);

    service = await SyncServiceImpl.create(atClient,
        atClientManager: MockAtClientManager(),
        remoteSecondary: remote,
        warmStartSync: false) as SyncServiceImpl;
  });

  tearDown(() async {
    if (!service.isStopped) {
      await service.stop();
    }
  });

  test('a run parked on the network when stop() lands does no work on resume',
      () async {
    final park = Completer<String>();
    when(() => remote.executeVerb(any())).thenAnswer((_) => park.future);

    SyncResult? errorResult;
    service.sync(onError: (result) => errorResult = result as SyncResult?);
    await Future.delayed(Duration.zero);
    verify(() => remote.executeVerb(any())).called(1);

    final stopFuture = service.stop();
    park.complete('data:[{"value":"7"}]');
    await stopFuture;
    await Future.delayed(Duration(milliseconds: 20));
    verifyNever(() => local.peekSyncQueue(limit: any(named: 'limit')));
    verifyNever(() => atClient.get(any()));
    expect(errorResult, isNotNull,
        reason: 'the stranded request must be answered, not left dangling');
    expect(
        errorResult!.atClientException?.message, contains('has been stopped'),
        reason: 'the request is answered as stopped, not as any other error');
  });

  test(
      'a run parked on its pull fetch when stop() lands does not write the '
      'pull cursor on resume', () async {
    final park = Completer<String>();
    when(() => remote.executeVerb(any())).thenAnswer((invocation) {
      if (invocation.positionalArguments.first is StatsVerbBuilder) {
        return Future.value('data:[{"value":"9"}]');
      }
      return park.future;
    });

    SyncResult? errorResult;
    service.sync(onError: (result) => errorResult = result as SyncResult?);
    await Future.delayed(Duration(milliseconds: 20));
    verify(() => remote.executeVerb(any())).called(2);

    final stopFuture = service.stop();
    park.complete('data:[]');
    await stopFuture;
    await Future.delayed(Duration(milliseconds: 20));
    verifyNever(() => atClient.put(any(), any(),
        putRequestOptions: any(named: 'putRequestOptions')));
    expect(
        errorResult?.atClientException?.message, contains('has been stopped'),
        reason: 'the stranded request is answered as stopped');
  });

  test('control: without stop(), the same parked run resumes and does work',
      () async {
    final park = Completer<String>();
    when(() => remote.executeVerb(any())).thenAnswer((_) => park.future);

    service.sync();
    await Future.delayed(Duration.zero);
    park.complete('data:[{"value":"7"}]');
    await Future.delayed(Duration(milliseconds: 50));

    // NOTE: without this control arm the first test's verifyNever could pass
    // because the path was never reachable at all.
    verify(() => local.peekSyncQueue(limit: any(named: 'limit')))
        .called(greaterThanOrEqualTo(1));
  });

  test('stop() returns without waiting for the in-flight run', () async {
    final park = Completer<String>();
    when(() => remote.executeVerb(any())).thenAnswer((_) => park.future);

    service.sync();
    await Future.delayed(Duration.zero);

    var stopped = false;
    final stopFuture = service.stop().then((_) => stopped = true);
    await Future.delayed(Duration(milliseconds: 20));
    expect(stopped, true,
        reason: 'stop() does not drain or wait; the parked run is abandoned '
            'and ends at its next step once the network answers');
    park.complete('data:[{"value":"7"}]');
    await stopFuture;
    await Future.delayed(Duration(milliseconds: 20));
  });
}
