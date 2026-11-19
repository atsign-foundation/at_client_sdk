// ignore_for_file: deprecated_member_use
// The fixtures build legacy flat-field keys on purpose.
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/passkey.dart' show PasskeyRecordType;
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/passkey/at_server_at_keys_io.dart';
import 'package:at_client/src/passkey/enrollment_gateway.dart';
import 'package:at_client/src/passkey/passkey_custody.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUpException;
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

  Future<EnrollmentSession> activate() => gateway()
      .activate(atSign: _atSign, apkamKeyPair: derived, cram: 'cram-secret');

  group('apkamKeyPairFromSeed', () {
    test('derives the ML-DSA-65 key pair of the seed as base64', () async {
      final pair = await apkamKeyPairFromSeed(_seed);

      expect(pair.publicKey, derived.publicKey);
      expect(pair.privateKey, derived.privateKey);
    });
  });

  group('activate', () {
    test('activates with the given key pair and the CRAM secret', () async {
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

    test('a PKAM failure after activation is rethrown as it is', () async {
      wire.pkamAccepted = false;

      await expectLater(activate(), throwsA(isA<UnAuthenticatedException>()));
      expect(activations, hasLength(1));
      expect(wire.lookUpsBuilt.single.closed, isTrue);
    });
  });

  group('authenticate', () {
    Future<EnrollmentSession> authenticate() => gateway().authenticate(
        atSign: _atSign, enrollmentId: _eid, apkamKeyPair: derived);

    test('a lookUp that fails to close after a refusal is logged', () async {
      wire
        ..pkamThrows = UnAuthenticatedException(
            'Failed connecting to $_atSign. error:AT0401-Client '
            'authentication failed')
        ..stopThrows = true;

      final logs = await _warnings(() async {
        await expectLater(authenticate(), throwsA(isA<PkamRefusedException>()));
      });

      expect(logs, hasLength(1));
      expect(logs.single, contains('close failed'));
    });

    test('runs PKAM on a fresh connection with the given key pair', () async {
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

  group('publishedEncryptionKey', () {
    Future<EnrollmentSession> sessionOver(Wire w) async {
      wire = w;
      return activate();
    }

    test('is the same when the published public key is the restored one',
        () async {
      final session =
          await sessionOver(Wire()..lookupAnswer = 'data:$_encPublic');

      expect(
          await session
              .publishedEncryptionKey({'aesEncryptPublicKey': _encPublic}),
          PublishedEncryptionKey.same);
      expect(wire.commands.last, 'lookup:publickey$_atSign\n');
    });

    test('is different when the published public key differs', () async {
      final session = await sessionOver(Wire()..lookupAnswer = 'data:other');

      expect(
          await session
              .publishedEncryptionKey({'aesEncryptPublicKey': _encPublic}),
          PublishedEncryptionKey.different);
    });

    test('is none when nothing is published', () async {
      final session = await sessionOver(Wire()..lookupAnswer = 'data:null');

      expect(
          await session
              .publishedEncryptionKey({'aesEncryptPublicKey': _encPublic}),
          PublishedEncryptionKey.none);
    });

    test('is none when the atServer has no publickey (AT0015)', () async {
      final session = await sessionOver(
          Wire()..lookupAnswer = 'error:AT0015-key not found : publickey');

      expect(
          await session
              .publishedEncryptionKey({'aesEncryptPublicKey': _encPublic}),
          PublishedEncryptionKey.none);
    });

    for (final (code, reply) in [
      ('AT0011', 'error:AT0011-Internal server exception'),
      ('AT0014', 'error:AT0014-Request timed out'),
    ]) {
      test(
          'throws the lookup\'s $code failure, which is not the key not '
          'found', () async {
        final session = await sessionOver(Wire()..lookupAnswer = reply);

        await expectLater(
            session.publishedEncryptionKey({'aesEncryptPublicKey': _encPublic}),
            throwsA(isA<AtLookUpException>()
                .having((e) => e.errorCode, 'errorCode', code)));
      });
    }

    test('is the same when the restored keys carry no public key to compare',
        () async {
      final session =
          await sessionOver(Wire()..lookupAnswer = 'data:$_encPublic');

      expect(await session.publishedEncryptionKey({}),
          PublishedEncryptionKey.same);
    });
  });

  group('completeActivation', () {
    test(
        'publishes the encryption public key with ttr -1, then deletes the '
        'CRAM secret, on the PKAM connection', () async {
      final session = await activate();

      await session.completeActivation({'aesEncryptPublicKey': _encPublic});

      expect(wire.commands, [
        'update:ttr:-1:isEncrypted:false:public:publickey$_atSign $_encPublic\n',
        'delete:privatekey:at_secret\n',
      ]);
      expect(wire.dials, 1);
    });

    test('publishes without looking up the key already published', () async {
      wire.lookupAnswer = 'data:other';
      final session = await activate();

      await session.completeActivation({'aesEncryptPublicKey': _encPublic});

      expect(wire.commands.where((c) => c.contains('lookup:')), isEmpty);
      expect(wire.commands.first, endsWith(' $_encPublic\n'));
    });

    test('with no encryption public key, deletes the CRAM secret only',
        () async {
      final session = await activate();

      await session.completeActivation({});

      expect(wire.commands, ['delete:privatekey:at_secret\n']);
    });

    for (final (name, value) in [
      ('a line feed', 'MIIB\nXYZ'),
      ('a carriage return', 'MIIB\rXYZ'),
    ]) {
      test('refuses an encryption public key with $name before any command',
          () async {
        final session = await activate();
        final sent = wire.commands.length;

        await expectLater(
            session.completeActivation({'aesEncryptPublicKey': value}),
            throwsArgumentError);

        expect(wire.commands, hasLength(sent));
      });
    }

    test('counts a CRAM secret the atServer reports as not found as deleted',
        () async {
      final session = await activate();
      wire.answer = (command) => command.startsWith('delete:')
          ? throw AtLookUpException('AT0015', 'key not found')
          : null;

      await session.completeActivation({});

      expect(wire.commands.last, 'delete:privatekey:at_secret\n');
    });
  });

  group('revokeOtherEnrollments', () {
    const list = 'enroll:list:{"enrollmentStatusFilter":["approved"]}\n';
    String revoke(String id) => 'enroll:revoke:{"enrollmentId":"$id"}\n';

    /// An `enroll:list` reply holding [statuses] by enrollment id.
    String listed(Map<String, String> statuses) => 'data:${jsonEncode({
              for (final MapEntry(key: id, value: status) in statuses.entries)
                '$id.new.enrollments.__manage$_atSign': {
                  'appName': 'wavi',
                  'deviceName': 'browser',
                  'namespace': {'__manage': 'rw', '*': 'rw'},
                  'status': status,
                }
            })}';

    /// Answers the first `enroll:list` with [first] and every later one with
    /// [then], and each revoke with [revoked].
    void serve(Map<String, String> first, Map<String, String> then,
        {String? Function(String command)? revoked}) {
      var lists = 0;
      wire.answer = (command) {
        if (command.startsWith('enroll:list')) {
          return listed(lists++ == 0 ? first : then);
        }
        if (command.startsWith('enroll:revoke')) {
          return revoked?.call(command) ??
              'data:{"enrollmentId":"x","status":"revoked"}';
        }
        return null;
      };
    }

    test(
        'revokes every approved enrollment but its own, on the PKAM '
        'connection, then lists again', () async {
      final session = await activate();
      serve({_eid: 'approved', 'eid-0': 'approved', 'eid-9': 'approved'},
          {_eid: 'approved'});

      await session.revokeOtherEnrollments();

      expect(wire.commands, [list, revoke('eid-0'), revoke('eid-9'), list]);
      expect(wire.dials, 1);
    });

    test('revokes nothing that is listed but not approved', () async {
      final session = await activate();
      serve({_eid: 'approved', 'eid-0': 'pending', 'eid-2': 'revoked'},
          {_eid: 'approved'});

      await session.revokeOtherEnrollments();

      expect(wire.commands, [list, list]);
    });

    // NOTE: the lookUp throws an atServer's error reply as an
    // AtLookUpException, which the remote secondary maps by its code.
    for (final code in ['AT0029', 'AT0031', 'AT0032']) {
      test(
          'a revoke the atServer refuses with $code, for an enrollment no '
          'longer approved, is left to the list and is not a failure',
          () async {
        final session = await activate();
        serve({_eid: 'approved', 'eid-0': 'approved'}, {_eid: 'approved'},
            revoked: (_) => throw AtLookUpException(code, 'not approved'));

        await session.revokeOtherEnrollments();

        expect(wire.commands, [list, revoke('eid-0'), list],
            reason: 'an atServer refusal of a revoke is left to the list '
                'that follows');
      });
    }

    test('throws when an approved enrollment other than its own remains',
        () async {
      final session = await activate();
      serve({
        _eid: 'approved',
        'eid-0': 'approved'
      }, {
        _eid: 'approved',
        'eid-0': 'approved'
      }, revoked: (_) => throw AtLookUpException('AT0031', 'refused'));

      await expectLater(session.revokeOtherEnrollments(),
          throwsA(isA<AtEnrollmentException>()));
    });

    test('a revoke that fails other than with an atServer refusal propagates',
        () async {
      // What a real lookUp throws for a lost connection, a timeout, a
      // browser reconnect that fails, and an atServer that is failing,
      // busy, paused or throttling.
      for (final (code, failure) in [
        ('AT0004', 'the connection was lost'),
        ('AT0014', 'Request timed out'),
        ('AT0021', 'wss connect failed'),
        ('AT0011', 'internal server exception'),
        ('AT0012', 'inbound connection limit exceeded'),
        ('AT0024', 'server is paused'),
        ('AT0028', 'throttle limit exceeded'),
      ]) {
        wire.commands.clear();
        final session = await activate();
        serve({_eid: 'approved', 'eid-0': 'approved'}, {_eid: 'approved'},
            revoked: (_) => throw AtLookUpException(code, failure));

        await expectLater(
            session.revokeOtherEnrollments(),
            throwsA(isA<AtException>()
                .having((e) => e.message, 'message', failure)),
            reason: 'only an atServer refusal of a revoke is tolerated');
        expect(wire.commands, [list, revoke('eid-0')], reason: code);
      }
    });

    test('a revoke that cannot reach the atServer propagates', () async {
      final session = await activate();
      final failure =
          AtConnectException('findAtServer for $_atSign : Connection refused');
      serve({_eid: 'approved', 'eid-0': 'approved'}, {_eid: 'approved'},
          revoked: (_) => throw failure);

      await expectLater(
          session.revokeOtherEnrollments(), throwsA(same(failure)),
          reason: 'a revoke that never reached the atServer was not refused');
      expect(wire.commands, [list, revoke('eid-0')]);
    });

    test('a revoke that fails with an I/O error propagates', () async {
      final session = await activate();
      final failure = AtIOException('the socket write failed');
      serve({_eid: 'approved', 'eid-0': 'approved'}, {_eid: 'approved'},
          revoked: (_) => throw failure);

      await expectLater(
          session.revokeOtherEnrollments(), throwsA(same(failure)),
          reason: 'a revoke that failed to send was not refused');
      expect(wire.commands, [list, revoke('eid-0')]);
    });

    test('a revoke whose answer does not come in time propagates', () async {
      final session = await activate();
      final failure = AtTimeoutException(
          'Full response not received after 90000 millis from remote atServer');
      serve({_eid: 'approved', 'eid-0': 'approved'}, {_eid: 'approved'},
          revoked: (_) => throw failure);

      await expectLater(
          session.revokeOtherEnrollments(), throwsA(same(failure)),
          reason: 'a revoke whose answer never came was not refused');
      expect(wire.commands, [list, revoke('eid-0')]);
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
          atSign: _atSign, enrollmentId: _eid, apkamKeyPair: derived);
      final vault = (await DerivedKeys.derive(
              Uint8List.fromList(List.generate(32, (i) => i + 7)), _atSign))
          .vault;
      addTearDown(vault.close);

      await expectLater(
          session.openClient(AtServerAtKeysIo(
              documents: session.documents,
              atSign: _atSign,
              seal: (d) => vault.seal(PasskeyRecordType.atkeys, d),
              open: (r) => vault.open(PasskeyRecordType.atkeys, r),
              enrollmentId: _eid,
              apkamKeyPair: await _derived())),
          throwsStateError);
      expect(wire.lookUpsBuilt.single.closed, isFalse);

      await session.close();

      expect(wire.lookUpsBuilt.single.closed, isTrue);
    });
  });
}
