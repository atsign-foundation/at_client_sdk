import 'package:at_client/at_client.dart';
import 'package:at_client/src/lifecycle/lookups_io.dart' as io;
import 'package:at_client/src/lifecycle/lookups_web.dart' as web;
import 'package:at_lookup/at_lookup_io.dart';
import 'package:test/test.dart';

void main() {
  final preference = AtClientPreference()
    ..rootDomain = 'root.example'
    ..rootPort = 6464;

  group('web branch', () {
    test('defaultLookUps throws a StateError naming lookUps:', () {
      expect(
          () => web.defaultLookUps(preference),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('lookUps:'))));
      expect(
          () => web.defaultLookUps(),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('lookUps:'))));
    });

    test(
        'defaultSecondaryAddressFinder throws a StateError naming '
        'secondaryAddressFinder:', () {
      expect(
          () => web.defaultSecondaryAddressFinder(preference),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              contains('secondaryAddressFinder:'))));
    });
  });

  group('io branch', () {
    test('defaultLookUps builds TLS lookups', () {
      final lookUp = io.defaultLookUps(preference)(
          atSign: '@io',
          rootDomain: const AtRootDomain('127.0.0.1', 64),
          authenticator: null);
      expect(lookUp, isA<AtLookupImpl>());
    });

    test('defaultSecondaryAddressFinder asks the atDirectory', () {
      expect(io.defaultSecondaryAddressFinder(preference),
          isA<CacheableSecondaryAddressFinder>());
    });
  });
}
