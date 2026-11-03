import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockNotificationService extends Mock implements NotificationService {}

class _MockAtClient extends Mock implements AtClient {}

class _MockLocalSecondary extends Mock implements LocalSecondary {}

class _MockRemoteSecondary extends Mock implements RemoteSecondary {}

/// Catalogue: features/at_client/sync_rounds.feature
void main() {
  late _MockRemoteSecondary remote;
  late SyncServiceImpl sync;

  /// How many times a round has read the atServer's commit id.
  late int reads;

  /// Holds the first read until it completes, while set.
  late Completer<void> firstRead;

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(StatsVerbBuilder());
    registerFallbackValue(PutRequestOptions());
  });

  setUp(() async {
    reads = 0;
    firstRead = Completer<void>();
    final atClient = _MockAtClient();
    final localSecondary = _MockLocalSecondary();
    remote = _MockRemoteSecondary();
    when(() => atClient.getCurrentAtSign()).thenReturn('@rounds');
    when(() => atClient.getLocalSecondary()).thenReturn(localSecondary);
    final notifications = _MockNotificationService();
    when(() => notifications.subscribe(
            regex: any(named: 'regex'),
            shouldDecrypt: any(named: 'shouldDecrypt')))
        .thenAnswer((_) => const Stream<AtNotification>.empty());
    when(() => atClient.notificationService).thenReturn(notifications);
    when(() => atClient.getPreferences()).thenReturn(AtClientPreference());
    when(() => atClient.get(any()))
        .thenAnswer((_) async => AtValue()..value = '5');
    when(() => localSecondary.syncQueueSize).thenAnswer((_) async => 0);
    when(() => localSecondary.peekSyncQueue())
        .thenAnswer((_) async => <String>[]);
    when(() => remote.executeVerb(any())).thenAnswer((invocation) async {
      final builder = invocation.positionalArguments.first;
      if (builder is StatsVerbBuilder) {
        reads++;
        if (reads == 1) await firstRead.future;
        return 'data:[{"id":"3","name":"lastCommitID","value":"5"}]';
      }
      throw StateError(
          'no answer for ${(builder as VerbBuilder).buildCommand()}');
    });
    sync = await SyncServiceImpl.create(atClient,
        remoteSecondary: remote, warmStartSync: false) as SyncServiceImpl;
  });

  tearDown(() => sync.stop());

  /// Lets the event loop run until [done] holds, for at most two seconds.
  Future<void> until(bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('the condition did not hold within two seconds');
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  /// Lets every round that is due run to its end.
  Future<void> settled() async {
    await until(() => !sync.isSyncInProgress && sync.syncRequests.isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  test('A sync an app asks for while a round runs gets a round of its own',
      () async {
    sync.sync();
    await until(() => reads == 1);

    sync.sync();
    firstRead.complete();
    await settled();

    expect(reads, 2,
        reason: 'the round that read the atServer before the app asked does '
            'not answer it; another round reads afresh');
  });

  test(
      'Given a round waiting on its read of the atServer, when the app asks '
      'for a sync three times, then one more round runs after it, and no '
      'other', () async {
    sync.sync();
    await until(() => reads == 1);

    for (var i = 0; i < 3; i++) {
      sync.sync();
    }
    firstRead.complete();
    await settled();

    expect(reads, 2, reason: 'the requests made during one round share one');
  });

  test(
      'Given an app asking for a sync twice before any round runs, when the '
      'round runs, then it answers both', () async {
    firstRead.complete();
    sync
      ..sync()
      ..sync();
    await settled();

    expect(reads, 1, reason: 'both were queued when the round read');
  });
}
