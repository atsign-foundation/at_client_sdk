import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

class _FakeCryptoScheme implements CryptoScheme {
  int registerCallCount = 0;

  @override
  Future<dynamic> decrypt(AtKey atKey, dynamic value) async => value;

  @override
  Future<dynamic> encrypt(AtKey atKey, dynamic value) async => value;

  @override
  Future<void> register() async {
    registerCallCount++;
  }
}

void main() {
  group('SchemeRegistry', () {
    test('register adds scheme, calls register, and can lookup by name',
        () async {
      final registry = SchemeRegistry();
      final scheme = _FakeCryptoScheme();

      registry.register('schemeA', scheme);

      expect(registry.contains('schemeA'), isTrue);
      expect(registry.registeredNames, contains('schemeA'));
      expect(registry.lookup('schemeA'), same(scheme));
      expect(scheme.registerCallCount, 1);
    });

    test('lookup throws CryptoSchemeNotRegistered for unknown name', () {
      final registry = SchemeRegistry();

      expect(
        () => registry.lookup('missingScheme'),
        throwsA(
          isA<CryptoSchemeNotRegistered>().having(
            (e) => e.message,
            'message',
            contains('missingScheme'),
          ),
        ),
      );
    });

    test('contains returns false for unknown names', () {
      final registry = SchemeRegistry();

      expect(registry.contains('missingScheme'), isFalse);
    });

    test('registeredNames is empty initially', () {
      final registry = SchemeRegistry();

      expect(registry.registeredNames, isEmpty);
    });

    test('registering existing name overwrites prior scheme and re-registers',
        () async {
      final registry = SchemeRegistry();
      final first = _FakeCryptoScheme();
      final second = _FakeCryptoScheme();

      registry.register('sameName', first);
      registry.register('sameName', second);

      expect(registry.lookup('sameName'), same(second));
      expect(registry.registeredNames.where((e) => e == 'sameName').length, 1);
      expect(first.registerCallCount, 1);
      expect(second.registerCallCount, 1);
    });

    test('registeredNames is not growable', () {
      final registry = SchemeRegistry();
      registry.register('schemeA', _FakeCryptoScheme());
      final names = registry.registeredNames;

      expect(() => names.add('newName'), throwsUnsupportedError);
    });
  });
}
