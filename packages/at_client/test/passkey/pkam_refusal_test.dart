/// Catalogue: features/at_client/pkam_refusal.feature
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart' show AtKeys;
import 'package:at_auth/passkey.dart';
import 'package:at_client/src/passkey/enrollment_gateway.dart';
import 'package:at_client/src/passkey/passkey_custody.dart';
import 'package:at_client/src/version.dart';
import 'package:at_commons/at_commons.dart'
    show
        AtRootDomain,
        Atsign,
        ConnectionInvalidException,
        UnAuthenticatedException;
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import '../support/bytes_passkey_sealer.dart';
import '../support/custody_fakes.dart';
import '../test_utils/fake_at_server.dart' show FakeAtServerSocket;

const _atSign = '@alice🛠';
const _eid = 'b6f0c3de-0b8e-4f6a-9d1e-6c2f3a8e5b71';
const _uuid = '123e4567-e89b-12d3-a456-426614174000';
const _proxyRoot = AtRootDomain('proxy:127.0.0.1', 64);
final _credential = Uint8List.fromList([1]);

/// The PRF output of the one passkey, fresh each call: deriving wipes it.
Uint8List _prf() => Uint8List.fromList(List.generate(32, (i) => i + 3));

/// What the atServer does with a command on [socket].
typedef _Answer = Future<void> Function(FakeAtServerSocket socket);

/// Answers with [line], then the prompt.
_Answer _replies(String line) => (socket) => socket.serverSends('$line\n@');

/// A `from:` challenge issued to [_atSign].
final _challenge = _replies('data:_$_uuid$_atSign:$_uuid');

/// An atServer reached through real at_lookup connections over a fake
/// transport: it answers each `from:` with [onFrom] and each `pkam:` with
/// [onPkam].
class _PkamServer {
  _PkamServer({_Answer? onFrom, _Answer? onPkam})
      : onFrom = onFrom ?? _challenge,
        onPkam = onPkam ?? _replies('data:success');

  final _Answer onFrom;
  final _Answer onPkam;

  /// Every `from:` command received, in order.
  final froms = <String>[];

  /// Every `pkam:` command received, in order.
  final pkams = <String>[];

  AtLookUpFactory get lookUps => (
          {required String atSign,
          required AtRootDomain rootDomain,
          required AtAuthenticator? authenticator,
          SecondaryAddressFinder? secondaryAddressFinder}) =>
      AtLookUp.withSecureSocket(
          atSign: atSign,
          rootDomain: rootDomain,
          authenticator: authenticator,
          secondaryAddressFinder: FixedSecondaryAddressFinder('127.0.0.1', 1),
          transport: AtLookupTransport(transportFactory: _Dial(this)));

  void _onWrite(FakeAtServerSocket socket, String command) {
    if (command.startsWith('from:')) {
      froms.add(command);
      unawaited(onFrom(socket));
    } else if (command.startsWith('pkam:')) {
      pkams.add(command);
      unawaited(onPkam(socket));
    } else {
      unawaited(_replies('error:AT0003-Exception: Invalid syntax')(socket));
    }
  }
}

class _Dial implements AtTransportFactory {
  _Dial(this._server);

  final _PkamServer _server;

  @override
  Future<AtTransport> connect(String host, String port,
          {Duration? timeout}) async =>
      FakeAtServerSocket(_server._onWrite);
}

/// An atServer that answers the `pkam:` with [reply].
_PkamServer _refusing(String reply) => _PkamServer(onPkam: _replies(reply));

/// AT0401 as an atServer writes it in each form.
const _at0401 = {
  'dash': 'error:AT0401-Exception: pkam authentication failed',
  'colon': 'error:AT0401:Exception: pkam authentication failed',
  'JSON': 'error:{"errorCode":"AT0401",'
      '"errorDescription":"Exception: pkam authentication failed"}',
};

void main() {
  late FakeAuthenticator passkeys;
  late FakeServer pointers;

  setUp(() async {
    passkeys = FakeAuthenticator()
      ..prfByCredential[_credential[0]] = _prf()
      ..current = _credential;
    pointers = FakeServer();
    final keys = await DerivedKeys.derive(_prf(), _atSign);
    pointers
      ..pointers[keys.lookupHex] =
          await keys.vault.seal(PasskeyRecordType.eid, {'enrollmentId': _eid})
      ..pointerNamespaces[keys.lookupHex] = keys.ns;
    keys.vault.close();
  });

  AtAuthEnrollmentGateway gateway(AtLookUpFactory lookUps,
          {AtRootDomain root = AtRootDomain.atsignDomain}) =>
      AtAuthEnrollmentGateway(
          lookUps: lookUps,
          finder: FixedSecondaryAddressFinder('127.0.0.1', 1),
          root: root,
          app: 'wavi',
          device: 'browser',
          clientOpener: (
                  {required lookUp,
                  required atSign,
                  required enrollmentId,
                  required keysIo}) async =>
              throw StateError('no client opens in this test'),
          activator: (
                  {required atSign,
                  required cram,
                  required apkamKeyPair}) async =>
              withApkamKey(AtKeys(atsign: Atsign(atSign)), _eid, apkamKeyPair));

  PasskeyCustody custody(AtLookUpFactory lookUps, FakeHints hints,
          {AtRootDomain root = AtRootDomain.atsignDomain}) =>
      PasskeyCustody(
          prf: PasskeyPrf(passkeys),
          deriver: const BytesPasskeyKeyDeriver(),
          pointerReader: pointers,
          gateway: gateway(lookUps, root: root),
          hints: hints,
          setupLock: FakeSetupLock(),
          setupLockPrefix: 'test:setup',
          retryDelay: Duration.zero);

  FakeHints savedHints() => FakeHints()
    ..credentials[_atSign] = _credential
    ..ids[_atSign] = _eid;

  final isLostPasskey = isA<PasskeyLostException>().having(
      (e) => e.cause,
      'cause',
      isA<PkamRefusedException>()
          .having((e) => e.enrollmentId, 'enrollmentId', _eid));

  Matcher failedWith(String reply) => isA<UnAuthenticatedException>().having(
      (e) => e.message, 'message', 'Failed connecting to $_atSign. $reply');

  final refusedToSign = isA<UnAuthenticatedException>().having((e) => e.message,
      'message', startsWith('Refusing to sign a malformed from: challenge'));

  _PkamServer proxyFailingReconnect() {
    FakeAtServerSocket? firstConnection;
    return _PkamServer(
        onFrom: (socket) {
          firstConnection ??= socket;
          return identical(socket, firstConnection)
              ? _challenge(socket)
              : _replies(_at0401['dash']!)(socket);
        },
        onPkam: (socket) => socket.serverCloses());
  }

  final proxyFailure = allOf(
      isA<AtLookUpException>()
          .having((e) => e.errorCode, 'errorCode', 'AT0401')
          .having((e) => e.errorMessage, 'errorMessage',
              'Exception: pkam authentication failed'),
      isNot(isA<PasskeyLostException>()),
      isNot(isA<PkamRefusedException>()));

  void expectReconnectFailedAtProxyFrom(_PkamServer proxy) {
    expect(proxy.pkams, hasLength(1),
        reason: 'the pkam: was sent before the connection was lost');
    expect(proxy.froms, hasLength(3),
        reason: 'the first connection carried the proxy\'s from: and the '
            'PKAM\'s, and the reconnect stopped at its proxy from:');
    expect(proxy.froms.last, 'from:$_atSign\n',
        reason: 'the error answered the reconnect\'s proxy from:, not a '
            'from: of the PKAM');
  }

  Future<void> expectLostPasskey(_PkamServer atServer, String why) async {
    await expectLater(
        custody(atServer.lookUps, FakeHints()).open(atSign: _atSign),
        throwsA(isLostPasskey),
        reason: why);
    expect(atServer.pkams, isNotEmpty,
        reason: 'the refusal answered a pkam: sent on the wire');
    expect(atServer.pkams.first, contains('enrollmentId:$_eid:'),
        reason: 'the pkam: named the enrollment the pointer holds');
  }

  const outline1 =
      'A PKAM the atServer refuses for the passkey\'s enrollment is a lost '
      'passkey';
  for (final (code, reason, atServer) in [
    (
      'AT0401',
      'the signature did not verify',
      () => _refusing(_at0401['dash']!)
    ),
    (
      'AT0025',
      'the enrollment is denied',
      () => _refusing('error:AT0025:enrollment_id: $_eid is denied')
    ),
    (
      'AT0027',
      'the enrollment is revoked',
      () => _refusing('error:AT0027:enrollment_id: $_eid is revoked')
    ),
    (
      'AT0028',
      'the enrollment has expired, or the atServer no longer holds it',
      () => _refusing('error:AT0028:enrollment_id: $_eid is expired or invalid')
    ),
    (
      'AT0028',
      'the enrollment has expired, though the reply does not name it',
      () => _refusing('error:AT0028:Enrollment expired')
    ),
    (
      'AT0029',
      'the enrollment has expired, or the atServer no longer holds it',
      () => _refusing('error:AT0029:enrollment_id: $_eid is expired or invalid')
    ),
    ('no code', 'the reply is empty', () => _refusing('')),
    ('no code', 'the reply carries no error:', () => _refusing('data:failure')),
  ]) {
    test('$outline1 ($code, $reason)', () async {
      await expectLostPasskey(
          atServer(), 'the atServer refused the enrollment: $reason');
    });
  }

  const outline2 =
      'A refusal reads the same in every form the atServer writes it in';
  _at0401.forEach((form, reply) {
    test('$outline2 ($form)', () async {
      await expectLostPasskey(
          _refusing(reply), 'AT0401 in the $form form is a refusal');
    });
  });

  const outline3 =
      'A failure at the from: on the PKAM\'s connection is not a refusal';
  for (final (answer, reply, propagated) in [
    for (final MapEntry(key: form, value: reply) in _at0401.entries)
      ('error:AT0401 in the $form form', reply, failedWith(reply)),
    ('data: and nothing else', 'data:', refusedToSign),
  ]) {
    test('$outline3 ($answer)', () async {
      final atServer = _PkamServer(onFrom: _replies(reply));

      await expectLater(
          custody(atServer.lookUps, FakeHints()).open(atSign: _atSign),
          throwsA(propagated),
          reason: 'the open throws what the from: failed with');
      expect(atServer.froms, isNotEmpty,
          reason: 'the failure answered a from: sent on the wire');
      expect(atServer.pkams, isEmpty, reason: 'no pkam: was sent');
    });
  }

  test('A failure at the from: keeps a device\'s passkey hints', () async {
    final reply = _at0401['dash']!;
    final atServer = _PkamServer(onFrom: _replies(reply));
    final hints = savedHints();

    await expectLater(custody(atServer.lookUps, hints).open(atSign: _atSign),
        throwsA(failedWith(reply)),
        reason: 'the open throws what the from: failed with');
    expect(atServer.pkams, isEmpty, reason: 'no pkam: was sent');
    expect(passkeys.gets, 1, reason: 'the passkey was asked for once');
    expect(pointers.pointerReads, 0,
        reason: 'the hints were not set aside for the pointer');
    expect(hints.credentials[_atSign], _credential,
        reason: 'the device keeps its credential hint');
    expect(hints.ids[_atSign], _eid,
        reason: 'the device keeps its enrollment hint');
  });

  test(
      'A PKAM attempt the connection makes again starts afresh, so a failure '
      'at its from: is not a refusal', () async {
    final reply = _at0401['dash']!;
    late final _PkamServer atServer;
    atServer = _PkamServer(
        onFrom: (socket) => atServer.froms.length == 1
            ? _challenge(socket)
            : _replies(reply)(socket),
        onPkam: (socket) => socket.serverCloses());

    await expectLater(
        custody(atServer.lookUps, FakeHints()).open(atSign: _atSign),
        throwsA(failedWith(reply)),
        reason: 'the open throws what the second attempt\'s from: failed '
            'with');
    expect(atServer.pkams, hasLength(1),
        reason: 'the first attempt sent its pkam: before the connection '
            'was lost');
    expect(atServer.froms, hasLength(2),
        reason: 'the connection made the attempt again');
  });

  test(
      'A PKAM refused on the attempt the connection makes again is a lost '
      'passkey', () async {
    final reply = _at0401['dash']!;
    late final _PkamServer atServer;
    atServer = _PkamServer(
        onPkam: (socket) => atServer.pkams.length == 1
            ? socket.serverCloses()
            : _replies(reply)(socket));

    await expectLostPasskey(
        atServer, 'the second attempt\'s pkam: was refused');
    expect(atServer.pkams, hasLength(2),
        reason: 'the first attempt sent its pkam: before the connection '
            'was lost, and the connection made the attempt again');
  });

  test(
      'A proxy\'s error reply to the from: of a reconnect after the pkam: is '
      'not a refusal', () async {
    final proxy = proxyFailingReconnect();

    await expectLater(
        custody(proxy.lookUps, FakeHints(), root: _proxyRoot)
            .open(atSign: _atSign),
        throwsA(proxyFailure),
        reason: 'the open throws what the proxy answered the reconnect\'s '
            'from: with');
    expect(proxy.froms.first, 'from:$_atSign\n',
        reason: 'the control: the proxy root sends its from: first on a '
            'connection');
    expectReconnectFailedAtProxyFrom(proxy);
  });

  test(
      'A proxy\'s error reply to the from: of a reconnect after the pkam: '
      'keeps a device\'s passkey hints', () async {
    final proxy = proxyFailingReconnect();
    final hints = savedHints();

    await expectLater(
        custody(proxy.lookUps, hints, root: _proxyRoot).open(atSign: _atSign),
        throwsA(proxyFailure),
        reason: 'the open throws what the proxy answered the reconnect\'s '
            'from: with');
    expect(passkeys.gets, 1, reason: 'the passkey was asked for once');
    expect(pointers.pointerReads, 0,
        reason: 'the hints were not set aside for the pointer');
    expect(hints.credentials[_atSign], _credential,
        reason: 'the device keeps its credential hint');
    expect(hints.ids[_atSign], _eid,
        reason: 'the device keeps its enrollment hint');
    expectReconnectFailedAtProxyFrom(proxy);
  });

  const outline4 = 'A PKAM failure that is not a refusal propagates as it is';
  for (final (failure, answer, propagated) in [
    (
      'answers AT0026 because the enrollment is pending',
      _replies('error:AT0026:enrollment_id: $_eid is pending'),
      failedWith('error:AT0026:enrollment_id: $_eid is pending'),
    ),
    (
      'answers with a server error',
      (FakeAtServerSocket socket) async {
        await _replies('error:AT0011-Exception: FileSystemException: '
            'Cannot open file')(socket);
        await socket.serverCloses();
      },
      failedWith('error:AT0011-Exception: FileSystemException: Cannot open '
          'file'),
    ),
    (
      'closes the connection',
      (FakeAtServerSocket socket) => socket.serverCloses(),
      isA<ConnectionInvalidException>(),
    ),
  ]) {
    test('$outline4 ($failure)', () async {
      final atServer = _PkamServer(onPkam: answer);
      final hints = savedHints();

      await expectLater(custody(atServer.lookUps, hints).open(atSign: _atSign),
          throwsA(propagated),
          reason: 'the open throws what the PKAM failed with');
      expect(atServer.pkams, isNotEmpty,
          reason: 'the failure answered a pkam: sent on the wire');
      expect(passkeys.gets, 1,
          reason: 'the hints were not set aside for a second prompt');
      expect(pointers.pointerReads, 0,
          reason: 'the hints were not set aside for the pointer');
      expect(hints.credentials[_atSign], _credential,
          reason: 'the device keeps its credential hint');
      expect(hints.ids[_atSign], _eid,
          reason: 'the device keeps its enrollment hint');
    });
  }

  const outline5 =
      'The from: on the passkey\'s PKAM connection names at_client as the SDK';
  for (final (moment, authenticates) in [
    (
      'at a login',
      (AtAuthEnrollmentGateway gateway, ApkamKeyPair pair) => gateway
          .authenticate(atSign: _atSign, enrollmentId: _eid, apkamKeyPair: pair)
    ),
    (
      'when an onboarding activates the Atsign',
      (AtAuthEnrollmentGateway gateway, ApkamKeyPair pair) => gateway.activate(
          atSign: _atSign, apkamKeyPair: pair, cram: 'cram-secret')
    ),
  ]) {
    test('$outline5 ($moment)', () async {
      final atServer = _PkamServer();
      final pair = await apkamKeyPairFromSeed(_prf());

      final session = await authenticates(gateway(atServer.lookUps), pair);
      await session.close();

      expect(session.enrollmentId, _eid,
          reason: 'the control: the PKAM authenticated the enrollment');
      expect(atServer.froms, hasLength(1), reason: 'one from: began the PKAM');
      const prefix = 'from:$_atSign:clientConfig:';
      expect(atServer.froms.single, startsWith(prefix),
          reason: 'the from: carries a clientConfig');
      final config =
          jsonDecode(atServer.froms.single.substring(prefix.length).trim())
              as Map<String, dynamic>;
      expect(config['sdkName'], 'atsign.dart.at_client',
          reason: 'the from: names at_client as the SDK');
      expect(config['sdkVersion'], packageVersion,
          reason: 'the from: carries at_client\'s version as the sdk version');
      expect(config['version'], packageVersion,
          reason: 'the from: carries at_client\'s version as version');
    });
  }
}
