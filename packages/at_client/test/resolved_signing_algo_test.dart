import 'package:at_client/at_client.dart';
import 'package:at_client/src/signing/resolved_signing_algo.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

/// How a client's PKAM signing algorithm resolves: the recorded key-material
/// resolution first, then rsa2048, the algorithm of a flat keyfile.
void main() {
  group('the resolved-signing-algo record', () {
    test('answers with the recorded resolution', () {
      final client = MockAtClient();
      recordResolvedSigningAlgo(client, SigningAlgoType.mldsa65);
      expect(signingAlgoOf(client), SigningAlgoType.mldsa65);
      expect(resolvedSigningAlgoFor(client), SigningAlgoType.mldsa65);
    });

    test('falls back to rsa2048 when nothing was recorded', () {
      final client = MockAtClient();
      expect(signingAlgoOf(client), SigningAlgoType.rsa2048);
      expect(resolvedSigningAlgoFor(client), isNull,
          reason: 'the fallback is not a resolution');
    });

    test('a null record clears back to the fallback', () {
      final client = MockAtClient();
      recordResolvedSigningAlgo(client, SigningAlgoType.mldsa65);
      recordResolvedSigningAlgo(client, null);
      expect(signingAlgoOf(client), SigningAlgoType.rsa2048);
      expect(resolvedSigningAlgoFor(client), isNull);
    });

    test('two clients of one atSign keep separate records', () {
      final a = MockAtClient();
      final b = MockAtClient();
      recordResolvedSigningAlgo(a, SigningAlgoType.mldsa65);
      expect(signingAlgoOf(a), SigningAlgoType.mldsa65);
      expect(signingAlgoOf(b), SigningAlgoType.rsa2048);
    });
  });
}
