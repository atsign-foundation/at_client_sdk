import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtLookUp extends Mock implements AtLookUp {}

class MockSecondaryAddressFinder extends Mock
    implements SecondaryAddressFinder {}

/// The per-enrollment signing algorithm must reach every connection the
/// client owns. A self-retrofit's ML-DSA enrollment re-authenticates on
/// every reconnect — verb, monitor and sync alike — so a connection stamped
/// with the preference's rsa2048 default fails against the
/// record-authoritative atServer no matter how correct its AtChops are.
void main() {
  final preference = AtClientPreference()..namespace = 'unit';

  group('RemoteSecondary', () {
    test('threads a resolved signingAlgoType onto the AtLookUp', () {
      final lookUp = MockAtLookUp();
      RemoteSecondary('@alice', preference,
          atLookUp: lookUp,
          enrollmentId: 'pq-1',
          signingAlgoType: SigningAlgoType.mldsa65);

      verify(() => lookUp.signingAlgoType = SigningAlgoType.mldsa65).called(1);
      verifyNever(() => lookUp.signingAlgoType = SigningAlgoType.rsa2048);
    });

    test('defaults to the preference when no resolution is supplied', () {
      final lookUp = MockAtLookUp();
      RemoteSecondary('@alice', preference, atLookUp: lookUp);

      verify(() => lookUp.signingAlgoType = SigningAlgoType.rsa2048).called(1);
    });
  });

  group('Monitor', () {
    Monitor buildMonitor({SigningAlgoType? signingAlgoType}) => Monitor(
        atSign: '@alice',
        atClientPreference: preference,
        atChops: null,
        enrollmentId: 'pq-1',
        secondaryAddressFinder: MockSecondaryAddressFinder(),
        handleNotification: (_) async {},
        getLastNotificationTime: () async => null,
        signingAlgoType: signingAlgoType);

    test('carries a resolved signingAlgoType for its own re-authentication',
        () {
      expect(buildMonitor(signingAlgoType: SigningAlgoType.mldsa65)
          .signingAlgoType, SigningAlgoType.mldsa65);
    });

    test('defaults to the preference', () {
      expect(buildMonitor().signingAlgoType, SigningAlgoType.rsa2048);
    });
  });
}
