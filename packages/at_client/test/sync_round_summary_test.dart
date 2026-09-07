import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/at_notification.dart' as at_notification;
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/recorded_logs.dart';

class MockAtClient extends Mock implements AtClient {
  @override
  String? getCurrentAtSign() => '@alice';

  @override
  AtClientPreference getPreferences() => AtClientPreference();
}

class MockNotificationServiceImpl extends Mock
    implements NotificationServiceImpl {
  @override
  Stream<at_notification.AtNotification> subscribe(
      {String? regex, bool shouldDecrypt = false}) {
    return StreamController<at_notification.AtNotification>().stream;
  }
}

/// What a log at `info` says about sync: one line per round that moved data,
/// and nothing per entry, so the log does not grow with the number of keys.
void main() {
  final logs = RecordedLogs();
  late MockAtClient atClient;
  late MockRemoteSecondary remote;
  late MockLocalSecondary local;
  late SyncServiceImpl service;

  setUpAll(() {
    logs.installOn(level: 'finer');
    registerFallbackValue(AtKey());
    registerFallbackValue(StatsVerbBuilder());
    registerFallbackValue(UpdateVerbBuilder());
    registerFallbackValue(PutRequestOptions());
  });

  setUp(() => logs.records.clear());

  tearDown(() async {
    if (!service.isStopped) {
      await service.stop();
    }
  });

  /// An atServer at commit [server], a local store that has pulled up to
  /// [pulled] and has nothing to push, and one entry to pull between them.
  Future<void> build({required int server, required int pulled}) async {
    atClient = MockAtClient();
    remote = MockRemoteSecondary();
    local = MockLocalSecondary();
    when(() => atClient.notificationService)
        .thenReturn(MockNotificationServiceImpl());
    when(() => atClient.getLocalSecondary()).thenReturn(local);
    when(() => atClient.get(any()))
        .thenAnswer((_) async => AtValue()..value = '$pulled');
    when(() => atClient.put(any(), any(),
        putRequestOptions: any(named: 'putRequestOptions'))).thenAnswer(
      (_) async => true,
    );
    when(() => local.syncQueueSize).thenAnswer((_) async => 0);
    when(() => local.peekSyncQueue()).thenAnswer((_) async => <String>[]);
    when(() => local.peekSyncQueue(limit: any(named: 'limit')))
        .thenAnswer((_) async => <String>[]);
    when(() => local.isWriteInProgress(any())).thenReturn(false);
    when(() => local.executeVerb(any(),
            cameFromServer: any(named: 'cameFromServer')))
        .thenAnswer((_) async => 'data:$server');
    when(() => remote.executeVerb(any())).thenAnswer((invocation) async {
      if (invocation.positionalArguments.first is StatsVerbBuilder) {
        return 'data:[{"id":"3","name":"lastCommitID","value":"$server"}]';
      }
      return 'data:[{"atKey":"phone.wavi@alice","value":"123",'
          '"operation":"+","commitId":$server,"metadata":{}}]';
    });
    service = await SyncServiceImpl.create(atClient,
        remoteSecondary: remote, warmStartSync: false) as SyncServiceImpl;
  }

  Iterable<String> summaries() =>
      logs.at('INFO').where((m) => m.startsWith('sync round '));

  test(
      'a round that pulled an entry logs one info line saying so, and the '
      'entry itself only at finer', () async {
    await build(server: 5, pulled: 2);

    service.sync();
    for (var i = 0; i < 100 && summaries().isEmpty; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
    }

    expect(logs.at('FINER'),
        contains('Pulling to local: UPDATE: phone.wavi@alice'),
        reason: 'the round did not pull the entry, so the assertions below '
            'would be about a round that moved nothing');
    expect(summaries(), hasLength(1),
        reason: 'a round that moved data must say so exactly once at info');
    expect(
        summaries().single,
        allOf(
            contains('(app)'),
            contains('pulled 1 update(s) and 0 delete(s)'),
            contains('0 conflict(s) skipped'),
            contains('pushed 0'),
            endsWith('server commit id 5')),
        reason: 'the summary is what an operator reads instead of the '
            'per-entry lines, so it must carry the counts and the cursor');
    expect(
        logs.at('INFO').where((m) => m.contains('Pulling to local')), isEmpty,
        reason: 'a per-entry line at info makes the log grow with every key '
            'synced, which the summary line exists to prevent');
  });

  test('a round that found server and local in sync logs no summary', () async {
    await build(server: 2, pulled: 2);

    service.sync();
    await Future.delayed(const Duration(milliseconds: 200));

    expect(
        logs.at('FINER'), contains(startsWith('server and local are in sync')),
        reason: 'the round did not run to its in-sync exit, so the absence '
            'below would be about a round that never happened');
    expect(summaries(), isEmpty,
        reason: 'a round that moved nothing has nothing to summarise; an '
            'idle client must not log a line per stats notification');
  });
}
