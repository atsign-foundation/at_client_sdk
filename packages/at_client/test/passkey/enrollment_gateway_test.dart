// ignore_for_file: deprecated_member_use
// The fixtures build legacy flat-field keys on purpose.
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/passkey.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/passkey/at_server_at_keys_io.dart';
import 'package:at_client/src/passkey/enrollment_gateway.dart';
import 'package:at_client/src/passkey/passkey_custody.dart';
import 'package:at_utils/at_logger.dart';
import 'package:test/test.dart';

import '../support/custody_fakes.dart' show DerivedKeys;
import '../support/wire_fakes.dart';

const _atSign = '@alice';
const _eid = 'eid-1';
final _ns = 'cd' * 32;

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

/// Logs of the given logger-level handler while [body] runs.
Future<List<String>> _warnings(Future<void> Function() body) async {
  final messages = <String>[];
  final previous = AtSignLogger.defaultLoggingHandler;
  AtSignLogger.defaultLoggingHandler = _Capture(messages);
  try {
    await body();
  } finally {
    AtSignLogger.defaultLoggingHandler = previous;
  }
  return messages;
}

class _Capture implements LoggingHandler {
  _Capture(this.messages);

  final List<String> messages;

  @override
  void call(dynamic record) =>
      messages.add('${record.message} ${record.error}');
}

void main() {
  final finder = FixedSecondaryAddressFinder('atserver.test', 1);
  late Wire wire;
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
    activations = [];
  });

  AtAuthEnrollmentGateway gateway() => AtAuthEnrollmentGateway(
      lookUps: wire.lookUps,
      finder: finder,
      root: AtRootDomain.atsignDomain,
      app: 'wavi',
      device: 'browser',
      clientOpener: (
              {required lookUp,
              required atSign,
              required enrollmentId,
              required keysIo}) async =>
          throw UnimplementedError('no client in this test'),
      activator: (
          {required atSign,
          required cram,
          required apkamKeyPair,
          keysIo}) async {
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

  Future<EnrollmentSession> activate() =>
      gateway().activate(atSign: _atSign, authSeed: _seed, cram: 'cram-secret');

  group('activate', () {
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

  group('activation key retention', () {
    test('a PKAM refusal after activation carries the activated keys',
        () async {
      wire.pkamAccepted = false;

      await expectLater(
          activate(),
          throwsA(isA<ActivationUnfinishedException>()
              .having((e) => e.enrollmentId, 'enrollmentId', _eid)
              .having(
                  (e) => jsonEncode(e.takeAtKeys()),
                  'atKeys',
                  allOf(contains(_encPrivate),
                      isNot(contains(derived.privateKey))))
              .having((e) => e.toString(), 'toString',
                  isNot(contains(_encPrivate)))));
    });

    test('an activation that fails after filing keys keeps them resumable',
        () async {
      final cause = StateError('open failed');
      // ignore: invalid_use_of_visible_for_testing_member
      final keysIo = InMemoryAtKeysIo();

      await expectLater(
          activateKeepingKeys(keysIo, _atSign, () async {
            await keysIo.write(
                _atSign,
                withApkamKey(
                    AtKeys(atsign: Atsign(_atSign))
                      ..defaultEncryptionPrivateKey =
                          AtBytes.fromString(_encPrivate),
                    _eid,
                    derived));
            throw cause;
          }),
          throwsA(isA<ActivationUnfinishedException>()
              .having((e) => e.enrollmentId, 'enrollmentId', _eid)
              .having((e) => e.cause, 'cause', same(cause))
              .having(
                  (e) => jsonEncode(e.takeAtKeys()),
                  'atKeys',
                  allOf(contains(_encPrivate),
                      isNot(contains(derived.privateKey))))));
    });

    test('T7 the exception hands its keys over once and forgets them', () {
      final keys = {'aesEncryptPrivateKey': _encPrivate};
      final e = ActivationUnfinishedException(_eid,
          atKeys: keys, cause: StateError('pkam failed'));

      expect(e.takeAtKeys(), same(keys));
      expect(e.takeAtKeys, throwsStateError);
      expect(e.toString(), isNot(contains(_encPrivate)));
    });

    test('an activation that fails before filing keys rethrows its error',
        () async {
      // ignore: invalid_use_of_visible_for_testing_member
      final keysIo = InMemoryAtKeysIo();
      final cause = StateError('cram refused');

      await expectLater(
          activateKeepingKeys(keysIo, _atSign, () async => throw cause),
          throwsA(same(cause)));
    });

    test('a successful activation returns its keys and stops the client',
        () async {
      final held = AtKeys(atsign: Atsign(_atSign))
        ..defaultEncryptionPrivateKey = AtBytes.fromString(_encPrivate);
      // ignore: invalid_use_of_visible_for_testing_member
      final keysIo = InMemoryAtKeysIo.holding(_atSign, held);
      var stopped = false;

      final keys = await activateKeepingKeys(
          keysIo, _atSign, () async => _StoppableClient(() => stopped = true));

      expect(stopped, isTrue);
      expect(keys.defaultEncryptionPrivateKey, AtBytes.fromString(_encPrivate));
    });

    test('a stop that throws still returns the keys read before it', () async {
      final held = AtKeys(atsign: Atsign(_atSign))
        ..defaultEncryptionPrivateKey = AtBytes.fromString(_encPrivate);
      var stopped = false;
      // ignore: invalid_use_of_visible_for_testing_member
      final keysIo = InMemoryAtKeysIo.holding(_atSign, held);

      final keys = await readKeysThenStop(keysIo, _atSign, () async {
        stopped = true;
        throw StateError('stop failed');
      });

      expect(stopped, isTrue);
      expect(keys.defaultEncryptionPrivateKey, AtBytes.fromString(_encPrivate));
    });

    test('a stop that throws is logged with its error and no key material',
        () async {
      final held = AtKeys(atsign: Atsign(_atSign))
        ..defaultEncryptionPrivateKey = AtBytes.fromString(_encPrivate);
      // ignore: invalid_use_of_visible_for_testing_member
      final keysIo = InMemoryAtKeysIo.holding(_atSign, held);

      final logs = await _warnings(() async {
        await readKeysThenStop(
            keysIo, _atSign, () async => throw StateError('stop failed'));
      });

      expect(logs, hasLength(1));
      expect(logs.single, contains('stop failed'));
      expect(logs.single, isNot(contains(_encPrivate)));
    });

    test('a lookUp that fails to close after a refusal is logged', () async {
      wire
        ..pkamThrows = UnAuthenticatedException(
            'Failed connecting to $_atSign. error:AT0401-Client '
            'authentication failed')
        ..stopThrows = true;

      final logs = await _warnings(() async {
        await expectLater(
            gateway().authenticate(
                atSign: _atSign, enrollmentId: _eid, authSeed: _seed),
            throwsA(isA<PkamRefusedException>()));
      });

      expect(logs, hasLength(1));
      expect(logs.single, contains('close failed'));
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

    test('the atServer\'s PKAM refusal is a PkamRefusedException', () async {
      wire.pkamThrows = UnAuthenticatedException(
          'Failed connecting to $_atSign. error:AT0401-Client authentication '
          'failed');

      await expectLater(
          authenticate(),
          throwsA(isA<PkamRefusedException>()
              .having((e) => e.enrollmentId, 'enrollmentId', _eid)));
    });

    test('the refusal message and toString name unrevoke', () {
      final e = PkamRefusedException(_eid);

      expect(e.message, contains('enroll:unrevoke'));
      expect(e.toString(), contains('enroll:unrevoke'));
    });

    for (final reply in [
      'error:AT0011-Internal server exception',
      'error:AT0003-Invalid syntax',
      'throttled',
      ''
    ]) {
      test('a failed handshake reply "$reply" is not a refusal', () async {
        wire.pkamThrows =
            UnAuthenticatedException('Failed connecting to $_atSign. $reply');

        await expectLater(
            authenticate(), throwsA(isA<UnAuthenticatedException>()));
      });
    }

    // The atServer rejects a denied, revoked or unknown enrollment before it
    // checks the signature, replying `error:<code>:enrollment_id: <id> is
    // <state>`; at_auth wraps the reply as `Failed connecting to <atSign>.
    // <reply>`.
    for (final reply in {
      'AT0025': 'is denied',
      'AT0027': 'is revoked',
      'AT0028': 'is expired or invalid',
    }.entries) {
      final code = reply.key;
      String message(String id) => 'Failed connecting to $_atSign. '
          'error:$code:enrollment_id: $id ${reply.value}';

      test('$code naming the presented enrollment is a refusal', () async {
        wire.pkamThrows = UnAuthenticatedException(message(_eid));

        await expectLater(
            authenticate(),
            throwsA(isA<PkamRefusedException>()
                .having((e) => e.enrollmentId, 'enrollmentId', _eid)));
      });

      test('$code naming another enrollment is not a refusal', () async {
        wire.pkamThrows = UnAuthenticatedException(message('${_eid}9'));

        await expectLater(
            authenticate(), throwsA(isA<UnAuthenticatedException>()));
      });

      test('$code naming no enrollment is not a refusal', () async {
        wire.pkamThrows = UnAuthenticatedException(
            'Failed connecting to $_atSign. error:$code:${reply.value}');

        await expectLater(
            authenticate(), throwsA(isA<UnAuthenticatedException>()));
      });
    }

    test('a pending enrollment (AT0026) is not a refusal', () async {
      wire.pkamThrows =
          UnAuthenticatedException('Failed connecting to $_atSign. '
              'error:AT0026:enrollment_id: $_eid is pending');

      await expectLater(
          authenticate(), throwsA(isA<UnAuthenticatedException>()));
    });

    test('an authenticator that reports failure is not a refusal', () async {
      wire.pkamAccepted = false;

      await expectLater(
          authenticate(), throwsA(isA<UnAuthenticatedException>()));
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
      session = await activate();
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
      await session.pointers.put(_atSign, hex, '{"p":1}', ns: _ns);

      expect(wire.dials, 1);
      expect(
          wire.commands.single, startsWith('update:public:_$hex.$_ns$_atSign'));
    });

    test('pointer reads are anonymous lookups on a connection of their own',
        () async {
      await session.pointers.get(_atSign, '0' * 64, ns: _ns);

      expect(wire.dials, 2);
      expect(wire.lookUpsBuilt.last.authenticator, isNull);
      expect(wire.commands.single, startsWith('lookup:_'));
    });

    test('close closes the PKAM connection', () async {
      await session.close();

      expect(wire.lookUpsBuilt.single.closed, isTrue);
    });
  });

  group('atKeys', () {
    test('holds the enrollment encryption keys and no APKAM private key',
        () async {
      final session = await activate();

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
      return activate();
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

  group('completeActivation', () {
    Future<EnrollmentSession> sessionOver(Wire w) async {
      wire = w;
      return activate();
    }

    final keys = {'aesEncryptPublicKey': _encPublic};

    test(
        'publishes the public key when none is published, then deletes the CRAM',
        () async {
      final session = await sessionOver(Wire()..lookupAnswer = 'data:null');

      await session.completeActivation(keys);

      final updates = wire.commands.where((c) => c.startsWith('update'));
      expect(updates, hasLength(1));
      expect(updates.single, contains('publickey$_atSign'));
      expect(updates.single, endsWith('$_encPublic\n'));
      expect(wire.commands.last, startsWith('delete:'));
      expect(wire.commands.last, contains(AtConstants.atCramSecret));
    });

    test('keeps the published public key when it is the restored one',
        () async {
      final session =
          await sessionOver(Wire()..lookupAnswer = 'data:$_encPublic');

      await session.completeActivation(keys);

      expect(wire.wroteToServer, isFalse);
      expect(wire.commands.last, startsWith('delete:'));
    });

    test('refuses a different published public key and keeps the CRAM',
        () async {
      final session = await sessionOver(Wire()..lookupAnswer = 'data:other');

      await expectLater(session.completeActivation(keys),
          throwsA(isA<PublicKeyMismatchException>()));

      expect(wire.wroteToServer, isFalse);
      expect(wire.commands.where((c) => c.startsWith('delete:')), isEmpty);
    });

    for (final (name, value) in [
      ('a line feed', 'MIIB\nXYZ'),
      ('a carriage return', 'MIIB\rXYZ'),
    ]) {
      test('refuses a public key with $name before any command', () async {
        final session = await sessionOver(Wire()..lookupAnswer = 'data:null');
        final sent = wire.commands.length;

        await expectLater(
            session.completeActivation({'aesEncryptPublicKey': value}),
            throwsArgumentError);

        expect(wire.commands, hasLength(sent));
      });
    }

    test('counts a CRAM secret that is already gone as deleted', () async {
      final session = await sessionOver(Wire()
        ..lookupAnswer = 'data:$_encPublic'
        ..answer = (c) => c.startsWith('delete:')
            ? throw KeyNotFoundException('gone')
            : null);

      await session.completeActivation(keys);
    });
  });

  group('a session whose client failed to open', () {
    test('still releases the lookUp when the session closes', () async {
      final gateway = AtAuthEnrollmentGateway(
          lookUps: wire.lookUps,
          finder: finder,
          root: AtRootDomain.atsignDomain,
          app: 'wavi',
          device: 'browser',
          clientOpener: (
                  {required lookUp,
                  required atSign,
                  required enrollmentId,
                  required keysIo}) async =>
              throw StateError('client failed to open'));
      final session = await gateway.authenticate(
          atSign: _atSign, enrollmentId: _eid, authSeed: _seed);
      final vault = (await DerivedKeys.derive(
              Uint8List.fromList(List.generate(32, (i) => i + 7)), _atSign))
          .vault;
      addTearDown(vault.close);

      await expectLater(
          session.openClient(AtServerAtKeysIo(
              documents: session.documents,
              vault: vault,
              enrollmentId: _eid,
              apkamKeyPair: await _derived())),
          throwsStateError);
      expect(wire.lookUpsBuilt.single.closed, isFalse);

      await session.close();

      expect(wire.lookUpsBuilt.single.closed, isTrue);
    });
  });

  group('a client that owns the vault through its keys store', () {
    late PasskeyVault vault;
    late Uint8List heldSeed;
    late EnrollmentSession session;
    late Future<void> Function() stopClient;

    setUp(() async {
      vault = (await DerivedKeys.derive(
              Uint8List.fromList(List.generate(32, (i) => i + 7)), _atSign))
          .vault;
      await vault.withAuthSeed((seed) async => heldSeed = seed);
      final gateway = AtAuthEnrollmentGateway(
          lookUps: wire.lookUps,
          finder: finder,
          root: AtRootDomain.atsignDomain,
          app: 'wavi',
          device: 'browser',
          clientOpener: (
                  {required lookUp,
                  required atSign,
                  required enrollmentId,
                  required keysIo}) async =>
              _KeysClosingClient(lookUp.close, keysIo));
      session = await gateway.authenticate(
          atSign: _atSign, enrollmentId: _eid, authSeed: _seed);
      final client = await session.openClient(AtServerAtKeysIo(
          documents: session.documents,
          vault: vault,
          enrollmentId: _eid,
          apkamKeyPair: await _derived(),
          closedByClient: true));
      stopClient = client.stop;
    });

    test('stays usable while the client runs', () async {
      expect(wire.lookUpsBuilt.single.closed, isFalse);
      expect(heldSeed.every((b) => b == 0), isFalse);
      await vault.withAuthSeed((_) async {});
    });

    test('stopping the client closes the vault through the keys store',
        () async {
      await stopClient();

      expect(wire.lookUpsBuilt.single.closed, isTrue);
      var ran = false;
      await expectLater(
          vault.withAuthSeed((_) async => ran = true), throwsStateError);
      expect(ran, isFalse);
      await expectLater(
          vault.seal(PasskeyRecordType.atkeys, {'a': 1}), throwsStateError);
      await expectLater(
          vault.open(PasskeyRecordType.atkeys, '{}'), throwsStateError);
      expect(heldSeed.every((b) => b == 0), isTrue);
    });

    test(
        'closes the vault when the lookUp fails to close, and the error '
        'propagates', () async {
      wire.stopThrows = true;

      await expectLater(stopClient(), throwsStateError);

      expect(wire.lookUpsBuilt.single.closed, isTrue);
      await expectLater(vault.withAuthSeed((_) async {}), throwsStateError);
      expect(heldSeed.every((b) => b == 0), isTrue);
    });
  });
}

/// An [AtClient] whose only working member is [stop].
class _StoppableClient implements AtClient {
  _StoppableClient(this._onStop);

  final void Function() _onStop;

  @override
  Future<void> stop() async => _onStop();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An [AtClient] that stops its lookUp, then closes a keys store flagged
/// `closedByClient`, as a client's stop does.
class _KeysClosingClient implements AtClient {
  _KeysClosingClient(this._closeLookUp, this._keysIo);

  final Future<void> Function() _closeLookUp;
  final WrittenAtKeysIo _keysIo;

  @override
  Future<void> stop() async {
    try {
      await _closeLookUp();
    } finally {
      if (_keysIo case final ClosableAtKeysIo io when io.closedByClient) {
        await io.close();
      }
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
