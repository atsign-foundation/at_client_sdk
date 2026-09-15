import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

/// The atServer's answers are raw literals: the codes and the colon after
/// them are its wire vocabulary, captured from the verb handlers that write
/// them, and a change to either changes what a client gives up on.
void main() {
  group('an enrollment the atServer will not authenticate is a refusal', () {
    const answers = {
      'error:AT0025:enrollment_id: e1 is denied': CredentialRefusal.denied,
      'error:AT0026:enrollment_id: e1 is pending': CredentialRefusal.pending,
      'error:AT0027:enrollment_id: e1 is revoked': CredentialRefusal.revoked,
      'error:AT0028:enrollment_id: e1 is expired or invalid':
          CredentialRefusal.expired,
      'error:AT0028:The enrollment id: e1 is expired. Closing the connection':
          CredentialRefusal.expired,
    };

    for (final entry in answers.entries) {
      test('${entry.value.name}: ${entry.key}', () {
        final wrapped = UnAuthenticatedException(
            'Failed connecting to @alice. ${entry.key}');
        expect(credentialRefusalIn(wrapped), entry.value,
            reason: 'as the authenticator raises it');
        expect(credentialRefusalIn(AtLookUpException('AT0401', '$wrapped')),
            entry.value,
            reason: 'as executeVerb wraps it, with only the text left');
        expect(credentialRefusalIn(entry.key), entry.value,
            reason: 'as the bare answer');
      });
    }
  });

  group('a failure a retry may change is not one', () {
    const notRefusals = [
      'Failed connecting to @alice. The authenticator reported failure',
      'Failed connecting to @alice. error:AT0401:Client authentication failed',
      'Failed connecting to @alice. error:AT0011:Internal server error',
      'error:AT0028-Too Many Requests',
      'error:{"errorCode":"AT0028","errorDescription":"Too Many Requests"}',
      'Exception: Connecting to 127.0.0.1:1 : SocketException: Connection '
          'refused (OS Error: Connection refused, errno = 61)',
      'The connection went away before a response arrived',
    ];

    for (final text in notRefusals) {
      test(text, () {
        expect(credentialRefusalIn(UnAuthenticatedException(text)), isNull);
        expect(credentialRefusalIn(text), isNull);
      });
    }
  });
}
