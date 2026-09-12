import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

/// What each failure a connection can raise says about the connection.
///
/// The error codes and the message shapes are raw literals on purpose: the
/// codes are the atServer's wire vocabulary, and the texts are what at_lookup
/// and the address finder produce today, captured from a run against a
/// refused port. A change to either is a change to what this classifies.
void main() {
  // What the authenticator raises when the atServer refuses the credentials:
  // the atServer's own `error:` line, appended to at_lookup's sentence.
  const revokedText =
      'Failed connecting to @alice. error:AT0027:Apkam Access Revoked';
  const unauthenticatedText =
      'Failed connecting to @alice. error:AT0401:Client authentication failed';
  const expiredText =
      'Failed connecting to @alice. error:AT0029:Apkam Enrollment Expired';
  const deniedText = 'Failed connecting to @alice. error:AT0025:Apkam Auth Denied';
  const pendingText = 'Failed connecting to @alice. error:AT0026:Apkam Auth Failed';

  // What the address finder raises when the atDirectory refuses the connect,
  // as captured from a run; once at_lookup's executeVerb has wrapped it, the
  // type is gone and only this text is left.
  const refusedConnectText =
      'Exception: Connecting to 127.0.0.1:1 : SocketException: Connection '
      'refused (OS Error: Connection refused, errno = 61), address = '
      '127.0.0.1, port = 55288';

  void expectClassified(Object error, AtConnectionOutcome outcome,
      AtConnectionCause? cause, String reason) {
    final state = classifyConnectionFailure(error);
    expect(state, isNotNull, reason: '$reason: $error was not classified');
    expect(state!.outcome, outcome, reason: reason);
    expect(state.cause, cause, reason: reason);
    if (outcome != AtConnectionOutcome.online) {
      expect(state.error, same(error),
          reason: 'the state carries what threw');
    }
  }

  group('a refusal is read from the atServer\'s code', () {
    test('typed, as the authenticator raises it', () {
      expectClassified(
          UnAuthenticatedException(revokedText),
          AtConnectionOutcome.refused,
          AtConnectionCause.revoked,
          'AT0027 is a revoked enrollment');
      expectClassified(
          UnAuthenticatedException(unauthenticatedText),
          AtConnectionOutcome.refused,
          AtConnectionCause.unauthenticated,
          'AT0401 is a credential that did not authenticate');
      expectClassified(
          UnAuthenticatedException(expiredText),
          AtConnectionOutcome.refused,
          AtConnectionCause.invalidEnrollment,
          'AT0029 is an expired enrollment');
      expectClassified(
          UnAuthenticatedException(deniedText),
          AtConnectionOutcome.refused,
          AtConnectionCause.enrollmentNotApproved,
          'AT0025 is a denied enrollment');
      expectClassified(
          UnAuthenticatedException(pendingText),
          AtConnectionOutcome.refused,
          AtConnectionCause.enrollmentNotApproved,
          'AT0026 is an enrollment not yet approved');
      expectClassified(
          UnAuthenticatedException('Auth failed'),
          AtConnectionOutcome.refused,
          AtConnectionCause.unauthenticated,
          'a refusal carrying no code is still a refusal');
    });

    test('wrapped by executeVerb, whose code names the type and whose message '
        'keeps the atServer\'s finer one', () {
      expectClassified(
          AtLookUpException('AT0401', 'Exception: $revokedText'),
          AtConnectionOutcome.refused,
          AtConnectionCause.revoked,
          'the message\'s AT0027 outranks the wrapper\'s AT0401');
      expectClassified(
          AtLookUpException('AT0401', 'Exception: Auth failed'),
          AtConnectionOutcome.refused,
          AtConnectionCause.unauthenticated,
          'with no finer code the wrapper\'s stands');
    });

    test('as an error response the atServer sent to a verb', () {
      expectClassified(
          AtLookUpException('AT0027', 'Apkam Access Revoked'),
          AtConnectionOutcome.refused,
          AtConnectionCause.revoked,
          'an error: line decoded by at_lookup carries the code itself');
      expectClassified(
          AtInvalidEnrollmentException('Apkam Enrollment Expired'),
          AtConnectionOutcome.refused,
          AtConnectionCause.invalidEnrollment,
          'the typed form RemoteSecondary rebuilds for AT0029');
    });
  });

  group('no atServer reached is offline', () {
    test('the atDirectory has no atServer for the atSign', () {
      expectClassified(
          SecondaryNotFoundException('No entry in atDirectory for alice'),
          AtConnectionOutcome.offline,
          AtConnectionCause.noAtServer,
          'typed');
      expectClassified(
          AtLookUpException('AT0007', 'No entry in atDirectory for alice'),
          AtConnectionOutcome.offline,
          AtConnectionCause.noAtServer,
          'wrapped');
    });

    test('the atDirectory or atServer cannot be reached, typed', () {
      expectClassified(
          RootServerConnectivityException(refusedConnectText),
          AtConnectionOutcome.offline,
          AtConnectionCause.unreachable,
          'the finder\'s own type');
      expectClassified(
          SecondaryConnectException(
              'unable to connect to atServer for @alice on host:1234'),
          AtConnectionOutcome.offline,
          AtConnectionCause.unreachable,
          'the connect to the atServer failed');
      expectClassified(
          AtTimeoutException('AtLookup.findAtServer for alice timed out'),
          AtConnectionOutcome.offline,
          AtConnectionCause.unreachable,
          'a timeout is nothing reached');
      expectClassified(
          TimeoutException('Future not completed'),
          AtConnectionOutcome.offline,
          AtConnectionCause.unreachable,
          'the attempt\'s own budget expiring');
      expectClassified(
          const SocketException('Connection refused'),
          AtConnectionOutcome.offline,
          AtConnectionCause.unreachable,
          'a raw socket failure');
    });

    test('the atDirectory or atServer cannot be reached, type lost in the '
        'wrapper and read from the text', () {
      expectClassified(
          AtLookUpException('AT0014', refusedConnectText),
          AtConnectionOutcome.offline,
          AtConnectionCause.unreachable,
          'the finder\'s exception has no code, so it arrives as AT0014');
      expectClassified(
          AtLookUpException('AT0021',
              'Exception: unable to connect to atServer for @alice on h:1'),
          AtConnectionOutcome.offline,
          AtConnectionCause.unreachable,
          'SecondaryConnectException has a code');
      expectClassified(
          AtLookUpException('AT0014', 'Request timed out'),
          AtConnectionOutcome.offline,
          AtConnectionCause.unreachable,
          'an empty response is nothing answering');
    });
  });

  group('the atServer answering is online, whatever it said', () {
    test('a server error about the request', () {
      expectClassified(
          AtLookUpException('AT0015', 'key not found'),
          AtConnectionOutcome.online,
          null,
          'a missing key was looked up on a live connection');
      expectClassified(
          UnAuthorizedException(
              'Cannot perform llookup on x due to insufficient privilege'),
          AtConnectionOutcome.online,
          null,
          'a privilege refusal is the atServer answering');
    });
  });

  group('nothing about the connection is null', () {
    test('local and caller-side failures', () {
      expect(classifyConnectionFailure(KeyNotFoundException('phone@alice')),
          isNull,
          reason: 'a local keystore miss says nothing about the atServer');
      expect(classifyConnectionFailure(ArgumentError('bad')), isNull);
      expect(classifyConnectionFailure(AtException('something else')), isNull,
          reason: 'an AtException carrying neither a code nor connectivity '
              'text is not read as either');
    });
  });
}
