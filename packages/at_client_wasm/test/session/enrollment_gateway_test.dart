// ignore_for_file: deprecated_member_use
// The fixtures build legacy flat-field keys on purpose.
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_wasm/src/session/enrollment_gateway.dart';
import 'package:at_client_wasm/src/session/passkey_custody.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import 'wire_fakes.dart';

const _atSign = '@alice';
const _eid = 'eid-1';

String _b64(String text) => base64Encode(utf8.encode(text));

final _encPublic = _b64('enc-public');
final _encPrivate = _b64('enc-private');
final _selfEnc = _b64('self-enc');

final _seed = Uint8List.fromList(List.generate(32, (i) => i + 1));

/// The base64 key pair `keyPairFromSeed` derives for [_seed].
Future<({String publicKey, String privateKey})> _derived() async {
  final pair = await MlDsa65PureDartAlgo().keyPairFromSeed(_seed);
  return (
    publicKey: base64Encode(pair.publicKey),
    privateKey: base64Encode(pair.secretKey)
  );
}

/// An [AtEnrollment] that records the request and approves it the way the
/// real handshake does: PKAM on the lookUp it is handed.
class FakeEnrollment implements AtEnrollment {
  AtEnrollmentRequest? request;
  AtLookUp? submittedOn;
  AtLookupMuxable? approvedOn;

  @override
  Future<AtEnrollmentResponse> submit(
      EnrollmentRequest enrollmentRequest, AtLookUp atLookUp) async {
    final r = request = enrollmentRequest as AtEnrollmentRequest;
    submittedOn = atLookUp;
    final pair = r.apkamKeyPair!;
    final keys = AtKeys()
      ..apkamPublicKey = AtBytes.fromString(pair.publicKey)
      ..apkamPrivateKey = AtBytes.fromString(pair.privateKey)
      ..defaultEncryptionPublicKey = AtBytes.fromString(_encPublic)
      ..defaultEncryptionPrivateKey = AtBytes.fromString(_encPrivate)
      ..defaultSelfEncryptionKey = AtBytes.fromString(_selfEnc)
      ..enrollmentId = _eid
      ..fileApkamMaterial(
          enrollmentId: _eid,
          algorithm: CryptographicMaterialAlgorithm.mlDsa65,
          publicKey: pair.publicKey,
          privateKey: pair.privateKey);
    return AtEnrollmentResponse(_eid, EnrollmentStatus.pending,
        atSign: r.atSign,
        rootDomain: r.rootDomain,
        atAuthKeys: keys,
        session: r.session);
  }

  @override
  Future<void> waitForApproval(AtEnrollmentResponse enrollmentResponse,
      {bool logProgress = false,
      int maxRetries = 0,
      Duration retryInterval = Duration.zero,
      required AtLookupMuxable atLookup,
      Future<void>? cancelled}) async {
    approvedOn = atLookup;
    if (!await atLookup.pkamAuthenticate()) {
      throw UnAuthenticatedException('refused');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

void main() {
  final finder = FixedSecondaryAddressFinder('atserver.test', 1);
  late Wire wire;
  late FakeEnrollment enrollment;
  late ({String publicKey, String privateKey}) derived;
  late List<
      ({
        String atSign,
        String cram,
        ({String publicKey, String privateKey}) pair
      })> activations;

  setUpAll(() async => derived = await _derived());

  setUp(() {
    wire = Wire();
    enrollment = FakeEnrollment();
    activations = [];
  });

  AtAuthEnrollmentGateway gateway() => AtAuthEnrollmentGateway(
      transport: (lookUps: wire.lookUps, finder: finder),
      root: AtRootDomain.atsignDomain,
      app: 'wavi',
      device: 'browser',
      namespaces: {'atkeysv': 'rw', 'wavi': 'rw'},
      enrollment: () => enrollment,
      activator: (
          {required atSign, required cram, required apkamKeyPair}) async {
        activations.add((atSign: atSign, cram: cram, pair: apkamKeyPair));
        return AtKeys(atsign: Atsign(atSign))
          ..apkamPublicKey = AtBytes.fromString(apkamKeyPair.publicKey)
          ..apkamPrivateKey = AtBytes.fromString(apkamKeyPair.privateKey)
          ..defaultEncryptionPublicKey = AtBytes.fromString(_encPublic)
          ..defaultEncryptionPrivateKey = AtBytes.fromString(_encPrivate)
          ..defaultSelfEncryptionKey = AtBytes.fromString(_selfEnc)
          ..enrollmentId = _eid
          ..fileApkamMaterial(
              enrollmentId: _eid,
              algorithm: CryptographicMaterialAlgorithm.mlDsa65,
              publicKey: apkamKeyPair.publicKey,
              privateKey: apkamKeyPair.privateKey);
      });

  Future<EnrollmentSession> enroll() =>
      gateway().enroll(atSign: _atSign, authSeed: _seed, otp: 'ABC123');

  group('enroll', () {
    test('sends the key derived from the seed as an ML-DSA-65 APKAM key',
        () async {
      await enroll();

      final request = enrollment.request!;
      expect(request.signingAlgo, SigningAlgoType.mldsa65);
      expect(request.apkamKeyPair?.publicKey, derived.publicKey);
      expect(request.apkamKeyPair?.privateKey, derived.privateKey);
      expect(request.otp, 'ABC123');
      expect(request.namespaces, {'atkeysv': 'rw', 'wavi': 'rw'});
    });

    test('mints no key of its own (X-K13)', () async {
      final session = await enroll();

      final keys = jsonEncode(await session.atKeys());
      expect(keys, isNot(contains(derived.privateKey)));
      expect(enrollment.request!.apkamKeyPair, isNotNull);
      expect(enrollment.request!.advertisedSigningKey, isNull);
      expect(enrollment.request!.metadataBuilder, isNull);
    });

    test('submits and approves on one connection that stays PKAM-authenticated',
        () async {
      final session = await enroll();

      expect(wire.dials, 1);
      expect(enrollment.approvedOn, same(enrollment.submittedOn));
      expect(session.enrollmentId, _eid);
    });

    test('a refused PKAM during approval is a PkamRefusedException', () async {
      wire.pkamAccepted = false;

      await expectLater(enroll(), throwsA(isA<PkamRefusedException>()));
    });
  });

  group('activate', () {
    Future<EnrollmentSession> activate() => gateway()
        .activate(atSign: _atSign, authSeed: _seed, cram: 'cram-secret');

    test('activates with the derived key and the CRAM secret, minting none',
        () async {
      await activate();

      expect(activations, hasLength(1));
      expect(activations.single.atSign, _atSign);
      expect(activations.single.cram, 'cram-secret');
      expect(activations.single.pair.publicKey, derived.publicKey);
      expect(activations.single.pair.privateKey, derived.privateKey);
    });

    test('then authenticates with PKAM as the activation enrollment', () async {
      final session = await activate();

      expect(session.enrollmentId, _eid);
      expect(wire.pkams, 1);
      expect(wire.dials, 1);
    });

    test('its @keys carry no APKAM private key', () async {
      final session = await activate();

      final keys = jsonEncode(await session.atKeys());
      expect(keys, isNot(contains(derived.privateKey)));
      expect(keys, contains(_encPrivate));
    });
  });

  group('authenticate', () {
    Future<EnrollmentSession> authenticate() => gateway()
        .authenticate(atSign: _atSign, enrollmentId: _eid, authSeed: _seed);

    test('runs PKAM on a fresh connection with the derived key', () async {
      final session = await authenticate();

      expect(session.enrollmentId, _eid);
      expect(wire.pkams, 1);
      expect(wire.dials, 1);
      final signer = wire.lookUpsBuilt.single.authenticator;
      expect(signer, isNotNull);
    });

    test('a refusal is a PkamRefusedException naming the enrollment', () async {
      wire.pkamAccepted = false;

      await expectLater(
          authenticate(),
          throwsA(isA<PkamRefusedException>()
              .having((e) => e.enrollmentId, 'enrollmentId', _eid)));
    });

    test('an UnAuthenticatedException is a PkamRefusedException', () async {
      wire.pkamThrows = UnAuthenticatedException('AT0401');

      await expectLater(authenticate(), throwsA(isA<PkamRefusedException>()));
    });

    test('a connection failure is not a refusal', () async {
      wire.connectFails = true;

      await expectLater(authenticate(), throwsStateError);
    });

    test('an authenticated session holds no @keys to hand back', () async {
      final session = await authenticate();

      await expectLater(session.atKeys(), throwsStateError);
    });
  });

  group('session operations', () {
    late EnrollmentSession session;

    setUp(() async {
      wire.lookupAnswer = 'data:null';
      session = await enroll();
    });

    test('document writes go over the PKAM connection', () async {
      final connection = wire.lookUpsBuilt.single;
      await session.documents.put(_atSign, _eid, '{"a":1}');

      expect(wire.dials, 1);
      expect(wire.commands.single,
          startsWith('update:atkeys.$_eid.a.__e$_atSign'));
      expect(connection.commandsSent, 1);
    });

    test('document reads go over the PKAM connection', () async {
      await session.documents.get(_atSign, _eid);

      expect(wire.dials, 1);
      expect(wire.commands.single,
          startsWith('llookup:atkeys.$_eid.a.__e$_atSign'));
    });

    test('pointer writes go over the PKAM connection', () async {
      final hex = '0' * 64;
      await session.pointers.put(_atSign, hex, '{"p":1}');

      expect(wire.dials, 1);
      expect(wire.commands.single,
          startsWith('update:public:_$hex.atkeysv$_atSign'));
    });

    test('pointer reads are anonymous lookups on a connection of their own',
        () async {
      await session.pointers.get(_atSign, '0' * 64);

      expect(wire.dials, 2);
      expect(wire.lookUpsBuilt.last.authenticator, isNull);
      expect(wire.commands.single, startsWith('lookup:_'));
    });

    test('revoke is an enroll:revoke on the PKAM connection', () async {
      await session.revoke('eid-2');

      expect(wire.commands.single, contains('enroll:revoke'));
      expect(wire.commands.single, contains('eid-2'));
      expect(wire.dials, 1);
    });

    test('close closes the PKAM connection', () async {
      await session.close();

      expect(wire.lookUpsBuilt.single.closed, isTrue);
    });
  });

  group('atKeys', () {
    test('holds the enrollment encryption keys and no APKAM private key',
        () async {
      final session = await enroll();

      final keys = await session.atKeys();
      final text = jsonEncode(keys);
      expect(text, isNot(contains(derived.privateKey)));
      expect(keys.containsKey('aesPkamPrivateKey'), isFalse);
      expect(keys['aesEncryptPrivateKey'], _encPrivate);
      expect(keys['aesEncryptPublicKey'], _encPublic);
      expect(text, isNot(contains('privateAuthentication')));
    });
  });

  group('publicKeysMatch', () {
    Future<EnrollmentSession> sessionOver(Wire w) async {
      wire = w;
      return enroll();
    }

    test('is true when the published public key is the restored one', () async {
      final session =
          await sessionOver(Wire()..lookupAnswer = 'data:$_encPublic');

      expect(await session.publicKeysMatch({'aesEncryptPublicKey': _encPublic}),
          isTrue);
      expect(wire.commands.last, 'lookup:publickey$_atSign\n');
    });

    test('is false when the published public key differs', () async {
      final session = await sessionOver(Wire()..lookupAnswer = 'data:other');

      expect(await session.publicKeysMatch({'aesEncryptPublicKey': _encPublic}),
          isFalse);
    });

    test('is false when nothing is published', () async {
      final session = await sessionOver(Wire()..lookupAnswer = 'data:null');

      expect(await session.publicKeysMatch({'aesEncryptPublicKey': _encPublic}),
          isFalse);
    });

    test('is false when the restored keys carry no public key to compare',
        () async {
      final session =
          await sessionOver(Wire()..lookupAnswer = 'data:$_encPublic');

      expect(await session.publicKeysMatch({}), isFalse);
    });
  });
}
