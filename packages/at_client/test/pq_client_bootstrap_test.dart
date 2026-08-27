import 'dart:async';

import 'package:at_auth/at_auth.dart'
    show
        AtKeys,
        AtKeysIo,
        InMemoryAtKeysIo,
        CryptographicMaterialAlgorithm,
        WrittenAtKeysIo;
import 'package:at_client/src/client/pq_client_bootstrap.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/preference/at_client_preference.dart'
    show AtClientPreference;
import 'package:at_client/src/response/enrollment.dart' show Enrollment;
import 'package:at_commons/atsign.dart' show AtsignString;
import 'package:at_utils/at_utils.dart'
    show AtSignLogger, LoggingHandler;
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/enroll/privilege_resolver.dart';
import 'package:at_client/src/secret_sharing/at_client_secret_sharing.dart';
import 'package:at_client/src/service/enrollment_privilege_resolver.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';

class MockAtClient extends Mock implements AtClient {}

/// Captures what the bootstrap logs, so a claim about a log LEVEL can be
/// asserted rather than eyeballed.
///
/// `AtSignLogger.defaultLoggingHandler` is a settable static and each
/// `AtSignLogger` binds its handler at construction, so this must be installed
/// **before** the bootstrap under test is built.
///
/// The parameter is `dynamic` rather than `LogRecord` on purpose: overriding
/// with a supertype is legal, and it keeps `package:logging` — which at_client
/// does not depend on and imports nowhere — out of the dependency list for the
/// sake of one test.
class _RecordedLogs implements LoggingHandler {
  final List<({String level, String message})> records = [];

  @override
  void call(dynamic record) => records.add(
      (level: '${record.level.name}', message: '${record.message}'));

  Iterable<String> at(String level) =>
      records.where((r) => r.level == level).map((r) => r.message);
}

// AtKeysIo itself is sealed; its abstract written flavour is the mockable
// face.
class MockAtKeysIo extends Mock implements WrittenAtKeysIo {}

class _FakePrivilege implements EnrollmentPrivilegeResolver {
  _FakePrivilege(this.answer);
  final bool answer;
  int calls = 0;
  final List<String> byIdCalls = [];
  @override
  Future<bool> isFullyPrivileged() async {
    calls++;
    return answer;
  }

  @override
  Future<bool> isEnrollmentFullyPrivileged(String enrollmentId) async {
    byIdCalls.add(enrollmentId);
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

    test(
        'construction wires the per-enrollment request gate to the '
        'privilege seam', () async {
      final privilege = _FakePrivilege(true);
      final bootstrap = build(privilege: privilege);

      final gate = bootstrap.sharing.perEnrollmentSecretRequestGate;
      expect(gate, isNotNull,
          reason: 'a null gate fails closed for every requester; the '
              'production composition must install the resolver at '
              'construction, because a request can arrive as soon as the '
              'client listens — not only after the startup steps run');
      expect(await gate!('enroll-x'), isTrue);
      expect(privilege.byIdCalls, ['enroll-x'],
          reason: 'the gate consults the ONE injected seam, with the '
              'requester\'s id');
      expect(privilege.calls, 0,
          reason: 'the requester\'s privilege is the question, not this '
              'client\'s own');
    });

    test('seeding, sharing and ring are single shared instances', () {
      final bootstrap = build();
      expect(identical(bootstrap.seeding.ring, bootstrap.ring), isTrue);
      expect(
          identical(bootstrap.sharing, AtClientSecretSharing.forClient(client)),
          isTrue,
          reason: 'forClient caches per client; the bootstrap must hold '
              'that instance, not a rival');
      expect(
          identical(bootstrap.seeding.privateFiling, bootstrap.filing), isTrue);
    });
  });

  group('startup', () {
    test(
        'completes despite every step failing or skipping, and is '
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
      await build(privilege: privileged, sweep: () async => ++swept).startup();
      expect(swept, 1);

      swept = 0;
      await build(privilege: _FakePrivilege(false), sweep: () async => ++swept)
          .startup();
      expect(swept, 0, reason: 'an unprivileged client must not sweep');
    });

    test('stop() between steps halts the startup', () async {
      // Park the first step: hydration reads the keyfile, and the read's
      // future is under this test's control.
      final keysIo = MockAtKeysIo();
      final readGate = Completer<Never>();
      when(() => keysIo.read(any())).thenAnswer((_) => readGate.future);

      var swept = 0;
      final privilege = _FakePrivilege(true);
      final bootstrap = PqClientBootstrap(
        client,
        keysIo: keysIo,
        privilege: privilege,
        sweepUnanchoredEnrollments: () async => ++swept,
      );

      final startup = bootstrap.startup();
      bootstrap.stop();
      // The parked step finishes (by failing, which hydration contains);
      // no step after it may start.
      readGate.completeError(Exception('the test releases the parked read'));
      await startup;
      await bootstrap.startupComplete;

      expect(swept, 0, reason: 'a stopped client must not sweep');
      expect(privilege.calls, 0,
          reason: 'no step after the stop may run at all');
    });

    test('an abandoned startup says so at WARNING, naming what it skipped',
        () async {
      // The cost of an abandoned tail is paid by a DIFFERENT principal in a
      // different process: this atSign goes on sending while no peer can seal
      // to it, so the only symptom appears at the far end naming the wrong
      // party. That is the same reason a dropped delivery-loop event logs at
      // warning, and this line logged at `info` until 2026-08-27 — among 31
      // other info lines in a 15-second run, measured.
      final logs = _RecordedLogs();
      final previousHandler = AtSignLogger.defaultLoggingHandler;
      final previousLevel = AtSignLogger.root_level;
      AtSignLogger.defaultLoggingHandler = logs;
      AtSignLogger.root_level = 'info';
      addTearDown(() {
        AtSignLogger.defaultLoggingHandler = previousHandler;
        AtSignLogger.root_level = previousLevel;
      });

      // The default fixture answers null here; the consequence sentence is
      // conditional on this client actually being one that seeds, so a null
      // preference would make the test assert the absence of the sentence it
      // is about.
      when(() => client.getPreferences())
          .thenReturn(AtClientPreference()..seedNamespaceKeys = true);

      // Built AFTER the handler is installed — AtSignLogger binds its handler
      // at construction, so a bootstrap built earlier would log elsewhere and
      // this test would assert against an empty recorder.
      final keysIo = MockAtKeysIo();
      final readGate = Completer<Never>();
      when(() => keysIo.read(any())).thenAnswer((_) => readGate.future);
      final bootstrap = PqClientBootstrap(
        client,
        keysIo: keysIo,
        privilege: _FakePrivilege(true),
        sweepUnanchoredEnrollments: () async => 0,
      );

      final startup = bootstrap.startup();
      bootstrap.stop();
      readGate.completeError(Exception('the test releases the parked read'));
      await startup;

      // The POSITIVE CONTROL for the recorder, and it has to be independent
      // of the level under test: the parked read this fixture arranges makes
      // the hydrate step log at SEVERE, which arrives whatever level the
      // abandonment uses. Controlling on WARNING instead would go red under
      // the very mutation this test exists to catch, so an empty recorder and
      // a wrongly-levelled line would be indistinguishable.
      expect(logs.records, isNotEmpty,
          reason: 'the recorder is installed and capturing; without this an '
              'empty capture satisfies every absence assertion below while '
              'measuring nothing');

      final warnings = logs.at('WARNING').toList();

      final abandoned =
          warnings.where((m) => m.contains('was stopped with')).toList();
      expect(abandoned, hasLength(1),
          reason: 'the abandonment is reported once, at warning');
      expect(abandoned.single, contains('seedNamespaceKeys'),
          reason: 'and it NAMES the step that did not run — "the remaining '
              'steps" is not something a reader can act on, and which ones '
              'were missed is what decides what is now untrue');
      expect(abandoned.single, contains('no peer can seal to it'),
          reason: 'and states the consequence, because the symptom surfaces '
              'at a different atSign that names this one as the problem');
      expect(logs.at('INFO').where((m) => m.contains('PQ startup stopped')),
          isEmpty,
          reason: 'and it is no longer only an info line, which is what let '
              'it sit unread beside every other startup line');
    });

    test('mintSettled settles once the mint step has run', () async {
      final bootstrap = build();
      var done = false;
      unawaited(bootstrap.mintSettled.then((_) => done = true));
      await pumpEventQueue();
      expect(done, isFalse,
          reason: 'nothing may settle the barrier before startup reaches '
              'the mint step — a signer that proceeded early would sign in '
              'the exact window the barrier exists to close');
      await bootstrap.startup();
      expect(done, isTrue);
    });

    test('mintSettled settles at the mint step, not at startup\'s end',
        () async {
      // Park the sweep — a step after the mint — so startup is still running
      // when the assertion looks.
      final parked = Completer<int>();
      final bootstrap =
          build(privilege: _FakePrivilege(true), sweep: () => parked.future);
      final startup = bootstrap.startup();
      await bootstrap.mintSettled.timeout(const Duration(seconds: 5),
          onTimeout: () =>
              fail('the barrier must lift when the mint step has run, not when '
                  'the whole startup tail has — the steps after the mint sign '
                  'envelopes, and each of those signs would wait on itself'));
      parked.complete(0);
      await startup;
    });

    test('a startup stopped before the mint step still settles mintSettled',
        () async {
      final keysIo = MockAtKeysIo();
      final readGate = Completer<Never>();
      when(() => keysIo.read(any())).thenAnswer((_) => readGate.future);

      final bootstrap = PqClientBootstrap(
        client,
        keysIo: keysIo,
        privilege: _FakePrivilege(true),
        sweepUnanchoredEnrollments: () async => 0,
      );

      final startup = bootstrap.startup();
      bootstrap.stop();
      readGate.completeError(Exception('the test releases the parked read'));
      await startup;

      await bootstrap.mintSettled.timeout(const Duration(seconds: 5),
          onTimeout: () => fail(
              'a stopped startup never reaches the mint step, and a signer '
              'waiting on a barrier nothing settles waits forever'));
    });

    test('a gated-off mint still settles mintSettled', () async {
      final bootstrap =
          build(gates: const PqStartupGates(mintInUseSigningKeys: false));
      await bootstrap.startup();
      await bootstrap.mintSettled.timeout(const Duration(seconds: 5),
          onTimeout: () =>
              fail('gated-off must settle the barrier: whatever the keyfile '
                  'holds after the step is what may sign'));
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
    test(
        'a client with no enrollment id is fully privileged by '
        'construction', () async {
      final remote = MockRemoteSecondary();
      final lookUp = MockAtLookupImpl();
      when(() => client.getRemoteSecondary()).thenReturn(remote);
      when(() => remote.atLookUp).thenReturn(lookUp);
      when(() => lookUp.enrollmentId).thenReturn(null);
      expect(
          await EnrollmentRecordPrivilegeResolver(client,
                  listEnrollments: ({enrollmentListParams}) async => [])
              .isFullyPrivileged(),
          isTrue);
    });
  });

  group('the enrollment snapshot', () {
    const atSign = '@bootstrap🛠';
    const enrollmentId = 'enroll-1';

    /// A keyfile holding APKAM material for [id], so the enrollment slot
    /// exists — which is the precondition the reconciliation requires.
    Future<InMemoryAtKeysIo> keyfileHolding(String id) async {
      final io = InMemoryAtKeysIo();
      final keys = AtKeys(atsign: atSign.toAtsign())
        ..fileApkamMaterial(
          enrollmentId: id,
          algorithm: CryptographicMaterialAlgorithm.rsa2048,
          // AtBytes.fromString base64-decodes, so these have to be valid
          // base64 rather than readable placeholders.
          publicKey: 'cHVibGlj',
          privateKey: 'cHJpdmF0ZQ==',
        );
      await io.write(atSign, keys);
      return io;
    }

    MockLocalSecondary localSecondaryReturning(Enrollment? record) {
      final local = MockLocalSecondary();
      when(() => local.getEnrollmentDetails()).thenAnswer((_) async => record);
      return local;
    }

    Enrollment recordWith({
      Map<String, dynamic>? namespace,
      String? appName,
      String? deviceName,
    }) =>
        Enrollment()
          ..appName = appName
          ..deviceName = deviceName
          ..namespace = namespace;

    Future<void> runStartup(AtKeysIo io, MockLocalSecondary local) async {
      when(() => client.enrollmentId).thenReturn(enrollmentId);
      when(() => client.getLocalSecondary()).thenReturn(local);
      await PqClientBootstrap(
        client,
        keysIo: io,
        privilege: _FakePrivilege(false),
        sweepUnanchoredEnrollments: () async => 0,
      ).startup();
    }

    test('is filled in from the enrollment record on a keyfile that has none',
        () async {
      final io = await keyfileHolding(enrollmentId);
      await runStartup(
          io,
          localSecondaryReturning(recordWith(
            namespace: {'buzz': 'rw'},
            appName: 'wavi',
            deviceName: 'pixel',
          )));

      final held = (await io.read(atSign)).enrollmentInfo(enrollmentId)!;
      expect(held.namespaces, {'buzz': 'rw'});
      expect(held.appName, 'wavi');
      expect(held.deviceName, 'pixel');
    });

    test('is NOT created for an enrollment the keyfile holds no material for',
        () async {
      // The slot would be typed content, so creating one here rewrites a
      // legacy-flat keyfile as a version 1 document as a side effect of
      // merely opening it.
      final io = await keyfileHolding('some-other-enrollment');
      await runStartup(
          io, localSecondaryReturning(recordWith(namespace: {'buzz': 'rw'})));

      expect((await io.read(atSign)).enrollmentInfo(enrollmentId), isNull);
    });

    test('a changed grant is recorded, and said out loud', () async {
      final io = await keyfileHolding(enrollmentId);
      await io.update(atSign.toAtsign(), (keys) {
        keys.recordEnrollmentSnapshot(enrollmentId,
            namespaces: {'buzz': 'rw'}, appName: 'wavi');
        return true;
      });

      await runStartup(
          io, localSecondaryReturning(recordWith(namespace: {'buzz': 'r'})));

      expect((await io.read(atSign)).enrollmentInfo(enrollmentId)!.namespaces,
          {'buzz': 'r'},
          reason: 'the atServer is the authority on what this enrollment '
              'may reach');
    });

    test('a client authenticating with the atSign\'s own keys records nothing',
        () async {
      final io = await keyfileHolding(enrollmentId);
      final local = localSecondaryReturning(recordWith(appName: 'wavi'));
      when(() => client.enrollmentId).thenReturn(null);
      when(() => client.getLocalSecondary()).thenReturn(local);
      await PqClientBootstrap(
        client,
        keysIo: io,
        privilege: _FakePrivilege(false),
        sweepUnanchoredEnrollments: () async => 0,
      ).startup();

      verifyNever(() => local.getEnrollmentDetails());
    });

    test('a non-String grant value is skipped rather than stringified',
        () async {
      final io = await keyfileHolding(enrollmentId);
      await runStartup(
          io,
          localSecondaryReturning(
              recordWith(namespace: {'buzz': 'rw', 'broken': 42})));

      expect((await io.read(atSign)).enrollmentInfo(enrollmentId)!.namespaces,
          {'buzz': 'rw'},
          reason: "'42' recorded as an access level would read as a grant");
    });
  });

  test('the step order is the documented one', () {
    // ⚠️ **This pinned a hand-written copy until 2026-08-19, and the copy had
    // drifted.** `stepNamesInOrder` was a `static const` transcription of the
    // sequence written out beside it, so this test compared one transcription
    // to another and never read the list `startup()` iterates. It was missing
    // `startEnvelopeListener` and stayed green through that omission. The
    // getter is now derived from the real list, so a step added without a row
    // here goes red — which is the whole point of an ordering pin.
    expect(build().stepNamesInOrder, const [
      'hydrateHeldSecrets',
      'collectConveyedKeys',
      'startEnvelopeListener',
      // Before every step that signs — seeding, both link publications and
      // the sweep all produce signed envelopes, and a key minted after them
      // would leave that start's envelopes signed under a key the
      // advertisement of that moment did not name.
      'mintInUseSigningKeys',
      // After the signing keys, because the key package is signed by whatever
      // key `_apsk` advertises: signing it first would sign under the key this
      // start is about to retire, and a peer verifying against the new `_apsk`
      // would refuse a package written moments earlier.
      'reconcileKeyPackage',
      'seedNamespaceKeys',
      'requestRootPrivate',
      'requestMissingPrivates',
      'publishRootLink',
      'publishChainLink',
      'sweepUnanchoredEnrollments',
      // Last: nothing reads the enrollment snapshot, so this step can only
      // delay a step that heals key material, never enable one.
      'reconcileEnrollmentSnapshot',
    ]);
  });
}
