/// The shared mocks and fakes. A test file declaring its own copy of one of
/// these shadows the shared version silently — a local declaration wins over
/// an import with no analyzer complaint — so the two drift apart unnoticed.
///
/// ⚠️ Several mocks here stub a member in their CONSTRUCTOR. That makes
/// `thenReturn(MockX())` unsafe: the mock is built while the enclosing `when`
/// is still mid-registration, and mocktail refuses a nested `when` with
/// *Cannot call `when` within a stub response*. Build it on its own line and
/// pass the variable. The failure is immediate and names itself, so the suite
/// is the guard - but it surfaces on whichever test runs next, not on the line
/// at fault.
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
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';

/// A lookup that answers every command with null until a test says otherwise.
///
/// `executeCommand` returns `Future<String?>`, so the VALUE was always allowed
/// to be null; what an unstubbed member could not supply was the future. This
/// answers the future and keeps the null, which says "nothing came back" -
/// true of a mock with no atServer behind it, and better than answering a
/// command with content no test chose.
///
/// ⚠️ Null is not universally safe to answer: a caller is free to treat an
/// unreadable response as an error rather than as an absence, and
/// `VerbEnrollmentDirectory.listForNamespace` deliberately does. This default
/// is kept because every path measured in this suite handles it; a test whose
/// caller does not must model the response itself, which supersedes this.
void _answerCommandsWithNothing(AtLookUp lookUp) {
  when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
      .thenAnswer((_) async => null);
}

class MockAtLookUp extends Mock implements AtLookUp {
  MockAtLookUp() {
    _answerCommandsWithNothing(this);
  }
}

class MockAtLookupImpl extends Mock implements AtLookupImpl {
  MockAtLookupImpl() {
    _answerCommandsWithNothing(this);
  }
}

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
    // A real RemoteSecondary always has a lookup, and it carries no
    // enrollment id unless one was named - so a client built on this is fully
    // privileged, which is what the fixtures that stub their own lookup also
    // choose. Only the lookup itself is answered: what it would send is the
    // fixture's business, and a test needing that supersedes this.
    final atLookUp = MockAtLookupImpl();
    when(() => atLookUp.enrollmentId).thenReturn(null);
    when(() => this.atLookUp).thenReturn(atLookUp);
  }
}

class MockLocalSecondary extends Mock implements LocalSecondary {}

/// Gives [atClient] a local secondary holding the two keys an approval reads
/// of its own atSign: the encryption private key, which unwraps the symmetric
/// key a legacy enrollee RSA-wrapped to it, and the self-encryption key, one
/// of the two secrets approval seals for the enrollee.
///
/// Real demo material rather than placeholders, so a test that goes on to
/// unwrap or open with it gets keys that work. Returns the local secondary for
/// a test that wants to stub more on it.
MockLocalSecondary stubApproverKeys(AtClient atClient,
    {String demoAtSign = '@alice🛠'}) {
  final local = MockLocalSecondary();
  when(() => atClient.getLocalSecondary()).thenReturn(local);
  when(() => local.getEncryptionPrivateKey())
      .thenAnswer((_) async => demo.encryptionPrivateKeyMap[demoAtSign]!);
  when(() => local.getEncryptionSelfKey())
      .thenAnswer((_) async => demo.aesKeyMap[demoAtSign]!);
  return local;
}

/// Stubs [localSecondary] to answer [atSign]'s encryption keypair.
///
/// This is how a client resolves that keypair: `LocalSecondary` consults an
/// injected `AtChops`, then the client's key source, then the keystore, and a
/// mock standing in for it answers directly. Stubbing an `AtChops` on the
/// client instead reaches the same material through the deprecated door, and
/// leaves the paths that read it through the local secondary unexercised.
/// [localSecondary] is typed as the interface because that is how the test
/// trees declare their doubles; mocktail records against the instance.
void stubEncryptionKeyPair(
    LocalSecondary localSecondary, String atSign, RsaKeyPair keyPair) {
  when(() => localSecondary.getEncryptionPublicKey(atSign))
      .thenAnswer((_) async => keyPair.atPublicKey.publicKey);
  when(() => localSecondary.getEncryptionPrivateKey())
      .thenAnswer((_) async => keyPair.atPrivateKey.privateKey);
}

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
          ..namespace = 'wavi' {
    _answerReadsAsMissing();
  }

  // A stable, mutable preference (matching the real getPreferences(), which
  // returns the live instance) so tests can set `.crypto` to inject a
  // CryptoConfig that CryptoRuntime resolves against.
  final AtClientPreference _preference;

  /// A read of a key nothing stored, which is what a client with no fixture
  /// data behind it should see. Registered in the constructor, so any `when`
  /// a test writes afterwards supersedes it - mocktail takes the last
  /// matching response. Left unstubbed it answered null into a non-nullable
  /// `Future<AtValue>`, and the caller logged a defect instead of a miss.
  void _answerReadsAsMissing() {
    registerFallbackValue(AtKey());
    when(() => get(any(), getRequestOptions: any(named: 'getRequestOptions')))
        .thenAnswer((inv) async =>
            throw AtKeyNotFoundException('${inv.positionalArguments[0]}'));
    when(() => get(any())).thenAnswer((inv) async =>
        throw AtKeyNotFoundException('${inv.positionalArguments[0]}'));
  }

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
  // unstubbed mocktail getter answers null, which the runtime refuses for the
  // non-nullable AtConnection; a Monitor built from this mock reads it.
  @override
  final AtConnection connection = AtConnection(
      atSign: '@alice',
      attempt: (_) async =>
          AtConnectionState.offline(AtConnectionCause.unattempted));
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
