import 'package:at_commons/src/enroll/enrollment.dart';
import 'package:at_commons/src/verb/enroll_verb_builder.dart';
import 'package:at_commons/src/verb/operation_enum.dart';
import 'package:test/test.dart';

void main() {
  group('A group of enroll verb builder test', () {
    test('A test to verify enroll request', () {
      var enrollVerbBuilder = EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.request
        ..appName = 'wavi'
        ..deviceName = 'pixel'
        ..namespaces = {'wavi': 'rw', '__manage': 'r'}
        ..apkamPublicKey = 'abcd1234'
        ..enrollmentId = '1234'
        ..encryptedAPKAMSymmetricKey = 'dummy_pkam_sym_key'
        ..encryptedDefaultEncryptionPrivateKey = 'dummy_encrypted_private_key'
        ..encryptedDefaultSelfEncryptionKey = 'dummy_self_encryption_key'
        ..apkamKeysExpiryDuration = Duration(minutes: 1);
      var command = enrollVerbBuilder.buildCommand();
      expect(command,
          'enroll:request:{"enrollmentId":"1234","appName":"wavi","deviceName":"pixel","namespaces":{"wavi":"rw","__manage":"r"},"encryptedDefaultEncryptionPrivateKey":"dummy_encrypted_private_key","encryptedDefaultSelfEncryptionKey":"dummy_self_encryption_key","encryptedAPKAMSymmetricKey":"dummy_pkam_sym_key","apkamPublicKey":"abcd1234","apkamKeysExpiryInMillis":60000}\n');
    });

    // Both of these assert against a RAW LITERAL rather than against the
    // builder's own fields, because the point of the pin is the wire: `apsk`
    // existed on EnrollParams with no route to the built command, so a test
    // that read the field back would have passed the whole time the value
    // could not be sent.
    test('a request carries its apsk array to the wire', () {
      var enrollVerbBuilder = EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.request
        ..appName = 'wavi'
        ..deviceName = 'pixel'
        ..namespaces = {'wavi': 'rw'}
        ..apkamPublicKey = 'abcd1234'
        ..signingAlgo = 'mldsa65'
        ..apsk = {
          'v': 1,
          'keys': [
            {
              'kid': '0123456789abcdef',
              'use': 'sign',
              'alg': 'mldsa65',
              'pub': 'PUBKEY'
            }
          ]
        };
      var command = enrollVerbBuilder.buildCommand();
      expect(command,
          'enroll:request:{"appName":"wavi","deviceName":"pixel","namespaces":{"wavi":"rw"},"apkamPublicKey":"abcd1234","signingAlgo":"mldsa65","apsk":{"v":1,"keys":[{"kid":"0123456789abcdef","use":"sign","alg":"mldsa65","pub":"PUBKEY"}]}}\n');
    });

    test('a request carries its bare apskLegacy to the wire, unquoted-as-JSON',
        () {
      var enrollVerbBuilder = EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.request
        ..appName = 'wavi'
        ..deviceName = 'pixel'
        ..namespaces = {'wavi': 'rw'}
        ..apkamPublicKey = 'abcd1234'
        ..apskLegacy = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A';
      var command = enrollVerbBuilder.buildCommand();
      expect(command,
          'enroll:request:{"appName":"wavi","deviceName":"pixel","namespaces":{"wavi":"rw"},"apkamPublicKey":"abcd1234","apskLegacy":"MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A"}\n');
    });

    test('A test to verify enroll approve operation', () {
      var enrollVerbBuilder = EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.approve
        ..enrollmentId = '123'
        ..appName = 'wavi'
        ..deviceName = 'pixel'
        ..namespaces = {'wavi': 'rw'}
        ..apkamPublicKey = 'abcd1234'
        ..encryptedAPKAMSymmetricKey = 'dummy_pkam_sym_key'
        ..encryptedDefaultEncryptionPrivateKey = 'dummy_encrypted_private_key'
        ..encPrivateKeyIV = 'dummy_iv_for_enc_private_key'
        ..encryptedDefaultSelfEncryptionKey = 'dummy_self_encryption_key'
        ..selfEncKeyIV = 'dummy_iv_for_self_encryption_key';
      var command = enrollVerbBuilder.buildCommand();
      expect(command,
          'enroll:approve:{"enrollmentId":"123","appName":"wavi","deviceName":"pixel","namespaces":{"wavi":"rw"},"encryptedDefaultEncryptionPrivateKey":"dummy_encrypted_private_key","encPrivateKeyIV":"dummy_iv_for_enc_private_key","encryptedDefaultSelfEncryptionKey":"dummy_self_encryption_key","selfEncKeyIV":"dummy_iv_for_self_encryption_key","encryptedAPKAMSymmetricKey":"dummy_pkam_sym_key","apkamPublicKey":"abcd1234"}\n');
    });

    test('A test to verify enroll deny operation', () {
      var enrollVerbBuilder = EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.deny
        ..enrollmentId = '123';
      var command = enrollVerbBuilder.buildCommand();
      expect(command, 'enroll:deny:{"enrollmentId":"123"}\n');
    });

    test('A test to verify enroll revoke operation', () {
      var enrollVerbBuilder = EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.revoke
        ..enrollmentId = '123';
      var command = enrollVerbBuilder.buildCommand();
      expect(command, 'enroll:revoke:{"enrollmentId":"123"}\n');
    });

    test('A test to verify enroll force revoke operation', () {
      var enrollVerbBuilder = EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.revoke
        ..enrollmentId = '123'
        ..force = true;
      var command = enrollVerbBuilder.buildCommand();
      expect(command, 'enroll:revoke:force:{"enrollmentId":"123"}\n');
    });

    test('A test to verify to override enroll list status', () {
      var enrollVerbBuilder = EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.list
        ..enrollmentStatusFilter = [
          EnrollmentStatus.approved,
          EnrollmentStatus.pending
        ];
      var command = enrollVerbBuilder.buildCommand();
      expect(command,
          'enroll:list:{"enrollmentStatusFilter":["approved","pending"]}\n');
    });

    test('A test to validate enroll list command with default filter', () {
      var enrollVerbBuilder = EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.list;
      var command = enrollVerbBuilder.buildCommand();
      expect(command, 'enroll:list\n');
    });

    test('A test to validate the enroll fetch command', () {
      EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.fetch
        ..enrollmentId = '123';

      var command = enrollVerbBuilder.buildCommand();

      expect(command, 'enroll:fetch:{"enrollmentId":"123"}\n');
    });

    test('A test to validate the enroll unrevoke command', () {
      EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.unrevoke
        ..enrollmentId = '123';
      expect(enrollVerbBuilder.buildCommand(),
          'enroll:unrevoke:{"enrollmentId":"123"}\n');
    });

    test('A test to validate enroll delete command', () {
      EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.delete
        ..enrollmentId = '4785';
      expect(enrollVerbBuilder.buildCommand(),
          'enroll:delete:{"enrollmentId":"4785"}\n');
    });
  });
}
