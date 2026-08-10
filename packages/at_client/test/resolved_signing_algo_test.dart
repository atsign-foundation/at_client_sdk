import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:at_client/src/signing/resolved_signing_algo.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

void main() {
  group('the resolved-signing-algo record', () {
    test('answers with the recorded resolution', () {
      final client = MockAtClient();
      recordResolvedSigningAlgo(client, SigningAlgoType.mldsa65);
      expect(signingAlgoOf(client), SigningAlgoType.mldsa65);
      expect(resolvedSigningAlgoFor(client), SigningAlgoType.mldsa65);
    });

    test('falls back to the preference when nothing was recorded', () {
      final client = MockAtClient();
      when(() => client.getPreferences()).thenReturn(AtClientPreference()
        // The documented legacy fallback for untyped key material.
        // ignore: deprecated_member_use
        ..signingAlgoType = SigningAlgoType.ecc_secp256r1);
      expect(signingAlgoOf(client), SigningAlgoType.ecc_secp256r1);
      expect(resolvedSigningAlgoFor(client), isNull,
          reason: 'the fallback is not a resolution');
    });

    test('defaults to rsa2048 with no record and no preference', () {
      final client = MockAtClient();
      when(() => client.getPreferences()).thenReturn(null);
      expect(signingAlgoOf(client), SigningAlgoType.rsa2048);
    });

    test('a null record clears back to the fallback', () {
      final client = MockAtClient();
      when(() => client.getPreferences()).thenReturn(null);
      recordResolvedSigningAlgo(client, SigningAlgoType.mldsa65);
      recordResolvedSigningAlgo(client, null);
      expect(signingAlgoOf(client), SigningAlgoType.rsa2048);
      expect(resolvedSigningAlgoFor(client), isNull);
    });

    test('two clients of one atSign keep separate records', () {
      final a = MockAtClient();
      final b = MockAtClient();
      when(() => b.getPreferences()).thenReturn(null);
      recordResolvedSigningAlgo(a, SigningAlgoType.mldsa65);
      expect(signingAlgoOf(a), SigningAlgoType.mldsa65);
      expect(signingAlgoOf(b), SigningAlgoType.rsa2048);
    });
  });
}
