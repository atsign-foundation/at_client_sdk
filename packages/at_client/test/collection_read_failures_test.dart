import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// Catalogue: features/at_client/collection_read_failures.feature
void main() {
  setUpAll(() {
    registerFallbackValue(FakeAtKey());
  });

  late MockAtClient atClient;
  late StreamController<AtNotification> notifStream;

  const selfAtSignStr = '@alice';
  final selfAtSign = selfAtSignStr.toAtsign();
  const namespace = 'tasks.app_1.my_apps';

  setUp(() {
    atClient = MockAtClient();
    notifStream = StreamController<AtNotification>.broadcast();
    when(() => atClient.atSign).thenReturn(selfAtSign);
    when(
      () => atClient.getAtKeys(regex: any(named: 'regex')),
    ).thenAnswer((_) async => [
          AtKey.fromString('id1.$namespace$selfAtSignStr'),
        ]);
  });

  tearDown(() async {
    await notifStream.close();
  });

  AtCollection<String> buildCollection() => collectionWithInjectedNotifications(
        atClient,
        namespace,
        const Duration(days: 7),
        notifications: notifStream.stream,
      );

  /// Every error the read path yields, with the data discarded.
  Future<List<Object>> readErrors(AtCollection<String> collection) async {
    final errors = <Object>[];
    await collection.getItemsAsStream().handleError(errors.add).drain<void>();
    return errors;
  }

  AtValue storedValue(String value) => AtValue()
    ..value = value
    ..metadata = (Metadata()
      ..createdAt = DateTime.now().toUtc()
      ..expiresAt = DateTime.now().add(const Duration(days: 1)));

  test(
      'a read that times out fails the listing instead of marking the item unreadable',
      () async {
    final collection = buildCollection();

    for (final failure in <Object>[
      AtTimeoutException('Waited for 10 millis. No response'),
      SecondaryConnectException('unable to connect to atServer'),
    ]) {
      when(() => atClient.get(any())).thenThrow(failure);

      final errors = await readErrors(collection);

      expect(errors, hasLength(1),
          reason: '${failure.runtimeType} reaches the caller raw');
      expect(errors.single, same(failure));
      expect(errors.single, isNot(isA<CItemReadException>()));
    }
  });

  test('a value that cannot be decoded is still reported unreadable', () async {
    final collection = buildCollection();
    when(() => atClient.get(any()))
        .thenAnswer((_) async => storedValue('not json'));

    final errors = await readErrors(collection);

    expect(errors, hasLength(1));
    expect(errors.single, isA<CItemReadException>());
    expect((errors.single as CItemReadException).cause, isA<FormatException>());
  });

  test('a read refused as unauthorised is still reported unreadable', () async {
    final collection = buildCollection();
    when(() => atClient.get(any()))
        .thenThrow(UnAuthorizedException('not allowed'));

    final errors = await readErrors(collection);

    expect(errors, hasLength(1));
    expect(errors.single, isA<CItemReadException>());
    expect((errors.single as CItemReadException).cause,
        isA<UnAuthorizedException>());
  });
}
