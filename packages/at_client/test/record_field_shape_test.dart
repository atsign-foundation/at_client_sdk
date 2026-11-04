import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show requireRecordAtSign, requireRecordKid, requireRecordNamespace;
import 'package:test/test.dart';

import 'test_utils/fake_at_server.dart';
import 'test_utils/no_keys.dart';
import 'test_utils/transport.dart';

/// A namespace, key id or atSign that a record's `appMetadata` names is used
/// only when an atKey can carry it.
void main() {
  Matcher refusedNaming(String field) => throwsA(isA<AtDecryptionException>()
      .having((e) => e.message, 'message', contains('as its $field'))
      .having((e) => e.message, 'message', isNot(contains('\n'))));

  group('A field a record names', () {
    test('is used when an atKey can carry it', () {
      for (final namespace in ['wavi', 'app_1.my_apps', 'my-app.wavi']) {
        expect(requireRecordNamespace(namespace, 'ns'), namespace);
      }
      for (final kid in ['0123456789abcdef', 'kid1']) {
        expect(requireRecordKid(kid, 'nskeyKid'), kid);
      }
      for (final atSign in ['@alice', '@alice🛠']) {
        expect(requireRecordAtSign(atSign, 'destination'), atSign);
      }
    });

    test(
        'is refused when it holds a newline, a colon, an atSign or a space, '
        'or is empty, and the refusal quotes it on one line', () {
      for (final namespace in [
        'app\n',
        'app\nx',
        'app:x',
        'app@bob',
        'app x',
        'my-app',
        '',
      ]) {
        expect(
            () => requireRecordNamespace(namespace, 'ns'), refusedNaming('ns'),
            reason: 'namespace "$namespace"');
      }
      for (final kid in ['kid1\n', 'kid.1', 'kid:1', '']) {
        expect(
            () => requireRecordKid(kid, 'nskeyKid'), refusedNaming('nskeyKid'),
            reason: 'kid "$kid"');
      }
      for (final atSign in ['@bob\n', 'bob', '@b ob', '@']) {
        expect(() => requireRecordAtSign(atSign, 'destination'),
            refusedNaming('destination'),
            reason: 'atSign "$atSign"');
      }
    });
  });

  group('Given a client reading under the pqReady posture', () {
    late FakeAtServer server;
    late AtClientImpl client;

    /// The generation this client's own advertisement for `app` names.
    late String kid;

    List<String> sentSince(int before) =>
        server.sockets.expand((s) => s.written).skip(before).toList();

    int sentSoFar() => server.sockets.expand((s) => s.written).length;

    Future<String> read(AtKey atKey) =>
        CryptoRuntime(client).decryptForGet(atKey, 'AAAA').then((v) => '$v');

    AtKey shared(String providerId, Map<String, dynamic> additional) =>
        AtKey.fromString('@alice:item.app@bob')
          ..metadata.appMetadata =
              AppMetadata(providerId: providerId, additional: additional);

    AtKey nskeyRecord({String ns = 'app', String? nskeyKid}) =>
        shared(nskeyCryptoProviderId, {
          'recipientKind': NskeyRecipientKind.nskey,
          'ckKid': 'ck1',
          'nskeyKid': nskeyKid ?? kid,
          'ns': ns,
        });

    AtKey siblingCopy({String destination = '@bob', String ckNs = 'app'}) =>
        AtKey.fromString('ck1.__ck.app@alice')
          ..metadata.appMetadata =
              AppMetadata(providerId: nskeyCryptoProviderId, additional: {
            'recipientKind': NskeyRecipientKind.nskey,
            'ckKid': 'ck1',
            'nskeyKid': kid,
            'ns': 'app',
            'destination': destination,
            'ckNs': ckNs,
          });

    AtKey sharedValue({required String ckKid, String ckNs = 'app'}) => shared(
        symmetricAesGcmCryptoProviderId,
        {'ckKid': ckKid, 'iv': 'AAAAAAAAAAAAAAAA', 'ckNs': ckNs});

    int asked() => client.pqBootstrap!.ring.namespacesAskedRecently;

    setUp(() async {
      server = FakeAtServer(atSign: '@alice');
      client = await AtClientImpl.create(
          '@alice',
          'wavi',
          AtClientPreference(posture: PqPosture.pqReady)
            ..monitorAutoStart = false,
          secondaryAddressFinder: defaultAtDirectory,
          atKeysIo: noKeysFor('@alice'),
          lookUps: server.lookUps,
          storage: InMemoryAtClientStorage(
              atSign: '@alice', closedByClient: true)) as AtClientImpl;
      await client.pqBootstrap!.startupComplete;
      // NOTE: the fake accepts the client's credential, as an atServer accepts
      // the enrollment's own PKAM, so an authenticated command reaches it.
      client.getRemoteSecondary()!.atLookUp.authenticator = (_) async => true;
      final kem = SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing)!;
      final advertised = NskeyAdvertisement.single(
          publicKey: (await kem.keyPairFromSeed(kem.newSeed())).publicKey,
          alg: SecretSharingAlgos.xWing);
      kid = advertised.nskeyKid;
      // NOTE: under the refused spelling too, so only the refusal keeps a
      // refused record from the ask.
      for (final ns in ['app', 'app\n']) {
        client.pqBootstrap!.ring.rememberOwn('@alice', ns, advertised);
      }
    });

    tearDown(() => client.stop());

    test(
        'when a shared nskey record names a namespace ending in a newline, '
        'then the read is refused and nothing is sent', () async {
      final before = sentSoFar();

      await expectLater(
          read(nskeyRecord(ns: 'app\n')), refusedNaming('namespace'));
      expect(asked(), 0,
          reason: 'a refused record must not reach the ask, which names its '
              'namespace to the atServer');

      await expectLater(read(nskeyRecord()),
          throwsA(isA<NskeyPrivateUnavailableException>()));
      expect(asked(), 1,
          reason: 'the premise: a record this client cannot open asks its '
              'other enrollments');
      await server.waitUntil(
          () => sentSince(before).any((c) => c.startsWith('enroll:listns')),
          what: 'the ask for the readable record');
      expect(sentSince(before).where((c) => c.startsWith('enroll:listns')),
          ['enroll:listns:app\n']);
    });

    test(
        'when a shared nskey record names a generation holding a newline, '
        'then the read is refused before anything is asked', () async {
      await expectLater(
          read(nskeyRecord(nskeyKid: '$kid\n')), refusedNaming('nskeyKid'));
      expect(asked(), 0);
    });

    test(
        'when an own sibling copy names a recipient or a namespace no atKey '
        'can carry, then the read is refused before anything is asked',
        () async {
      await expectLater(read(siblingCopy(destination: '@bob\n')),
          refusedNaming('destination'));
      await expectLater(
          read(siblingCopy(ckNs: 'app\n')), refusedNaming('ckNs'));
      expect(asked(), 0);
    });

    test(
        'when a shared value names a content key id ending in a newline, then '
        'the read is refused and nothing is sent', () async {
      final before = sentSoFar();

      await expectLater(read(sharedValue(ckKid: '0123456789abcdef\n')),
          refusedNaming('ckKid'));
      expect(sentSince(before).where((c) => c.contains('.__ck.')), isEmpty);

      await expectLater(read(sharedValue(ckKid: '0123456789abcdef')),
          throwsA(isA<ContentKeyUnavailableException>()));
      expect(sentSince(before),
          contains('lookup:all:0123456789abcdef.__ck.app@bob\n'),
          reason: 'the premise: a value whose content key is not held reads '
              'its conveyance from the atServer');
    });

    test(
        'when a shared value names a content key namespace ending in a '
        'newline, then the read is refused and nothing is sent', () async {
      final before = sentSoFar();

      await expectLater(
          read(sharedValue(ckKid: '0123456789abcdef', ckNs: 'app\n')),
          refusedNaming('ckNs'));
      expect(sentSince(before).where((c) => c.contains('.__ck.')), isEmpty);

      await expectLater(read(sharedValue(ckKid: '0123456789abcdef')),
          throwsA(isA<ContentKeyUnavailableException>()));
      expect(sentSince(before),
          contains('lookup:all:0123456789abcdef.__ck.app@bob\n'));
    });

    test(
        'when a shared value names a content key id ending in a newline, then '
        'its scheme leaves the algorithm unknown and nothing is sent',
        () async {
      final before = sentSoFar();

      final scheme =
          await client.schemeOf(sharedValue(ckKid: '0123456789abcdef\n'));
      expect(scheme.providerId, symmetricAesGcmCryptoProviderId);
      expect(scheme.keyAlgorithm, isNull);
      expect(sentSince(before).where((c) => c.contains('.__ck.')), isEmpty);

      await client.schemeOf(sharedValue(ckKid: '0123456789abcdef'));
      expect(
          sentSince(before)
              .where((c) => c.contains('0123456789abcdef.__ck.app@bob')),
          isNotEmpty,
          reason: 'the premise: a conveyance not held locally has its metadata '
              'read from the atServer');
    });
  });
}
