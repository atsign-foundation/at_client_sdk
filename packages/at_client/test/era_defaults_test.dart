import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/era_defaults.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

void main() {
  group('the per-client era-default registry', () {
    test('adopt-if-absent keeps the first value', () {
      final registry = EraDefaults<String>();
      final client = MockAtClient();
      registry.adoptIfAbsent(client, 'first');
      registry.adoptIfAbsent(client, 'second');
      expect(registry.of(client), 'first',
          reason: 'a re-used cached client keeps the value it was built '
              'with');
    });

    test('entries are per client, never shared', () {
      final registry = EraDefaults<String>();
      final a = MockAtClient();
      final b = MockAtClient();
      registry.adoptIfAbsent(a, 'for-a');
      expect(registry.of(b), isNull);
    });

    test('clear forgets, and a later adopt takes', () {
      final registry = EraDefaults<String>();
      final client = MockAtClient();
      registry.adoptIfAbsent(client, 'first');
      registry.clear(client);
      expect(registry.of(client), isNull);
      registry.adoptIfAbsent(client, 'second');
      expect(registry.of(client), 'second');
    });
  });
}
