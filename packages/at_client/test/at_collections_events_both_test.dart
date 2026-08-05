// Coverage for AtCollection's `EventSource.both` path — both source
// streams active simultaneously, no de-duplication. The notifs path
// is exercised in at_collections_test.dart (and the related
// at_collections_sub_test.dart / at_collections_query_test.dart /
// at_collections_query_sub_test.dart files); the data path is
// exercised in at_collections_data_events_test.dart. This file's
// scope is narrow: prove that with `EventSource.both`, a single
// logical change driven through each source emits TWICE on the
// collection's event streams (once per source).

import 'dart:async';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAtClient extends Mock implements AtClient {
  @override
  SigningAlgoType get signingAlgoType => SigningAlgoType.rsa2048;
}

class _FakeAtKey extends Fake implements AtKey {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeAtKey());
  });

  late _MockAtClient atClient;
  late StreamController<AtNotification> notifStream;
  late StreamController<DataEvent> dataEvents;

  const selfAtSignStr = '@alice';
  final selfAtSign = selfAtSignStr.toAtsign();
  const bobStr = '@bob';
  final bob = bobStr.toAtsign();
  const namespace = 'tasks.app_1.my_apps';

  setUp(() {
    atClient = _MockAtClient();
    notifStream = StreamController<AtNotification>.broadcast();
    dataEvents = StreamController<DataEvent>.broadcast();
    when(() => atClient.atSign).thenReturn(selfAtSign);
  });

  tearDown(() async {
    await notifStream.close();
    await dataEvents.close();
  });

  AtCollection<T> buildCollection<T>({
    String ns = namespace,
    Duration ttl = const Duration(days: 7),
  }) =>
      collectionWithInjectedBoth<T>(
        atClient,
        ns,
        ttl,
        notifications: notifStream.stream,
        dataEvents: dataEvents.stream,
      );

  AtKey objKey({required String id, required String owner, String? to}) =>
      AtKey.fromString(
        to != null ? '$to:$id.$namespace$owner' : '$id.$namespace$owner',
      );

  AtNotification objNotif({
    required String key,
    required String from,
    required String to,
    required String operation,
  }) {
    return AtNotification(
      'nid-1',
      key,
      from,
      to,
      DateTime.now().millisecondsSinceEpoch,
      'key',
      false,
      operation: operation,
    );
  }

  test(
      'a single logical update driven through each source emits twice on '
      'the updates stream (notifs path + data path, no de-duplication)',
      () async {
    final c = buildCollection<String>();
    final received = <CItemUpdated>[];
    final sub = c.updates.listen(received.add);

    // Same logical update — same id, same owner — once via the
    // notification path (peer-driven write delivered to this atSign)
    // and once via the data path (sync applies that write to the
    // local keystore).
    notifStream.add(objNotif(
      key: 'id9.$namespace$selfAtSignStr',
      from: selfAtSignStr,
      to: selfAtSignStr,
      operation: 'update',
    ));
    dataEvents.add(DataUpdated(
      objKey(id: 'id9', owner: selfAtSignStr),
    ));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(2));
    expect(received.every((e) => e.id == 'id9'), isTrue);
    expect(received.every((e) => e.owner == selfAtSign), isTrue);
    await sub.cancel();
  });

  test(
      'a single logical delete driven through each source emits twice on '
      'the deletes stream', () async {
    final c = buildCollection<String>();
    final received = <CItemDeleted>[];
    final sub = c.deletes.listen(received.add);

    notifStream.add(objNotif(
      key: 'id9.$namespace$selfAtSignStr',
      from: bobStr,
      to: selfAtSignStr,
      operation: 'delete',
    ));
    dataEvents.add(DataDeleted(
      objKey(id: 'id9', owner: bobStr, to: selfAtSignStr),
    ));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(2));
    expect(received.every((e) => e.id == 'id9'), isTrue);
    expect(received.every((e) => e.owner == bob), isTrue);
    await sub.cancel();
  });

  test('notifs-only event still flows through (data stream silent)', () async {
    final c = buildCollection<String>();
    final received = <CItemUpdated>[];
    final sub = c.updates.listen(received.add);

    notifStream.add(objNotif(
      key: 'idn.$namespace$selfAtSignStr',
      from: selfAtSignStr,
      to: selfAtSignStr,
      operation: 'update',
    ));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.single.id, 'idn');
    await sub.cancel();
  });

  test('data-only event still flows through (notifs stream silent)', () async {
    final c = buildCollection<String>();
    final received = <CItemUpdated>[];
    final sub = c.updates.listen(received.add);

    dataEvents.add(DataUpdated(
      objKey(id: 'idd', owner: selfAtSignStr),
    ));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.single.id, 'idd');
    await sub.cancel();
  });
}
