import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    hide AtNotification;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/recorded_logs.dart';

class _MockNotificationService extends Mock implements NotificationService {}

class _MockAtClient extends Mock implements AtClient {}

class _MockLocalSecondary extends Mock implements LocalSecondary {}

class _MockRemoteSecondary extends Mock implements RemoteSecondary {}

class _MockKeyStore extends Mock
    implements AtKeyValueStore<String, AtData, AtMetaData?> {}

/// A sync service whose atServer refuses the client's credentials.
void main() {
  final recorded = RecordedLogs();

  setUpAll(() {
    recorded.installOn(level: 'finer');
    registerFallbackValue(AtKey());
    registerFallbackValue(StatsVerbBuilder());
  });

  late _MockAtClient atClient;
  late _MockLocalSecondary localSecondary;
  late _MockRemoteSecondary remote;
  late SyncServiceImpl sync;
  late AtConnection connection;

  setUp(() async {
    recorded.records.clear();
    atClient = _MockAtClient();
    localSecondary = _MockLocalSecondary();
    remote = _MockRemoteSecondary();
    when(() => atClient.getCurrentAtSign()).thenReturn('@refused');
    when(() => atClient.getLocalSecondary()).thenReturn(localSecondary);
    final notifications = _MockNotificationService();
    when(() => notifications.subscribe(
            regex: any(named: 'regex'),
            shouldDecrypt: any(named: 'shouldDecrypt')))
        .thenAnswer((_) => const Stream<AtNotification>.empty());
    when(() => atClient.notificationService).thenReturn(notifications);
    when(() => atClient.getPreferences()).thenReturn(AtClientPreference());
    connection = AtConnection(
        atSign: '@refused',
        attempt: (_) async =>
            AtConnectionState.offline(AtConnectionCause.unattempted));
    when(() => atClient.connection).thenReturn(connection);
    when(() => atClient.get(any()))
        .thenThrow(AtKeyNotFoundException('nothing persisted yet'));
    when(() => localSecondary.syncQueueSize).thenAnswer((_) async => 0);
    when(() => localSecondary.peekSyncQueue())
        .thenAnswer((_) async => <String>[]);
    sync = await SyncServiceImpl.create(atClient,
        remoteSecondary: remote, warmStartSync: false) as SyncServiceImpl;
  });

  tearDown(() => sync.stop());

  /// Runs one app-requested round and returns what its onError was handed.
  Future<SyncResult?> round() async {
    SyncResult? failed;
    sync.sync(onError: (SyncResult result) => failed = result);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return failed;
  }

  test('a refused round is the last one that asks the atServer', () async {
    // What a revoked enrollment's stats read fails with, as the remote
    // secondary rethrows it.
    when(() => remote.executeVerb(any())).thenThrow(
        UnAuthenticatedException('Exception: Failed connecting to @refused. '
            'error:AT0027:enrollment_id: e1 is revoked'));

    expect(await round(), isNotNull);
    final second = await round();

    verify(() => remote.executeVerb(any())).called(1);
    expect(second?.atClientException, isNotNull,
        reason: 'a later request is still answered, as a failure');
    expect(connection.current.isRefused, isTrue,
        reason: 'the refusal reaches the client\'s connection state, where '
            'an app reads it');
    expect(connection.current.cause, AtConnectionCause.revoked);
    expect(recorded.at('WARNING'),
        contains(contains('refused this client\'s credentials')));
  });

  test('an explicit restart asks the atServer again', () async {
    when(() => remote.executeVerb(any())).thenThrow(
        UnAuthenticatedException('Exception: Failed connecting to @refused. '
            'error:AT0027:enrollment_id: e1 is revoked'));
    await round();

    await sync.stop();
    await sync.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    verify(() => remote.executeVerb(any())).called(2);
  });

  test('an authentication failure naming no refusal is tried again', () async {
    when(() => remote.executeVerb(any())).thenThrow(UnAuthenticatedException(
        'Failed connecting to @refused. The authenticator reported failure'));

    await round();
    await round();

    verify(() => remote.executeVerb(any())).called(2);
  });

  test('a refusal that arrives on a push batch ends the rounds too', () async {
    when(() => remote.executeVerb(any()))
        .thenAnswer((_) async => 'data:[{"value":"-1"}]');
    when(() => localSecondary.syncQueueSize).thenAnswer((_) async => 1);
    when(() => localSecondary.peekSyncQueue(limit: any(named: 'limit')))
        .thenAnswer((_) async => ['k1.wavi@refused']);
    when(() => localSecondary.readSyncQueueEntry(any())).thenAnswer((_) async =>
        SyncQueueEntry(
            atKey: 'k1.wavi@refused', op: SyncQueueOp.delete, ts: 1, seq: 1));
    when(() => localSecondary.keyStore).thenReturn(_MockKeyStore());
    when(() => remote.executeCommand(any(), auth: any(named: 'auth')))
        .thenThrow(UnAuthenticatedException('Failed connecting to @refused. '
            'error:AT0027:enrollment_id: e1 is revoked'));

    await round();
    await round();

    verify(() => remote.executeCommand(any(), auth: any(named: 'auth')))
        .called(1);
    expect(connection.current.isRefused, isTrue);
  });

  test('control: a failure that is not a refusal is tried again', () async {
    when(() => remote.executeVerb(any()))
        .thenThrow(AtConnectException('Connection refused'));

    await round();
    await round();

    verify(() => remote.executeVerb(any())).called(2);
  });
}
