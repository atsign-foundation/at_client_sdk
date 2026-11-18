/// Catalogue: features/at_client/pkam_refusal.feature
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart' show AtKeys;
import 'package:at_auth/passkey.dart';
import 'package:at_client/src/passkey/enrollment_gateway.dart';
import 'package:at_client/src/passkey/passkey_custody.dart';
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

  AtAuthEnrollmentGateway gateway(AtLookUpFactory lookUps) =>
      AtAuthEnrollmentGateway(
          lookUps: lookUps,
          finder: FixedSecondaryAddressFinder('127.0.0.1', 1),
          root: AtRootDomain.atsignDomain,
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

  PasskeyCustody custody(AtLookUpFactory lookUps, FakeHints hints) =>
      PasskeyCustody(
          prf: PasskeyPrf(passkeys),
          deriver: const BytesPasskeyKeyDeriver(),
          pointerReader: pointers,
          gateway: gateway(lookUps),
          credentials: hints,
          enrollmentIds: hints,
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
    ('no code', 'the reply is blank', () => _refusing('')),
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
}
