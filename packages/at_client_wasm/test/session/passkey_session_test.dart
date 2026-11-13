// ignore_for_file: deprecated_member_use
// The fixtures build legacy flat-field keyfiles on purpose.
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_wasm/at_client_wasm.dart';
import 'package:at_client_wasm/src/keys/passkey_record.dart';
import 'package:at_client_wasm/src/keys/passkey_record_keys.dart';
import 'package:at_client_wasm/src/keys/unlock_secret.dart';
import 'package:at_client_wasm/src/session/enrollment_gateway.dart'
    show apkamKeyPairFromSeed;
import 'package:at_client_wasm/src/session/passkey_custody.dart';
import 'package:at_client_wasm/src/session/passkey_session.dart';
import 'package:test/test.dart';

import 'custody_fakes.dart';
import 'wire_fakes.dart';

const _atSign = '@alice';
const _app = 'wavi';
const _cram = 'cram-secret';

/// ML-DSA-65 and classical @keys as an enrollment's document holds them: the
/// signing material is filed, no APKAM private key is.
Map<String, dynamic> _documentKeys() {
  final keys = AtKeys(atsign: Atsign(_atSign))
    ..defaultEncryptionPublicKey =
        AtBytes.fromString(base64Encode(utf8.encode('encryptionPublic')))
    ..defaultEncryptionPrivateKey =
        AtBytes.fromString(base64Encode(utf8.encode('encryptionPrivate')))
    ..defaultSelfEncryptionKey =
        AtBytes.fromString(base64Encode(utf8.encode('selfEncryption')))
    ..fileSigningMaterial(
        enrollmentId: 'eid1',
        algorithm: CryptographicMaterialAlgorithm.mlDsa65,
        publicKey: base64Encode(utf8.encode('mlDsaPublic')),
        privateKey: base64Encode(utf8.encode('mlDsaPrivate')));
  return Map<String, dynamic>.of(keys.toJson());
}

void main() {
  final finder = FixedSecondaryAddressFinder('atserver.test', 1);
  late Wire wire;
  late FakeServer server;
  late FakeGateway gateway;
  late FakeAuthenticator authenticator;
  late FakeHints hints;
  late FakeSetupLock setupLock;

  PasskeyCustody custody({FakeHints? withHints}) => PasskeyCustody(
      kek: PasskeyKek(authenticator),
      pointerReader: server,
      gateway: gateway,
      credentials: withHints ?? hints,
      enrollmentIds: withHints ?? hints,
      setupLock: setupLock);

  SessionTransport transport() => (lookUps: wire.lookUps, finder: finder);

  Future<AtClient> onboard() => onboardSession(custody(),
      atSign: _atSign, cram: _cram, app: _app, transport: transport());

  Future<AtClient> login({FakeHints? withHints, String atSign = _atSign}) =>
      loginSession(custody(withHints: withHints ?? hints),
          atSign: atSign, app: _app, transport: transport());

  /// A device that has nothing but its passkey, after a first setup.
  Future<FakeHints> enrolledElsewhere() async {
    await custody().onboard(atSign: _atSign, cram: _cram);
    return FakeHints();
  }

  setUp(() {
    wire = Wire();
    server = FakeServer()..keys = _documentKeys();
    server.publishes = (_) => true;
    gateway = FakeGateway(server);
    authenticator = FakeAuthenticator();
    hints = FakeHints();
    setupLock = FakeSetupLock();
  });

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    AtClientManager.getInstance().reset();
  });

  group('onboardSession', () {
    test('activates with the derived seed and the cram', () async {
      final prf = Uint8List.fromList(List.generate(32, (i) => i));
      final keys = await RecordKeys.derive(PrfSecret(prf), _atSign);

      await onboard();

      expect(gateway.activated.single.atSign, _atSign);
      expect(gateway.activated.single.cram, _cram);
      expect(gateway.activated.single.authSeed, keys.authSeed);
      expect(gateway.enrolled, isEmpty);
    });

    test('returns a client that has run PKAM', () async {
      final client = await onboard();

      expect(wire.pkams, greaterThan(0));
      expect(client.connection.current.isOnline, isTrue);
    });

    test('writes the document, then the pointer', () async {
      await onboard();

      expect(server.log.map((l) => l.split(':').first),
          ['put-document', 'put-pointer']);
    });

    test('the APKAM private key reaches no storage', () async {
      await onboard();
      final prf = Uint8List.fromList(List.generate(32, (i) => i));
      final keys = await RecordKeys.derive(PrfSecret(prf), _atSign);
      final pair = await apkamKeyPairFromSeed(keys.authSeed);

      final document = await PasskeyRecordCodec.open(
          keys.kek, PasskeyRecordType.atkeys, server.documents['eid1']!);
      final stored = [
        jsonEncode(document),
        ...server.documents.values,
        ...server.pointers.values,
        ...hints.ids.values,
        ...hints.credentials.values.map((v) => v.join(',')),
      ];
      expect(stored.where((s) => s.contains(pair.privateKey)), isEmpty);
      expect(document, isNot(contains('aesPkamPrivateKey')));
    });

    test('holds the setup lock during activation only', () async {
      Set<String>? heldDuring;
      gateway.onActivate = () => heldDuring = {...setupLock.held};

      await onboard();

      expect(heldDuring, {'at_client_wasm:setup:@alice'});
      expect(setupLock.held, isEmpty);
    });

    test('closes the custody session', () async {
      await onboard();

      expect(gateway.lastSession!.closed, isTrue);
    });
  });

  group('loginSession', () {
    test('opens with ML-DSA-65 material the document holds', () async {
      final device = await enrolledElsewhere();

      final client = await login(withHints: device);

      expect(wire.pkams, greaterThan(0));
      expect(client.connection.current.isOnline, isTrue);
      expect(AtClientImpl.holdsLiveClient(_atSign), isTrue);
    });

    test('portalSession still refuses caller-supplied ML-DSA material',
        () async {
      final keys = AtKeys(atsign: Atsign(_atSign))
        ..fileSigningMaterial(
            enrollmentId: 'eid1',
            algorithm: CryptographicMaterialAlgorithm.mlDsa65,
            publicKey: base64Encode(utf8.encode('p')),
            privateKey: base64Encode(utf8.encode('s')))
        ..enrollmentId = 'eid1';
      expect(keys.signingKeysFor('eid1').single.algorithm,
          SigningAlgoType.mldsa65);

      await expectLater(
          portalSession(
              atSign: _atSign, app: _app, keys: keys, transport: transport()),
          throwsA(isA<UnsupportedKeyMaterialException>()));
    });

    test('takes no setup lock', () async {
      final device = await enrolledElsewhere();
      setupLock.names.clear();

      await login(withHints: device);

      expect(setupLock.names, isEmpty);
    });

    test('an atSign with no enrollment is a typed error', () async {
      final device = await enrolledElsewhere();

      await expectLater(
          login(withHints: device, atSign: '@nobody'),
          throwsA(isA<PasskeyLostException>()
              .having((e) => e.atSign, 'atSign', '@nobody')));

      expect(wire.dials, 0);
    });

    test('a missing pointer is a typed error', () async {
      final device = await enrolledElsewhere();
      server.pointers.clear();

      await expectLater(
          login(withHints: device), throwsA(isA<PasskeyLostException>()));
      expect(wire.dials, 0);
    });

    test('a PKAM refusal is a typed error', () async {
      final device = await enrolledElsewhere();
      server.revoked.add('eid1');

      await expectLater(
          login(withHints: device),
          throwsA(isA<PasskeyLostException>()
              .having((e) => e.cause, 'cause', isA<PkamRefusedException>())));
      expect(wire.dials, 0);
    });

    test('a public key mismatch is a typed error and closes the session',
        () async {
      final device = await enrolledElsewhere();
      server.publishes = (_) => false;

      await expectLater(
          login(withHints: device), throwsA(isA<PublicKeyMismatchException>()));

      expect(gateway.lastSession!.closed, isTrue);
      expect(wire.dials, 0);
      expect(AtClientImpl.holdsLiveClient(_atSign), isFalse);
    });

    test('closes the custody session when the client does not come online',
        () async {
      final device = await enrolledElsewhere();
      wire.pkamAccepted = false;

      await expectLater(login(withHints: device),
          throwsA(isA<PortalSessionOfflineException>()));

      expect(gateway.lastSession!.closed, isTrue);
      expect(AtClientImpl.holdsLiveClient(_atSign), isFalse);
    });
  });
}
