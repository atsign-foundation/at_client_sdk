import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {
}

class NoopPersistence implements SecretStorePersistence {
  @override
  Future<List<Secret>> load() async => [];

  @override
  Future<void> save(List<Secret> secrets) async {}
}

void main() {
  group('AtClientSecretSharing.forClient', () {
    test('returns one shared instance per AtClient', () {
      final atClientA = MockAtClient();
      final atClientB = MockAtClient();

      final a1 = AtClientSecretSharing.forClient(atClientA);
      final a2 = AtClientSecretSharing.forClient(atClientA);
      final b = AtClientSecretSharing.forClient(atClientB);

      expect(identical(a1, a2), isTrue,
          reason: 'same AtClient must yield the same shared instance');
      expect(identical(a1, b), isFalse);
    });

    test('the creating call wires persistence; later calls cannot replace it',
        () {
      final atClient = MockAtClient();
      final persistence = NoopPersistence();

      final first =
          AtClientSecretSharing.forClient(atClient, persistence: persistence);
      expect(first.secretStore.persistence, same(persistence));

      final second = AtClientSecretSharing.forClient(atClient,
          persistence: NoopPersistence());
      expect(identical(first, second), isTrue);
      expect(second.secretStore.persistence, same(persistence),
          reason: 'persistence is fixed by the creating call');
    });

    test('the plain constructor still creates independent instances', () {
      final atClient = MockAtClient();
      final shared = AtClientSecretSharing.forClient(atClient);
      final independent = AtClientSecretSharing(atClient);
      expect(identical(shared, independent), isFalse);
    });
  });
}
