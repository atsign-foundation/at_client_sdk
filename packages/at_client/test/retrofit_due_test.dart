import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:test/test.dart';

void main() {
  group('Whether a posture is due a retrofit', () {
    /// The three cells of ruling 113's posture matrix, read off the postures
    /// themselves rather than restated, so a posture whose algorithm changes
    /// moves this test with it.
    test('legacy drives no retrofit from a legacy enrollment', () {
      expect(
          AtClientImpl.retrofitIsDue(
              wanted: PqPosture.legacy.authenticationKeyAlgorithm,
              held: SigningAlgoType.rsa2048),
          false,
          reason: 'legacy means "do not drive an upgrade"');
    });

    test('either PQ posture retrofits a legacy enrollment', () {
      for (final posture in [PqPosture.pqReady, PqPosture.pqActive]) {
        expect(
            AtClientImpl.retrofitIsDue(
                wanted: posture.authenticationKeyAlgorithm,
                held: SigningAlgoType.rsa2048),
            true,
            reason: 'a PQ posture must move an rsa2048 enrollment');
      }
    });

    test('pqActive asks nothing of an enrollment already at pqReady', () {
      expect(
          AtClientImpl.retrofitIsDue(
              wanted: PqPosture.pqActive.authenticationKeyAlgorithm,
              held: PqPosture.pqReady.authenticationKeyAlgorithm),
          false,
          reason: 'both authenticate with the same key; only the DATA signing '
              'key moves between those stages, and that is minted unilaterally');
    });

    /// Ruling 1: a posture is a floor and never a downgrade. This is the arm
    /// that matters for an app pinned to an older at_client — it must not be
    /// able to drag a moved atSign back.
    test('no posture can downgrade an enrollment that has already moved', () {
      for (final posture in [
        PqPosture.legacy,
        PqPosture.pqReady,
        PqPosture.pqActive
      ]) {
        expect(
            AtClientImpl.retrofitIsDue(
                wanted: posture.authenticationKeyAlgorithm,
                held: SigningAlgoType.mldsa65),
            false,
            reason:
                'key material wins: ${posture.authenticationKeyAlgorithm.name} '
                'must not displace a stronger key already held');
      }
    });

    test('a weaker key than either named algorithm is still moved up', () {
      expect(
          AtClientImpl.retrofitIsDue(
              wanted: SigningAlgoType.rsa4096, held: SigningAlgoType.rsa2048),
          true,
          reason: 'the ordering is at_chops strongestFirst, not a two-value '
              'special case');
    });
  });
}
