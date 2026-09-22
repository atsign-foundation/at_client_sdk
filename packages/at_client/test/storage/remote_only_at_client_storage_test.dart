// Unit tests for RemoteOnlyAtClientStorage — the AtClientStorage that composes
// stage2a's NoopSyncQueueStore and stage2b's RemoteWriteThroughKeyStore into
// the concrete Mode E backend `implementation-plan.md` names as not yet
// written. Closes X-R1 (constructs with no local database) and X-R2 (proves
// composition wiring; true cross-client interop against a live atServer is a
// functional test, not this suite). See plans/wasm/spike/pb3-stage2c-plan.md.

import 'package:at_client/at_client.dart';
import 'package:at_client/remote_only.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';

/// A throwaway [AtClient] identity, only ever used to attach/detach storage
/// directly in these tests — never handed to `buildAtClient`.
class _FakeClient extends Mock implements AtClient {
  _FakeClient(this._atSign);
  final String _atSign;
  @override
  String? getCurrentAtSign() => _atSign;
  @override
  String? get enrollmentId => null;
}

/// Never touches the network — construction-only tests, like
/// `at_client_mode_e_construction_test.dart`'s own `_recording`.
AtLookupMuxable _recording({
  required String atSign,
  required AtRootDomain rootDomain,
  required AtAuthenticator? authenticator,
  SecondaryAddressFinder? secondaryAddressFinder,
  Map<String, dynamic> clientConfig = const {},
}) {
  final lookUp = MockAtLookupImpl();
  when(() => lookUp.isConnectionAvailable()).thenReturn(false);
  when(() => lookUp.close()).thenAnswer((_) async {});
  when(() => lookUp.stopNotifications()).thenAnswer((_) async {});
  when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
      .thenAnswer((_) async => 'data:null');
  return lookUp;
}

void main() {
  setUpAll(() => registerFallbackValue(LLookupVerbBuilder()));

  setUp(() => AtClientManager.getInstance().reset());

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientManager.getInstance().reset();
  });

  late MockRemoteSecondary remoteSecondary;

  setUp(() {
    remoteSecondary = MockRemoteSecondary();
  });

  test(
      'attaches with no local database, and reads/writes flow through the '
      'injected RemoteSecondary (X-R1, X-R2 composition wiring)', () async {
    const atSign = '@remoteonly1';
    final storage =
        RemoteOnlyAtClientStorage(atSign: atSign, remoteSecondary: remoteSecondary);
    final owner = _FakeClient(atSign);

    when(() => remoteSecondary.executeCommand(any(), auth: true))
        .thenAnswer((_) async => 'data:1');
    when(() => remoteSecondary.executeVerb(any())).thenAnswer(
        (_) async => 'data:{"data":"v","metaData":{"createdAt":'
            '"${DateTime.now().toUtc()}","updatedAt":"${DateTime.now().toUtc()}"}}');

    await storage.attach(owner);
    await storage.keyStore.put('k$atSign', AtData()..data = 'v');
    final result = await storage.keyStore.get('k$atSign');

    expect(result?.data, 'v',
        reason: 'the keyStore attached is the RemoteWriteThroughKeyStore '
            'proxying to the mocked RemoteSecondary, not a local fallback');
    verify(() => remoteSecondary.executeCommand(any(), auth: true)).called(1);
    verify(() => remoteSecondary.executeVerb(any())).called(1);

    await storage.detach(owner);
    await storage.close();
  });

  test('syncQueue is a NoopSyncQueueStore-backed AtSyncQueue', () async {
    const atSign = '@remoteonly2';
    final storage =
        RemoteOnlyAtClientStorage(atSign: atSign, remoteSecondary: remoteSecondary);
    final owner = _FakeClient(atSign);

    await storage.attach(owner);
    expect(storage.syncQueue.isOpen, isTrue);
    expect(storage.syncQueue.isEmpty, isTrue,
        reason: 'a noop store never persists anything to replay');

    await storage.detach(owner);
    await storage.close();
  });

  test('location is per atSign — one path per atSign, per D-13', () async {
    final a = RemoteOnlyAtClientStorage(
        atSign: '@remoteonly3a', remoteSecondary: remoteSecondary);
    final b = RemoteOnlyAtClientStorage(
        atSign: '@remoteonly3b', remoteSecondary: remoteSecondary);
    final ownerA = _FakeClient('@remoteonly3a');
    final ownerB = _FakeClient('@remoteonly3b');

    await a.attach(ownerA);
    await b.attach(ownerB);
    expect(a.location, isNot(b.location));

    final secondForA = RemoteOnlyAtClientStorage(
        atSign: '@remoteonly3a', remoteSecondary: remoteSecondary);
    await expectLater(
      () => secondForA.attach(_FakeClient('@remoteonly3a')),
      throwsA(isA<StateError>()),
      reason: 'two storages over one atSign are one store, per D-13 — the '
          'second is refused rather than sharing silently',
    );

    await a.detach(ownerA);
    await b.detach(ownerB);
    await a.close();
    await b.close();
  });

  test('clearData throws UnsupportedError — clearing a live atServer is out '
      'of scope for this slice', () async {
    const atSign = '@remoteonly4';
    final storage =
        RemoteOnlyAtClientStorage(atSign: atSign, remoteSecondary: remoteSecondary);
    final owner = _FakeClient(atSign);
    await storage.attach(owner);

    await expectLater(() => storage.clear(), throwsUnsupportedError);

    await storage.detach(owner);
    await storage.close();
  });

  test('closeBackend does not close the injected RemoteSecondary — the '
      'storage borrows it, it does not own it', () async {
    const atSign = '@remoteonly5';
    final storage =
        RemoteOnlyAtClientStorage(atSign: atSign, remoteSecondary: remoteSecondary);
    final owner = _FakeClient(atSign);

    await storage.attach(owner);
    await storage.detach(owner);
    await storage.close();

    verifyNever(() => remoteSecondary.closeConnection());
  });

  test(
      'a RemoteOnlyAtClientStorage constructs via buildAtClient, matching '
      'InMemoryAtClientStorage\'s Mode E construction shape', () async {
    const atSign = '@remoteonly6';
    when(() => remoteSecondary.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((_) async => 'data:1');
    // No key material on a fresh atServer — the real llookup-miss shape
    // _createAtChops's degrade-gracefully path is built to catch.
    when(() => remoteSecondary.executeVerb(any()))
        .thenThrow(KeyNotFoundException('no key material for $atSign'));

    final client = await buildAtClient(
        atSign: atSign,
        namespace: 'wavi',
        preference: AtClientPreference()
          ..isLocalStoreRequired = false
          ..namespace = 'wavi'
          ..monitorAutoStart = false,
        storage: RemoteOnlyAtClientStorage(
            atSign: atSign, remoteSecondary: remoteSecondary),
        lookUps: _recording) as AtClientImpl;

    expect(client.localSecondary, isNotNull,
        reason: 'B1/B2 (stage1) make this Mode E shape constructible; stage2c '
            'supplies the concrete non-Hive storage that fills it');

    await client.stop();
  });
}
