import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:test/test.dart';

import 'test_utils/fake_at_server.dart';
import 'test_utils/no_keys.dart';
import 'test_utils/transport.dart';

/// Catalogue: features/at_client/stopped_client.feature
void main() {
  Future<AtClient> openClient(String atSign) => buildAtClient(
      atSign: atSign,
      namespace: 'wavi',
      preference: AtClientPreference()
        ..namespace = 'wavi'
        ..monitorAutoStart = false,
      secondaryAddressFinder: defaultAtDirectory,
      atKeysIo: noKeysFor(atSign),
      lookUps: FakeAtServer(atSign: atSign).lookUps,
      storage: InMemoryAtClientStorage(atSign: atSign, closedByClient: true));

  final stopped = throwsA(isA<StoppedException>());

  test('collection() on a stopped client throws StoppedException', () async {
    final client = await openClient('@collection');
    await client.collection<String>('notes.wavi', const Duration(days: 1));

    await client.stop();

    await expectLater(
        client.collection<String>('notes.wavi', const Duration(days: 1)),
        stopped,
        reason: 'a collection obtained before the stop is not handed back');
    await expectLater(
        client.collection<String>('other.wavi', const Duration(days: 1)),
        stopped);
  });

  test("A stopped client's services throw StoppedException", () async {
    final client = await openClient('@services');
    expect(client.syncService, isNotNull, reason: 'the premise');
    expect(client.notificationService, isNotNull, reason: 'the premise');
    expect(client.enrollmentService, isNotNull, reason: 'the premise');

    await client.stop();

    expect(() => client.syncService, stopped);
    expect(() => client.notificationService, stopped);
    expect(() => client.enrollmentService, stopped);
    await expectLater(
        () => client.notificationService
            .send(to: '@bob'.toAtsign(), idAndNamespace: 'hi.wavi', body: 'x'),
        stopped);
    expect(() => client.notificationService.subscribe(regex: 'wavi'), stopped);
    expect(() => client.syncService.sync(), stopped);
    await expectLater(() => client.syncService.isInSync(), stopped);
    await expectLater(
        client.notifyChange(NotificationParams.forUpdate(
            (AtKey.shared('n', namespace: 'wavi', sharedBy: '@services')
                  ..sharedWith('@bob'))
                .build(),
            value: 'v')),
        stopped);
    await expectLater(() => client.enrollments.pending(), stopped);
  });

  test('startCompactionJob on a stopped client throws StoppedException',
      () async {
    final client = await openClient('@compaction');
    await client.stop();

    // ignore: deprecated_member_use_from_same_package
    await expectLater(client.startCompactionJob(), stopped);
  });
}
