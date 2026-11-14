import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client_flutter/src/widgets/shared/failure_message.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUpException;
import 'package:flutter_test/flutter_test.dart';

/// What the dialogs show for each kind of failure, one failure at a time.
void main() {
  const atSign = '@alice';
  const timedOut = 'timed out, as the dialog says it';
  const unreachable =
      'The atServer for @alice could not be reached. Please check your '
      'connection and try again.';

  String shown(Object error, {String? unreachable}) => failureMessage(
    atSign,
    error,
    timedOut: timedOut,
    unreachable: unreachable,
  );

  group('a wait that ran out shows the dialog\'s timeout advice', () {
    final cases = <String, Object>{
      'AtTimeoutException': AtTimeoutException('no answer'),
      'TimeoutException': TimeoutException('no answer'),
      'AtLookUpException AT0023': AtLookUpException('AT0023', 'no answer'),
    };
    for (final MapEntry(key: name, value: error) in cases.entries) {
      test(name, () => expect(shown(error), timedOut));
    }
  });

  group(
    'any other failure to reach a server shows that it was not reached',
    () {
      final cases = <String, Object>{
        'SocketException': const SocketException('Connection refused'),
        'SecondaryConnectException': SecondaryConnectException('refused'),
        'RootServerConnectivityException': RootServerConnectivityException(
          'refused',
        ),
        'SecondaryServerConnectivityException':
            SecondaryServerConnectivityException('refused'),
        'AtIOException': AtIOException('broken pipe'),
        'AtLookUpException AT0014 wrapping a socket failure': AtLookUpException(
          'AT0014',
          'Exception: Connecting to 127.0.0.1:1 : SocketException: Connection '
              'refused (OS Error: Connection refused, errno = 61)',
        ),
        'AtLookUpException AT0021': AtLookUpException('AT0021', 'refused'),
      };
      for (final MapEntry(key: name, value: error) in cases.entries) {
        test(name, () => expect(shown(error), unreachable));
      }

      test('in the words the dialog gives', () {
        expect(
          shown(const SocketException('refused'), unreachable: 'not reached'),
          'not reached',
        );
      });
    },
  );

  group('an atServer refusal shows its cause in plain words', () {
    AtConnectionState refused(AtConnectionCause cause) =>
        AtConnectionState.refused(cause);
    final cases = <String, (Object, String)>{
      'an expired enrollment': (
        AtOpenRefusedException(
          atSign,
          refused(AtConnectionCause.invalidEnrollment),
        ),
        "This device's enrollment for @alice has expired.",
      ),
      'keys the atServer did not accept': (
        AtOpenRefusedException(
          atSign,
          refused(AtConnectionCause.unauthenticated),
        ),
        "The atServer for @alice did not accept this device's keys.",
      ),
      'a refusal with no known code': (
        AtOpenRefusedException(atSign, refused(AtConnectionCause.otherRefusal)),
        'The atServer for @alice refused this device.',
      ),
      'a refusal of the keys alone': (
        AtCredentialRefusedException(
          atSign,
          refused(AtConnectionCause.revoked),
        ),
        "This device's access to @alice has been revoked.",
      ),
      'an atDirectory with no entry, however it is thrown': (
        SecondaryNotFoundException('No entry in atDirectory for alice'),
        '@alice is not in the atDirectory.',
      ),
    };
    for (final MapEntry(key: name, value: (error, message)) in cases.entries) {
      test(name, () => expect(shown(error), message));
    }
  });

  test("anything else shows its message's first line, and no FormatException "
      'source', () {
    const source = '{"aesPkamPrivateKey": "c2VjcmV0LWtleS1tYXRlcmlhbA=="';
    expect(
      shown(const FormatException('Unexpected end of input', source)),
      'Something went wrong with @alice: Unexpected end of input',
    );
  });
}
