import 'package:at_client/src/client/pq_client_bootstrap.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/enroll/privilege_resolver.dart';
import 'package:at_client/src/client/remote_secondary.dart'
    show RemoteSecondary;
import 'package:at_client/src/secret_sharing/at_client_secret_sharing.dart';
import 'package:at_client/src/service/enrollment_privilege_resolver.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookupImpl;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtLookupImpl extends Mock implements AtLookupImpl {}

class _FakePrivilege implements EnrollmentPrivilegeResolver {
  _FakePrivilege(this.answer);
  final bool answer;
  int calls = 0;
  @override
  Future<bool> isFullyPrivileged() async {
    calls++;
    return answer;
  }
}

void main() {
  late MockAtClient client;

  setUp(() {
    client = MockAtClient();
    when(() => client.getCurrentAtSign()).thenReturn('@bootstrap🛠');
    when(() => client.enrollmentId).thenReturn(null);
    when(() => client.getPreferences()).thenReturn(null);
  });

  PqClientBootstrap build({
    EnrollmentPrivilegeResolver? privilege,
    Future<int> Function()? sweep,
    PqStartupGates gates = const PqStartupGates(),
  }) =>
      PqClientBootstrap(
        client,
        keysIo: null,
        privilege: privilege ?? _FakePrivilege(false),
        sweepUnanchoredEnrollments: sweep ?? (() async => 0),
        gates: gates,
      );

  group('the bootstrap collapses the instance fragmentation', () {
    test('the crypto-config ring IS the bootstrap ring', () {
      final bootstrap = build();
      CryptoConfig.adoptEraDefault(
        client,
        CryptoConfig.readsNskeyWritesLegacy(keyRing: bootstrap.ring),
      );
      final config = CryptoConfig.forClient(client);
      final providers = config.providers.whereType<NskeyProvider>().toList();
      expect(providers, isNotEmpty);
      for (final provider in providers) {
        expect(identical(provider.keyRing, bootstrap.ring), isTrue,
            reason: 'reads must see what the startup steps minted and filed');
      }
    });

    test('seeding, sharing and ring are single shared instances', () {
      final bootstrap = build();
      expect(identical(bootstrap.seeding.ring, bootstrap.ring), isTrue);
      expect(
          identical(
              bootstrap.sharing, AtClientSecretSharing.forClient(client)),
          isTrue,
          reason: 'forClient caches per client; the bootstrap must hold '
              'that instance, not a rival');
      expect(identical(bootstrap.seeding.privateFiling, bootstrap.filing),
          isTrue);
    });
  });

  group('startup', () {
    test('completes despite every step failing or skipping, and is '
        'idempotent', () async {
      final bootstrap = build();
      // With no keysIo, no preference and unstubbed client calls, every
      // step either skips its precondition or throws internally; each
      // failure is contained and startupComplete still completes.
      await bootstrap.startup();
      await bootstrap.startupComplete;
      // A second call must not re-run the steps.
      await bootstrap.startup();
    });

    test('the sweep runs only for a fully privileged client', () async {
      var swept = 0;
      final privileged = _FakePrivilege(true);
      await build(privilege: privileged, sweep: () async => ++swept)
          .startup();
      expect(swept, 1);

      swept = 0;
      await build(privilege: _FakePrivilege(false), sweep: () async => ++swept)
          .startup();
      expect(swept, 0, reason: 'an unprivileged client must not sweep');
    });

    test('gates silence the active steps', () async {
      var swept = 0;
      final privilege = _FakePrivilege(true);
      await build(
        privilege: privilege,
        sweep: () async => ++swept,
        gates: const PqStartupGates(
          requestRootPrivate: false,
          requestMissingPrivates: false,
          publishRootLink: false,
          publishChainLink: false,
          sweepUnanchoredEnrollments: false,
          askOnReadMiss: false,
        ),
      ).startup();
      expect(swept, 0, reason: 'the sweep gate must silence the sweep');
      expect(privilege.calls, 0,
          reason: 'a fully gated startup has no reason to resolve '
              'privilege at all');
    });
  });

  group('the record-backed privilege resolver', () {
    test('a client with no enrollment id is fully privileged by '
        'construction', () async {
      final remote = MockRemoteSecondary();
      final lookUp = MockAtLookupImpl();
      when(() => client.getRemoteSecondary()).thenReturn(remote);
      when(() => remote.atLookUp).thenReturn(lookUp);
      when(() => lookUp.enrollmentId).thenReturn(null);
      expect(
          await EnrollmentRecordPrivilegeResolver(client).isFullyPrivileged(),
          isTrue);
    });
  });

  test('the step order is the documented one', () {
    expect(PqClientBootstrap.stepNamesInOrder, const [
      'hydrateHeldSecrets',
      'collectConveyedKeys',
      'seedNamespaceKeys',
      'requestRootPrivate',
      'requestMissingPrivates',
      'publishRootLink',
      'publishChainLink',
      'sweepUnanchoredEnrollments',
    ]);
  });
}
