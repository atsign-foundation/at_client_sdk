/// Catalogue: features/at_client/one_client_per_principal.feature
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client_io.dart';
import 'package:at_client/memory.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_lookup/at_lookup.dart' show AtAuthenticator;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/no_keys.dart';
import 'test_utils/transport.dart';

const _wait = Duration(seconds: 30);

/// How long tearDown waits for a test's builds to end once every gate is
/// open: well inside the 30 seconds the test runner gives a tearDown.
const _settle = Duration(seconds: 10);

/// What a build or a client's build refuses with while another client for
/// the same principal is live or being built.
final _refusal = isA<StateError>().having(
    (e) => e.message, 'message', contains('is already live or being built'));

/// An in-memory store that records when a build opens its backend, holds
/// that open until [release] completes, and then fails it when [fails]. It
/// records when its backend is closed.
class _GatedStorage extends InMemoryAtClientStorage {
  _GatedStorage(String atSign, {bool held = false, this.fails = false})
      : super(atSign: atSign, closedByClient: true) {
    if (!held) release.complete();
  }

  final bool fails;
  final entered = Completer<void>();
  final release = Completer<void>();
  bool closed = false;

  @override
  Future<void> openBackend() async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    if (fails) throw const _OpenFailed();
    await super.openBackend();
  }

  @override
  Future<void> closeBackend() async {
    closed = true;
    await super.closeBackend();
  }
}

class _OpenFailed implements Exception {
  const _OpenFailed();

  @override
  String toString() => '_OpenFailed: the store could not be opened';
}

/// [inner]'s keys, of which the first read [holds] picks, given its 1-based
/// number and the keys it read, waits on [release] once it has read them.
class _HeldKeysIo extends WrittenAtKeysIo {
  _HeldKeysIo(this.inner, {required this.holds});

  final WrittenAtKeysIo inner;
  final bool Function(int read, AtKeys keys) holds;
  final entered = Completer<void>();
  final release = Completer<void>();
  int _reads = 0;

  @override
  Future<AtKeys> read(String atsign) async {
    final keys = await inner.read(atsign);
    _reads++;
    if (!entered.isCompleted && holds(_reads, keys)) {
      entered.complete();
      await release.future;
    }
    return keys;
  }

  @override
  Future write(String atsign, AtKeys atKeys) => inner.write(atsign, atKeys);

  @override
  FutureOr<void> flush(Atsign atsign, AtKeys atKeys) =>
      inner.flush(atsign, atKeys);
}

/// [loopbackLookUps], adding to [asked] the atSign of each connection it
/// builds.
AtLookUpFactory _recording(List<String> asked) {
  final lookUps = loopbackLookUps();
  return (
      {required atSign,
      required rootDomain,
      required authenticator,
      secondaryAddressFinder}) {
    asked.add(atSign);
    return lookUps(
        atSign: atSign,
        rootDomain: rootDomain,
        authenticator: authenticator,
        secondaryAddressFinder: secondaryAddressFinder);
  };
}

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// Answers an authenticator's `from:` with a challenge for `@alice🛠` and its
/// `pkam:` with success.
class _PkamAtServer implements AtCommandExecutor {
  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    if (command.startsWith('from:')) {
      return 'data:_70ce5d4e-1b8e-4a7c-9d1e-7e6c2a9b8f10@alice🛠'
          ':4f3c2b1a-9e8d-4c7b-a6f5-e4d3c2b1a098';
    }
    return 'data:success';
  }
}

void main() {
  late SecondaryAddressFinder finder;
  late List<_GatedStorage> stores;
  late List<_HeldKeysIo> holds;
  late List<Future<Object>> outcomes;

  setUpAll(() {
    registerFallbackValue(_FakeVerbBuilder());
    registerFallbackValue((AtCommandExecutor _) async => true);
  });

  setUp(() async {
    finder = await refusingAtDirectory();
    stores = [];
    holds = [];
    outcomes = [];
  });

  tearDown(() async {
    for (final gate in [
      for (final s in stores) s.release,
      for (final h in holds) h.release
    ]) {
      if (!gate.isCompleted) gate.complete();
    }
    var hung = 0;
    final ended = await Future.wait([
      for (final outcome in outcomes)
        outcome.timeout(_settle, onTimeout: () {
          hung++;
          return 'still running';
        })
    ]);
    for (final client in ended.whereType<AtClient>()) {
      await client.stop();
    }
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.supersededInstanceKeys.clear();
    expect(hung, 0,
        reason: 'a build still running $_settle after its gates opened holds '
            'its claim into the tests after this one');
  });

  /// Starts a `buildAtClient` call for [atSign] on [storage] and returns what
  /// it ends with: the client, or what it threw.
  Future<Object> build(String atSign, _GatedStorage storage,
      {AtKeysIo? atKeysIo,
      String? enrollmentId,
      AtLookUpFactory? lookUps,
      AtClientPreference? preference}) {
    stores.add(storage);
    if (atKeysIo is _HeldKeysIo) holds.add(atKeysIo);
    final outcome = buildAtClient(
            atSign: atSign,
            namespace: 'wavi',
            preference: preference ?? loopbackPreference(),
            lookUps: lookUps ?? loopbackLookUps(),
            secondaryAddressFinder: finder,
            atKeysIo: atKeysIo ?? noKeysFor(atSign),
            enrollmentId: enrollmentId,
            storage: storage)
        .then<Object>((client) => client, onError: (Object e) => e);
    outcomes.add(outcome);
    return outcome;
  }

  test(
      'Two builds of one principal at once, each on its own data store, leave one live client',
      () async {
    const atSign = '@alice';
    final storage = [
      _GatedStorage(atSign, held: true),
      _GatedStorage(atSign, held: true)
    ];
    final asked = [<String>[], <String>[]];
    final ended = [
      for (var i = 0; i < 2; i++)
        build(atSign, storage[i], lookUps: _recording(asked[i]))
    ];

    final first = await Future.any([
      for (var i = 0; i < 2; i++) storage[i].entered.future.then((_) => i)
    ]).timeout(_wait);
    final other = 1 - first;
    await Future.any<Object?>([ended[other], storage[other].entered.future])
        .timeout(_wait);

    expect(storage[other].entered.isCompleted, isFalse,
        reason: 'the other build opened its data store, so both builds '
            'passed every check with neither filed');
    expect(await ended[other], _refusal);
    expect(asked[other], isEmpty,
        reason: 'the refused build asked for no connection');

    storage[first].release.complete();
    final client = await ended[first].timeout(_wait);
    expect(client, isA<AtClient>());
    expect(asked[first], isNotEmpty,
        reason: 'the control: a build that goes on asks for its connections '
            'through the factory it was given');
    expect(AtClientImpl.atClientInstanceMap[atSign], same(client));
    expect(AtClientImpl.liveClientsFor(atSign), [same(client)]);
  });

  test('A build that fails gives up its claim', () async {
    const atSign = '@alice';

    expect(await build(atSign, _GatedStorage(atSign, fails: true)),
        isA<_OpenFailed>(),
        reason: 'the premise: the build threw while building');

    final client = await build(atSign, _GatedStorage(atSign)).timeout(_wait);
    expect(client, isA<AtClient>());
    expect((client as AtClient).isStopped, isFalse);
    expect(AtClientImpl.atClientInstanceMap[atSign], same(client));
  });

  test('A build never hands back a client another build made', () async {
    const atSign = '@alice';
    final storage = _GatedStorage(atSign, held: true);
    final first = build(atSign, storage);
    await storage.entered.future.timeout(_wait);

    final keys = _HeldKeysIo(noKeysFor(atSign), holds: (read, _) => read == 2);
    final second = build(atSign, storage, atKeysIo: keys);
    await keys.entered.future.timeout(_wait);
    expect(AtClientImpl.holdsLiveClientAs(atSign, null), isFalse,
        reason: 'the premise: nothing is filed while the second call reads '
            'its keys');

    storage.release.complete();
    final client = await first.timeout(_wait);
    expect(client, isA<AtClientImpl>());
    client as AtClientImpl;
    expect(AtClientImpl.atClientInstanceMap[atSign], same(client),
        reason: 'the premise: the first call filed its client while the '
            'second was still reading its keys');
    final notifications = client.notificationService;
    final sync = client.syncService;
    final enrollments = client.enrollmentService;

    keys.release.complete();

    expect(await second.timeout(_wait), _refusal,
        reason: 'buildAtClient\'s own check names the client "already live" '
            'and not "being built", so this refusal comes from the client '
            'the second call was about to be handed');
    expect(client.notificationService, same(notifications));
    expect(client.syncService, same(sync));
    expect(client.enrollmentService, same(enrollments));
    expect(client.isStopped, isFalse);
    expect(AtClientImpl.atClientInstanceMap[atSign], same(client));
  });

  test(
      'A build that retrofits to a new enrollment still holds off a second build',
      () async {
    const atSign = '@alice🛠';
    const legacyId = 'first-1';
    const newId = 'retro-2';
    final keys = InMemoryAtKeysIo.holding(atSign, _legacyKeys(legacyId));
    final retrofitting = _HeldKeysIo(keys,
        holds: (_, __) =>
            AtClientImpl.supersededInstanceKeys['$atSign|$legacyId'] ==
            '$atSign|$newId');

    final first = build(atSign, _GatedStorage(atSign),
        atKeysIo: retrofitting,
        lookUps: _retrofittingAtServers(newId),
        preference: _retrofittingPreference());
    await retrofitting.entered.future.timeout(_wait);
    expect((await keys.read(atSign)).enrollmentToAuthenticateAs(), newId,
        reason: 'the premise: the retrofit has filed the new enrollment');
    expect(AtClientImpl.holdsLiveClientAs(atSign, newId), isFalse,
        reason: 'the premise: the first call has not filed');

    final storage = _GatedStorage(atSign);
    final asked = <String>[];
    final second =
        build(atSign, storage, atKeysIo: keys, lookUps: _recording(asked));
    await Future.any<Object?>([second, storage.entered.future]).timeout(_wait);

    expect(storage.entered.isCompleted, isFalse,
        reason: 'the second call opened its data store, beside a build of '
            'the same enrollment');
    expect(await second, _refusal);
    expect(asked, isEmpty);

    retrofitting.release.complete();
    final client = await first.timeout(_wait);
    expect(client, isA<AtClient>());
    expect((client as AtClient).enrollmentId, newId);
    expect(AtClientImpl.atClientInstanceMap['$atSign|$newId'], same(client));

    await client.stop();
    final again = await build(atSign, _GatedStorage(atSign),
            atKeysIo: keys, preference: _retrofittingPreference())
        .timeout(_wait);
    expect(again, isA<AtClient>(),
        reason: 'the claim the retrofit took on $newId outlived the build '
            'that took it');
    expect((again as AtClient).enrollmentId, newId);
  });

  test(
      'A build that reads a retrofitted enrollment before its retrofit has claimed it is refused as it files',
      () async {
    const atSign = '@alice🛠';
    const legacyId = 'first-1';
    const newId = 'retro-2';
    final keys = InMemoryAtKeysIo.holding(atSign, _legacyKeys(legacyId));
    final retrofitting = _HeldKeysIo(keys,
        holds: (_, read) => read.enrollmentToAuthenticateAs() == newId);

    final firstStore = _GatedStorage(atSign);
    final building = build(atSign, firstStore,
        atKeysIo: retrofitting,
        lookUps: _retrofittingAtServers(newId),
        preference: _retrofittingPreference());
    await retrofitting.entered.future.timeout(_wait);
    expect(AtClientImpl.supersededInstanceKeys['$atSign|$legacyId'], isNull,
        reason: 'the premise: the first call has filed $newId in the keys and '
            'not yet claimed it, which it does as it records the supersession');
    expect(firstStore.isAttached, isTrue,
        reason: 'the control: the client the first call is building holds its '
            'data store');

    final second = await build(atSign, _GatedStorage(atSign),
            atKeysIo: keys, preference: _retrofittingPreference())
        .timeout(_wait);
    expect(second, isA<AtClient>(),
        reason: 'the premise: the second call read the keys and built');
    expect((second as AtClient).enrollmentId, newId,
        reason: 'the premise: it built as $newId');

    retrofitting.release.complete();
    final first = await building.timeout(_wait);

    final ended = [first, second];
    final filed = AtClientImpl.atClientInstanceMap['$atSign|$newId'];
    expect([
      for (final client in ended.whereType<AtClient>())
        if (!client.isStopped && !identical(client, filed)) client
    ], isEmpty,
        reason: 'an orphan: a running client for $atSign as $newId that the '
            'registry does not hold, so nothing can find or stop it by name');
    expect(ended.whereType<AtClient>(), [same(filed)]);
    expect(ended.where((e) => e is! AtClient), [_refusal]);
    expect((filed as AtClient).isStopped, isFalse);
    expect(firstStore.isAttached, isFalse,
        reason: 'the client the refused call built still holds its data store, '
            'so it was not stopped');
    expect(firstStore.closed, isTrue,
        reason: 'the refused call left open the data store its client was to '
            'close');
  });

  test('Two builds of one named enrollment at once leave one live client',
      () async {
    const atSign = '@alice';
    const enrollmentId = 'e1';
    final storage = [
      _GatedStorage(atSign, held: true),
      _GatedStorage(atSign, held: true)
    ];
    final ended = [
      for (var i = 0; i < 2; i++)
        build(atSign, storage[i], enrollmentId: enrollmentId)
    ];

    final first = await Future.any([
      for (var i = 0; i < 2; i++) storage[i].entered.future.then((_) => i)
    ]).timeout(_wait);
    final other = 1 - first;
    await Future.any<Object?>([ended[other], storage[other].entered.future])
        .timeout(_wait);

    expect(storage[other].entered.isCompleted, isFalse,
        reason: 'the other build opened its data store beside a build of the '
            'same enrollment');
    expect(
        await ended[other],
        _refusal.having((e) => e.message, 'message',
            contains('as enrollment "$enrollmentId" ')));

    storage[first].release.complete();
    final client = await ended[first].timeout(_wait);
    expect(client, isA<AtClient>());
    expect((client as AtClient).enrollmentId, enrollmentId);
    expect(AtClientImpl.atClientInstanceMap['$atSign|$enrollmentId'],
        same(client));
  });

  test(
      'A retrofit keeps its new enrollment claimed when a build that claimed it first fails',
      () async {
    const atSign = '@alice🛠';
    const legacyId = 'first-1';
    const newId = 'retro-2';
    final keys = InMemoryAtKeysIo.holding(atSign, _legacyKeys(legacyId));
    final readBack = _HeldKeysIo(keys,
        holds: (_, read) => read.enrollmentToAuthenticateAs() == newId);
    final claimed = _HeldKeysIo(readBack,
        holds: (_, __) =>
            AtClientImpl.supersededInstanceKeys['$atSign|$legacyId'] ==
            '$atSign|$newId');
    holds.add(readBack);

    final retrofitting = build(atSign, _GatedStorage(atSign),
        atKeysIo: claimed,
        lookUps: _retrofittingAtServers(newId),
        preference: _retrofittingPreference());
    await readBack.entered.future.timeout(_wait);
    expect(AtClientImpl.supersededInstanceKeys['$atSign|$legacyId'], isNull,
        reason: 'the premise: the retrofit has filed $newId in the keys and '
            'not yet claimed it');

    final failingStore = _GatedStorage(atSign, held: true, fails: true);
    final failing = build(atSign, failingStore,
        atKeysIo: keys, preference: _retrofittingPreference());
    await Future.any<Object?>([failing, failingStore.entered.future])
        .timeout(_wait);
    expect(failingStore.entered.isCompleted, isTrue,
        reason: 'the premise: a second call read $newId and claimed it '
            'before the retrofit did');

    readBack.release.complete();
    await claimed.entered.future.timeout(_wait);

    failingStore.release.complete();
    expect(await failing.timeout(_wait), isA<_OpenFailed>(),
        reason: 'the premise: the call that claimed $newId first has ended');

    final storage = _GatedStorage(atSign);
    final asked = <String>[];
    final third = build(atSign, storage,
        atKeysIo: keys,
        lookUps: _recording(asked),
        preference: _retrofittingPreference());
    await Future.any<Object?>([third, storage.entered.future]).timeout(_wait);

    expect(storage.entered.isCompleted, isFalse,
        reason: 'the third call opened its data store beside the retrofitting '
            'build of $newId');
    expect(await third, _refusal);
    expect(asked, isEmpty);

    claimed.release.complete();
    final client = await retrofitting.timeout(_wait);
    expect(client, isA<AtClient>());
    expect((client as AtClient).enrollmentId, newId);
    expect(AtClientImpl.atClientInstanceMap['$atSign|$newId'], same(client));
  });

  test(
      'A retrofit that ends first leaves its new enrollment claimed by a build that claimed it before',
      () async {
    const atSign = '@alice🛠';
    const legacyId = 'first-1';
    const newId = 'retro-2';
    final keys = InMemoryAtKeysIo.holding(atSign, _legacyKeys(legacyId));
    final readBack = _HeldKeysIo(keys,
        holds: (_, read) => read.enrollmentToAuthenticateAs() == newId);

    final retrofitting = build(atSign, _GatedStorage(atSign),
        atKeysIo: readBack,
        lookUps: _retrofittingAtServers(newId),
        preference: _retrofittingPreference());
    await readBack.entered.future.timeout(_wait);
    expect(AtClientImpl.supersededInstanceKeys['$atSign|$legacyId'], isNull,
        reason: 'the premise: the retrofit has filed $newId in the keys and '
            'not yet claimed it');

    final heldStore = _GatedStorage(atSign, held: true);
    final held = build(atSign, heldStore,
        atKeysIo: keys, preference: _retrofittingPreference());
    await Future.any<Object?>([held, heldStore.entered.future]).timeout(_wait);
    expect(heldStore.entered.isCompleted, isTrue,
        reason: 'the premise: a second call read $newId and claimed it '
            'before the retrofit did');

    readBack.release.complete();
    final retrofitted = await retrofitting.timeout(_wait);
    expect(retrofitted, isA<AtClient>(),
        reason: 'the premise: the retrofit filed first');
    await (retrofitted as AtClient).stop();
    expect(AtClientImpl.holdsLiveClientAs(atSign, newId), isFalse,
        reason: 'the premise: nothing is filed as $newId');

    final storage = _GatedStorage(atSign);
    final asked = <String>[];
    final third = build(atSign, storage,
        atKeysIo: keys,
        lookUps: _recording(asked),
        preference: _retrofittingPreference());
    await Future.any<Object?>([third, storage.entered.future]).timeout(_wait);

    expect(storage.entered.isCompleted, isFalse,
        reason: 'the third call opened its data store beside the second '
            'call\'s build of $newId');
    expect(await third, _refusal);
    expect(asked, isEmpty);

    heldStore.release.complete();
    final client = await held.timeout(_wait);
    expect(client, isA<AtClient>());
    expect((client as AtClient).enrollmentId, newId);
    expect(AtClientImpl.atClientInstanceMap['$atSign|$newId'], same(client));
  });

  test(
      'AtClientImpl.create is refused while a build of its principal runs, and hands back the client that build files',
      () async {
    const atSign = '@alice';
    final storage = _GatedStorage(atSign, held: true);
    final building = build(atSign, storage);
    await storage.entered.future.timeout(_wait);

    Future<AtClient> create() =>
        AtClientImpl.create(atSign, 'wavi', loopbackPreference(),
            atKeysIo: noKeysFor(atSign),
            lookUps: loopbackLookUps(),
            secondaryAddressFinder: finder,
            storage: storage);

    await expectLater(create(), throwsA(_refusal));

    storage.release.complete();
    final client = await building.timeout(_wait);
    expect(client, isA<AtClient>());
    expect(await create().timeout(_wait), same(client));
  });

  test('No barrel exports the build that refuses a live client', () {
    final hiding = RegExp(r'\bhide\b[^;]*\bcreateOwnedAtClient\b');
    final statements = [
      for (final barrel in Directory('lib').listSync().whereType<File>())
        if (barrel.path.endsWith('.dart'))
          for (final export in RegExp(r"export\s+'([^']+)'([^;]*);")
              .allMatches(barrel.readAsStringSync()))
            if (export.group(1)!.endsWith('/src/client/at_client_impl.dart'))
              (barrel: barrel.path, combinators: export.group(2)!)
    ];

    expect(statements, isNotEmpty,
        reason: 'the control: a barrel exports the file that declares '
            'createOwnedAtClient; run this from the at_client package root');
    for (final statement in statements) {
      expect(statement.combinators, matches(hiding),
          reason: '${statement.barrel} makes createOwnedAtClient public API');
    }
  });
}

/// A pre-retrofit keyfile for `@alice🛠`: rsa2048 in the flat fields,
/// enrolled as [enrollmentId].
AtKeys _legacyKeys(String enrollmentId) => AtKeys()
  // ignore: deprecated_member_use
  ..apkamPublicKey = AtBytes.fromString(demo.pkamPublicKeyMap['@alice🛠']!)
  // ignore: deprecated_member_use
  ..apkamPrivateKey = AtBytes.fromString(demo.pkamPrivateKeyMap['@alice🛠']!)
  // ignore: deprecated_member_use
  ..defaultEncryptionPublicKey =
      AtBytes.fromString(demo.encryptionPublicKeyMap['@alice🛠']!)
  // ignore: deprecated_member_use
  ..defaultEncryptionPrivateKey =
      AtBytes.fromString(demo.encryptionPrivateKeyMap['@alice🛠']!)
  // ignore: deprecated_member_use
  ..defaultSelfEncryptionKey = AtBytes.fromString(demo.aesKeyMap['@alice🛠']!)
  // ignore: deprecated_member_use
  ..enrollmentId = enrollmentId;

/// A loopback preference whose posture authenticates with ML-DSA-65, so a
/// client on [_legacyKeys] retrofits as it starts.
AtClientPreference _retrofittingPreference() => loopbackPreference(
    authenticationKeyAlgorithm: SigningAlgoType.mldsa65,
    dataSigningKeyAlgorithms: {SigningAlgoType.mldsa65});

/// Connections to a fresh [_retrofittingAtServer] each.
AtLookUpFactory _retrofittingAtServers(String newId) => (
        {required atSign,
        required rootDomain,
        required authenticator,
        secondaryAddressFinder}) =>
    _retrofittingAtServer(newId);

/// An atServer that approves a self-enrollment as [newId], answers
/// `enroll:fetch` with an approved record for the app `wavi` on `laptop`,
/// holds nothing to sync, authenticates every PKAM, and answers any other
/// command with nothing.
MockAtLookupImpl _retrofittingAtServer(String newId) {
  final lookUp = MockAtLookupImpl();
  AtAuthenticator? installed;
  when(() => lookUp.authenticator = any()).thenAnswer((invocation) {
    installed = invocation.positionalArguments.first as AtAuthenticator?;
    return null;
  });
  when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
      .thenAnswer((invocation) async {
    final command = invocation.positionalArguments.first as String;
    if (command.startsWith('enroll:list')) return 'data:[]';
    if (command.startsWith('enroll:fetch')) {
      return 'data:${jsonEncode({
            'appName': 'wavi',
            'deviceName': 'laptop',
            'namespace': {'wavi': 'rw'},
            'status': 'approved'
          })}';
    }
    if (command.startsWith('enroll:')) {
      return 'data:${jsonEncode({
            'enrollmentId': newId,
            'status': 'approved'
          })}';
    }
    return null;
  });
  when(() => lookUp.executeVerb(any())).thenAnswer((invocation) async {
    final builder = invocation.positionalArguments.first as VerbBuilder;
    if (builder is UpdateVerbBuilder || builder is DeleteVerbBuilder) {
      return 'data:1';
    }
    if (builder is StatsVerbBuilder) {
      return 'data:[{"id":"3","name":"lastCommitID","value":"-1"}]';
    }
    throw StateError('the mocked atServer has no answer for: '
        '${builder.buildCommand()}');
  });
  when(() => lookUp.pkamAuthenticate()).thenAnswer((_) async {
    if (installed != null) await installed!(_PkamAtServer());
    return true;
  });
  when(() => lookUp.close()).thenAnswer((_) async {});
  when(() => lookUp.stopNotifications()).thenAnswer((_) async {});
  when(() => lookUp.isConnectionAvailable()).thenReturn(false);
  return lookUp;
}
