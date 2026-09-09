@Tags(['pq'])
library;

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// The nskey data path driven through a real `AtClient` against a live atServer.
///
/// `put` and `get` are local-first and never reach the atServer, so the tests
/// that must prove what was stored sync first and then ask the atServer itself.
void main() {
  TestUtils.isolateStorage('nskey_data_path_live_test');
  late AtClientManager atClientManager;
  late String atSign;
  const namespace = 'wavi';

  /// Hoisted out of [setUpAll] so a test can make a namespace gain a key
  /// mid-life, which is what a recipient publishing looks like to the resolver.
  late InMemoryNskeyKeyRing ring;

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];

    final nskeyPair = await XWingKeyPair.generate();
    final appNsPair = await XWingKeyPair.generate();
    ring = InMemoryNskeyKeyRing()
      ..seedKeypair(atSign, namespace,
          publicKey: nskeyPair.publicKeyBytes,
          privateKey: nskeyPair.privateKeyBytes)
      // NOTE: multi-segment on purpose. A single-segment app namespace would
      // make the last-dot split land on it by luck, and the nested-namespace
      // group below would prove nothing.
      ..seedKeypair(atSign, 'app_1.$namespace',
          publicKey: appNsPair.publicKeyBytes,
          privateKey: appNsPair.privateKeyBytes);

    final preference = TestUtils.getPreference(atSign,
        posture: legacyPlusPqProviders)
      ..crypto = CryptoConfig.nskey(keyRing: ring);

    atClientManager = await TestUtils.initAtClient(
      atSign,
      namespace,
      preference: preference,
    posture: legacyPlusPqProviders);
  });

  test('a self value round-trips through the nskey data path', () async {
    final atClient = atClientManager.atClient;
    final key = AtKey()
      ..key = 'treaty'
      ..namespace = namespace
      ..sharedBy = atSign;
    const plaintext = 'the treaty text';

    expect(await atClient.put(key, plaintext), true);

    final read = await atClient.get(key);
    expect(read.value, plaintext, reason: 'round-trip must equal plaintext');

    final valueMeta = read.metadata?.appMetadata;
    expect(valueMeta?.providerId, symmetricAesGcmCryptoProviderId);
    final ckKid = valueMeta?.additional?['ckKid'];
    expect(ckKid, isNotNull);
    expect(valueMeta?.additional?['iv'], isNotNull);
    expect(valueMeta?.additional?.containsKey('sealedKey'), isFalse,
        reason: 'the CK is conveyed once, never inline');

    final conveyance = await atClient.get(AtKey()
      ..key = '$ckKid.__ck'
      ..namespace = namespace
      ..sharedBy = atSign);
    final conveyanceMeta = conveyance.metadata?.appMetadata;
    expect(conveyanceMeta?.providerId, nskeyCryptoProviderId,
        reason: 'the conveyance routes to the CK-conveyance provider, and its '
            'id names the algorithms a reader needs');
    expect(conveyanceMeta?.additional?['ckKid'], ckKid);
    expect(conveyanceMeta?.additional?['nskeyKid'], isNotNull,
        reason: 'a conveyance names the nskey generation it was sealed to');
    expect(
        conveyanceMeta?.additional?['recipientKind'], NskeyRecipientKind.nskey);
  });

  test('a second write reuses the content key rather than cutting a new one',
      () async {
    final atClient = atClientManager.atClient;
    AtKey named(String k) => AtKey()
      ..key = k
      ..namespace = namespace
      ..sharedBy = atSign;

    expect(await atClient.put(named('first'), 'one'), true);
    final firstCk = (await atClient.get(named('first')))
        .metadata
        ?.appMetadata
        ?.additional?['ckKid'];

    expect(await atClient.put(named('second'), 'two'), true);
    final secondCk = (await atClient.get(named('second')))
        .metadata
        ?.appMetadata
        ?.additional?['ckKid'];

    expect(secondCk, firstCk,
        reason: 'a CK is long-lived per destination — re-cutting per write '
            'would multiply conveyance records for no benefit');
    expect((await atClient.get(named('second'))).value, 'two');
  });

  test('the crypto routing survives the sync push to the atServer', () async {
    final atClient = atClientManager.atClient;
    final key = AtKey()
      ..key = 'pushed'
      ..namespace = namespace
      ..sharedBy = atSign;

    expect(await atClient.put(key, 'the treaty text'), true);
    final localMeta = (await atClient.get(key)).metadata?.appMetadata;
    final ckKid = localMeta?.additional?['ckKid'];
    expect(ckKid, isNotNull);

    await FunctionalTestSyncService.getInstance()
        .syncData(syncSvc: atClient.syncService);

    Future<String> llookupAll(AtKey k) async =>
        (await atClient.getRemoteSecondary()!.executeCommand(
              'llookup:all:${k.toString()}\n',
              auth: true,
            )) ??
        '';

    final stored = await llookupAll(key);
    expect(stored, contains(AtConstants.appMetadata),
        reason: 'the atServer must have stored appMetadata — without it a '
            'cross-atSign lookup returns a null providerId and the reader '
            'falls back to legacy, hunting a shared_key that was never made');
    expect(stored, contains(symmetricAesGcmCryptoProviderId),
        reason: 'and the stored routing must name the data provider');
    expect(stored, contains(ckKid),
        reason: 'the stored value must still cite the content key it was '
            'encrypted under');

    final storedConveyance = await llookupAll(AtKey()
      ..key = '$ckKid.__ck'
      ..namespace = namespace
      ..sharedBy = atSign);
    expect(storedConveyance, contains(nskeyCryptoProviderId),
        reason: 'the conveyance must reach the atServer carrying its own '
            'provider id, not just the value that cites it');
  });

  test('binary round-trips byte-exact', () async {
    final atClient = atClientManager.atClient;
    final key = AtKey()
      ..key = 'blob'
      ..namespace = namespace
      ..sharedBy = atSign;
    // NOTE: the length must not fall on a 15-bit boundary.
    final bytes = [for (var i = 0; i < 256; i++) i, 0x00, 0xff, 0x7f];

    expect(await atClient.put(key, bytes), true);
    final read = await atClient.get(key);
    expect(read.value, bytes,
        reason: 'isBinary must survive the round-trip byte for byte');
  });

  /// A multi-segment namespace, driven through the real pipeline against a live
  /// atServer.
  ///
  /// `AtKey.fromString` splits at the last dot, so a multi-segment namespace
  /// cannot be recovered from the wire string and each record has to state its
  /// own.
  group('nested namespace', () {
    const appNs = 'app_1.wavi';
    const composed = '__rr.item123.app_1.wavi';

    test('a value under a composed namespace round-trips via the app key',
        () async {
      final atClient = atClientManager.atClient;
      final key = AtKey()
        ..key = 'memo'
        ..namespace = composed
        ..sharedBy = atSign;

      expect(await atClient.put(key, 'the treaty text'), true);

      final read = await atClient.get(key);
      expect(read.value, 'the treaty text');
      final meta = read.metadata?.appMetadata?.additional;
      expect(meta?['ns'], composed,
          reason: 'the value states its own namespace, which the last-dot '
              'split would have reported as "wavi"');
      expect(meta?['ckNs'], appNs,
          reason: 'and the CK lives at the namespace the walk found');
    });

    test('a second item shares the content key', () async {
      final atClient = atClientManager.atClient;
      AtKey item(String id) => AtKey()
        ..key = 'memo'
        ..namespace = '__rr.$id.app_1.wavi'
        ..sharedBy = atSign;

      expect(await atClient.put(item('itemA'), 'one'), true);
      expect(await atClient.put(item('itemB'), 'two'), true);

      final a = (await atClient.get(item('itemA'))).metadata?.appMetadata;
      final b = (await atClient.get(item('itemB'))).metadata?.appMetadata;
      expect(a?.additional?['ckKid'], b?.additional?['ckKid'],
          reason: 'a key per item would mean a conveyance record per item, '
              'which is what walking up exists to avoid');
    });

    test('binary round-trips byte-exact under a composed namespace', () async {
      final atClient = atClientManager.atClient;
      final key = AtKey()
        ..key = 'blob'
        ..namespace = composed
        ..sharedBy = atSign;
      final bytes = [for (var i = 0; i < 256; i++) i, 0x00, 0xff, 0x7f];

      expect(await atClient.put(key, bytes), true);
      expect((await atClient.get(key)).value, bytes);
    });

    test('the namespace fields survive the sync push to the atServer',
        () async {
      final atClient = atClientManager.atClient;
      final key = AtKey()
        ..key = 'synced_memo'
        ..namespace = composed
        ..sharedBy = atSign;
      expect(await atClient.put(key, 'for the server'), true);
      await FunctionalTestSyncService.getInstance()
          .syncData(syncSvc: atClient.syncService);

      final stored = (await atClient.getRemoteSecondary()!.executeCommand(
                'llookup:all:${key.toString()}\n',
                auth: true,
              )) ??
          '';
      expect(stored, contains(composed),
          reason: 'the stored record must carry its own namespace, not the '
              'last-dot guess');
      expect(stored, contains(appNs),
          reason: 'and the namespace its content key lives at');
    });
  });

  /// Cold start, driven through the real put pipeline.
  ///
  /// A namespace with no nskey has no post-quantum target, and no fallback that
  /// stays post-quantum, so the write must refuse in terms the caller can act
  /// on rather than raising a generic encryption error.
  group('cold start', () {
    AtKey unmintedNamespaceKey(String name) => AtKey()
      ..key = name
      ..namespace = 'never_used_ns'
      ..sharedBy = atSign;

    test('a write to a namespace with no nskey fails, saying which', () async {
      await expectLater(
        atClientManager.atClient.put(unmintedNamespaceKey('memo'), 'for me'),
        throwsA(isA<AtClientException>().having((e) => e.message, 'message',
            allOf(contains('never_used_ns'), contains(atSign)))),
        reason: 'the app has to be able to name what is missing; a bare '
            'encryption error tells it nothing it can act on',
      );
    });

    test('the readiness query answers the same question first', () async {
      final runtime = CryptoRuntime(atClientManager.atClient);

      expect(await runtime.isReadyFor(atSign, 'never_used_ns'), isFalse);
      expect(await runtime.isReadyFor(atSign, namespace), isTrue,
          reason: 'the namespace this suite minted for is reachable');
    });

    test('with the escape hatch opened, the write goes out under legacy',
        () async {
      final atClient = atClientManager.atClient;
      atClient.getPreferences()!.allowLegacyCryptoFallback = true;
      addTearDown(
          () => atClient.getPreferences()!.allowLegacyCryptoFallback = false);

      final key = unmintedNamespaceKey('fallback_memo');
      expect(await atClient.put(key, 'for me'), true);

      final read = await atClient.get(key);
      expect(read.value, 'for me');
      expect(read.metadata?.appMetadata?.providerId, legacyCryptoProviderId,
          reason: 'the fallback is legacy and says so on the record — a '
              'downgrade nobody can see afterwards is the thing being guarded '
              'against');
    });

    test(
        'a namespace that gains a key takes over, and what the fallback wrote '
        'stays legacy', () async {
      // UC-A3.3, second and third arms. Self data, no peer involved.
      final atClient = atClientManager.atClient;
      final ns = 'latecomer${DateTime.now().microsecondsSinceEpoch}';
      AtKey k(String name) => AtKey()
        ..key = name
        ..namespace = ns
        ..sharedBy = atSign;

      atClient.getPreferences()!.allowLegacyCryptoFallback = true;
      addTearDown(
          () => atClient.getPreferences()!.allowLegacyCryptoFallback = false);

      expect(await atClient.put(k('early'), 'before the key existed'), isTrue);
      expect((await atClient.get(k('early'))).metadata?.appMetadata?.providerId,
          legacyCryptoProviderId,
          reason: 'the premise: with no nskey for this namespace and the '
              'escape hatch open, the write goes out legacy');

      // NOTE: this control must be able to stay green while the assertion
      // below goes red — that is what attributes the flip to the key
      // appearing, not to this being the second write to the namespace.
      expect(await atClient.put(k('control'), 'also before'), isTrue);
      expect(
          (await atClient.get(k('control'))).metadata?.appMetadata?.providerId,
          legacyCryptoProviderId,
          reason: 'control: writing again changes nothing on its own');

      final pair = await XWingKeyPair.generate();
      ring.seedKeypair(atSign, ns,
          publicKey: pair.publicKeyBytes, privateKey: pair.privateKeyBytes);

      expect(await atClient.put(k('later'), 'after the key existed'), isTrue);
      expect((await atClient.get(k('later'))).metadata?.appMetadata?.providerId,
          symmetricAesGcmCryptoProviderId,
          reason: 'once the namespace has an nskey, every SUBSEQUENT write '
              'uses it — the app does not opt back in and there is no flag to '
              'flip. A build that answered from a remembered miss would still '
              'be writing legacy here, with the control above green');

      final early = await atClient.get(k('early'));
      expect(early.value, 'before the key existed');
      expect(early.metadata?.appMetadata?.providerId, legacyCryptoProviderId,
          reason: 'and what the fallback already wrote stays legacy and stays '
              'readable. Re-encrypting it is an explicit migration, never a '
              'side effect of a later put to the same namespace');
    });

    test('the fallback does not leak into the next write', () async {
      final atClient = atClientManager.atClient;
      atClient.getPreferences()!.allowLegacyCryptoFallback = true;
      await atClient.put(unmintedNamespaceKey('leak_check'), 'for me');
      atClient.getPreferences()!.allowLegacyCryptoFallback = false;

      final key = AtKey()
        ..key = 'still_pq'
        ..namespace = namespace
        ..sharedBy = atSign;
      expect(await atClient.put(key, 'and this one is not'), true);

      expect((await atClient.get(key)).metadata?.appMetadata?.providerId,
          symmetricAesGcmCryptoProviderId,
          reason: 'one write falling back must not pin the client to legacy — '
              'the check runs per write, which is what makes the fallback '
              'forward-only');
    });
  });
}
