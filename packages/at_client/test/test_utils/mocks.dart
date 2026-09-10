/// The shared mocks and fakes. A test file declaring its own copy of one of
/// these shadows the shared version silently — a local declaration wins over
/// an import with no analyzer complaint — so the two drift apart unnoticed.
///
/// Some mocks stay in the test file that uses them because they carry
/// behaviour rather than duplicating one of these — a concrete override cannot
/// be intercepted by `when(...)`, so adopting a shared version would silently
/// disable a stub. Before moving a family here, check that every copy is
/// genuinely identical: a copy that grew a method is an intentional
/// difference, not a duplicate.
library;

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';

class MockAtLookUp extends Mock implements AtLookUp {}

class MockAtLookupImpl extends Mock implements AtLookupImpl {}

class MockAtChops extends Mock implements AtChops {}

class MockAtChopsKeys extends Mock implements AtChopsKeys {}

class MockSecondaryAddressFinder extends Mock
    implements SecondaryAddressFinder {}

/// A [RemoteSecondary] mock whose `closeConnection()` answers with a completed
/// future, as the real one does.
///
/// Stubbed in the constructor rather than given a concrete body: a concrete
/// override never reaches `noSuchMethod`, so mocktail would record no call and
/// the teardown verification in `at_client_termination_test.dart` would assert
/// nothing while still passing. A test wanting different behaviour re-stubs it.
class MockRemoteSecondary extends Mock implements RemoteSecondary {
  MockRemoteSecondary() {
    when(() => closeConnection()).thenAnswer((_) async {});
  }
}

class MockLocalSecondary extends Mock implements LocalSecondary {}

class MockCryptoProvider extends Mock implements CryptoProvider {}

class FakeCryptoProvider extends Fake implements CryptoProvider {}

class MockAtClientManager extends Mock implements AtClientManager {}

class MockAtClient extends Mock implements AtClient {
  /// Both are constructor arguments rather than something a test sets
  /// afterwards because they are final on the preference, and
  /// `getPreferences()` is a concrete override here — so
  /// `when(() => client.getPreferences())` never reaches `noSuchMethod` and
  /// stubs nothing.
  MockAtClient({List<String>? keyEstablishmentAlgorithms, PqPosture? posture})
      : _preference = AtClientPreference(
            posture: posture ?? PqPosture.pqReady,
            keyEstablishmentAlgorithms: keyEstablishmentAlgorithms)
          ..namespace = 'wavi';

  // A stable, mutable preference (matching the real getPreferences(), which
  // returns the live instance) so tests can set `.crypto` to inject a
  // CryptoConfig that CryptoRuntime resolves against.
  final AtClientPreference _preference;

  @override
  AtClientPreference getPreferences() => _preference;
}

/// A client that refuses to encrypt new data with the legacy provider.
///
/// Its own class rather than a cascade on [MockAtClient] because
/// `disallowLegacyEncryption` is final and posture-only: a flag governing what
/// a client may write must not be flippable mid-run.
class StrictMockAtClient extends Mock implements AtClient {
  final AtClientPreference _preference =
      AtClientPreference(posture: PqPosture.pqActive);

  @override
  AtClientPreference getPreferences() => _preference;
}

class MockAtClientImpl extends Mock implements AtClientImpl {
  // NOTE: `implements` erases the concrete getter AtClientImpl carries, and an
  // unstubbed mocktail getter returns null into a non-nullable type.
  @override
  SigningAlgoType get signingAlgoType => SigningAlgoType.rsa2048;
}

/// `AtKeysIo` is `sealed`, but that only restricts direct subtyping of the
/// base — `WrittenAtKeysIo` is an ordinary `abstract class`, so extending it
/// outside at_auth is legal. `read` answers an empty document because a
/// client reads its keys at construction to learn which enrollment it runs
/// as; `write` throws so any accidental key write fails loudly.
class StubAtKeysIo extends WrittenAtKeysIo {
  @override
  Future<AtKeys> read(String atSign) async => AtKeys();

  @override
  Future<void> write(String atSign, AtKeys atKeys) =>
      throw UnimplementedError();
}

class MockSyncService extends Mock implements SyncService {}

class MockNotificationService extends Mock implements NotificationService {}

class MockEnrollmentService extends Mock implements EnrollmentService {}

class FakeLookupVerbBuilder extends Fake implements LookupVerbBuilder {}

class FakeLocalLookUpVerbBuilder extends Fake implements LLookupVerbBuilder {}

class FakeUpdateVerbBuilder extends Fake implements UpdateVerbBuilder {}

class FakeDeleteVerbBuilder extends Fake implements DeleteVerbBuilder {}

class FakeAtKey extends Fake implements AtKey {}

class FakeAtSigningInput extends Fake implements AtSigningInput {}

/// The two `enroll:list` command strings `EnrollmentServiceImpl.approve`
/// issues, in the order it issues them: the pre-approval read, then the
/// post-approval one.
List<String> approveListCommands() => [
      for (final statuses in const [
        [EnrollmentStatus.pending, EnrollmentStatus.approved],
        [EnrollmentStatus.approved],
      ])
        (EnrollVerbBuilder()
              ..operation = EnrollOperationEnum.list
              ..enrollmentStatusFilter = statuses)
            .buildCommand()
    ];

/// Stubs both `enroll:list` reads that `EnrollmentServiceImpl.approve` makes,
/// answering [answer] to each.
///
/// The two reads carry different status filters, and therefore different
/// command strings, so a stub registered against one of them leaves the other
/// falling through to `noSuchMethod`, which returns null into a
/// `Future<String?>` and surfaces as a TypeError naming neither the stub nor
/// the filter. A test whose subject is the difference between the two reads
/// should register the [approveListCommands] itself.
void stubApproveListReads(RemoteSecondary secondary, String answer) {
  for (final command in approveListCommands()) {
    when(() => secondary.executeCommand(command, auth: true))
        .thenAnswer((_) async => answer);
  }
}
