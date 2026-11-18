/// Catalogue: features/at_client/pkam_refusal.feature
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:at_client/src/passkey/enrollment_gateway.dart';
import 'package:at_client/src/passkey/passkey_custody.dart';
import 'package:at_commons/at_commons.dart'
    show AtRootDomain, ConnectionInvalidException, UnAuthenticatedException;
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

/// What the atServer does with a `pkam:` on [socket].
typedef _PkamAnswer = Future<void> Function(FakeAtServerSocket socket);

_PkamAnswer _replies(String line) => (socket) => socket.serverSends(line);

/// An atServer reached through real at_lookup connections over a fake
/// transport: it answers `from:` with a challenge naming the atSign asked
/// about, and every `pkam:` with [onPkam].
class _PkamServer {
  _PkamServer(this.onPkam);

  final _PkamAnswer onPkam;

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
      final atSign = command.substring('from:'.length).trim();
      unawaited(socket.serverSends('data:_$_uuid$atSign:$_uuid\n@'));
    } else if (command.startsWith('pkam:')) {
      pkams.add(command);
      unawaited(onPkam(socket));
    } else {
      unawaited(
          socket.serverSends('error:AT0003-Exception: Invalid syntax\n@'));
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

  PasskeyCustody custody(_PkamServer atServer, FakeHints hints) =>
      PasskeyCustody(
          prf: PasskeyPrf(passkeys),
          deriver: const BytesPasskeyKeyDeriver(),
          pointerReader: pointers,
          gateway: AtAuthEnrollmentGateway(
              lookUps: atServer.lookUps,
              finder: FixedSecondaryAddressFinder('127.0.0.1', 1),
              root: AtRootDomain.atsignDomain,
              app: 'wavi',
              device: 'browser',
              clientOpener: (
                      {required lookUp,
                      required atSign,
                      required enrollmentId,
                      required keysIo}) async =>
                  throw StateError('no client opens after a failed PKAM')),
          credentials: hints,
          enrollmentIds: hints,
          pendingStore: FakePendingStore(),
          setupLock: FakeSetupLock(),
          setupLockPrefix: 'test:setup',
          retryDelay: Duration.zero);

  const outline1 =
      'A PKAM the atServer refuses for the passkey\'s enrollment is a lost '
      'passkey';
  for (final (code, reply) in [
    ('AT0401', 'error:AT0401-Exception: pkam authentication failed\n@'),
    ('AT0025', 'error:AT0025:enrollment_id: $_eid is denied\n@'),
    ('AT0027', 'error:AT0027:enrollment_id: $_eid is revoked\n@'),
    ('AT0028', 'error:AT0028:enrollment_id: $_eid is expired or invalid\n@'),
  ]) {
    test('$outline1 ($code)', () async {
      final atServer = _PkamServer(_replies(reply));

      await expectLater(
          custody(atServer, FakeHints()).open(atSign: _atSign),
          throwsA(isA<PasskeyLostException>().having(
              (e) => e.cause,
              'cause',
              isA<PkamRefusedException>()
                  .having((e) => e.enrollmentId, 'enrollmentId', _eid))),
          reason: 'the atServer refused the enrollment with $code');
      expect(atServer.pkams, isNotEmpty,
          reason: 'the refusal answered a pkam: sent on the wire');
      expect(atServer.pkams.first, contains('enrollmentId:$_eid:'),
          reason: 'the pkam: named the enrollment the pointer holds');
    });
  }

  const outline2 = 'A PKAM failure that is not a refusal propagates as it is';
  for (final (failure, answer, propagated) in [
    (
      'answers AT0026 because the enrollment is pending',
      _replies('error:AT0026:enrollment_id: $_eid is pending\n@'),
      isA<UnAuthenticatedException>().having((e) => e.message, 'message',
          'Failed connecting to $_atSign. error:AT0026:enrollment_id: $_eid is pending'),
    ),
    (
      'closes the connection',
      (FakeAtServerSocket socket) => socket.serverCloses(),
      isA<ConnectionInvalidException>(),
    ),
  ]) {
    test('$outline2 ($failure)', () async {
      final atServer = _PkamServer(answer);
      final hints = FakeHints()
        ..credentials[_atSign] = _credential
        ..ids[_atSign] = _eid;

      await expectLater(
          custody(atServer, hints).open(atSign: _atSign), throwsA(propagated),
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
