import 'dart:convert';

import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'syntax_test.dart';

void main() {
  group('A group of tests related to enroll verb', () {
    test('A test to verify enroll request params', () {
      String command =
          'enroll:request:{"enrollmentId":"1234","appName":"wavi","deviceName":"pixel","namespaces":{"wavi":"rw","__manage":"r"},"encryptedDefaultEncryptionPrivateKey":"dummy_encrypted_private_key","encryptedDefaultSelfEncryptionKey":"dummy_self_encryption_key", "encryptedAPKAMSymmetricKey":"dummy_pkam_sym_key","apkamPublicKey":"abcd1234"}';
      expect(RegExp(VerbSyntax.enroll).hasMatch(command), true);
      command = command.replaceAll('enroll:request:', '');
      var enrollParams = jsonDecode(command);
      expect(enrollParams['enrollmentId'], '1234');
      expect(enrollParams['appName'], 'wavi');
      expect(enrollParams['deviceName'], 'pixel');
      expect(enrollParams['namespaces']['wavi'], 'rw');
      expect(enrollParams['namespaces']['__manage'], 'r');
      expect(enrollParams['encryptedDefaultEncryptionPrivateKey'],
          'dummy_encrypted_private_key');
      expect(enrollParams['encryptedDefaultSelfEncryptionKey'],
          'dummy_self_encryption_key');
      expect(enrollParams['encryptedAPKAMSymmetricKey'], 'dummy_pkam_sym_key');
      expect(enrollParams['apkamPublicKey'], 'abcd1234');
    });

    test('A test to verify enroll approve params', () {
      String command =
          'enroll:approve:{"enrollmentId":"123","appName":"wavi","deviceName":"pixel","namespaces":{"wavi":"rw"},"encryptedDefaultEncryptionPrivateKey":"dummy_encrypted_private_key","encPrivateKeyIV":"MHz0FJD63Dm3y5/w2fc+qw==","encryptedDefaultSelfEncryptionKey":"dummy_self_encryption_key","selfEncKeyIV":"G7GXk44cpIFACy31MSaUkA==","encryptedAPKAMSymmetricKey":"dummy_pkam_sym_key","apkamPublicKey":"abcd1234"}';
      expect(RegExp(VerbSyntax.enroll).hasMatch(command), true);
      command = command.replaceAll('enroll:approve:', '');
      var enrollParams = jsonDecode(command);
      expect(enrollParams['enrollmentId'], '123');
      expect(enrollParams['appName'], 'wavi');
      expect(enrollParams['deviceName'], 'pixel');
      expect(enrollParams['namespaces']['wavi'], 'rw');
      expect(enrollParams['encryptedDefaultEncryptionPrivateKey'],
          'dummy_encrypted_private_key');
      expect(enrollParams['encPrivateKeyIV'], 'MHz0FJD63Dm3y5/w2fc+qw==');
      expect(enrollParams['encryptedDefaultSelfEncryptionKey'],
          'dummy_self_encryption_key');
      expect(enrollParams['selfEncKeyIV'], 'G7GXk44cpIFACy31MSaUkA==');
      expect(enrollParams['encryptedAPKAMSymmetricKey'], 'dummy_pkam_sym_key');
      expect(enrollParams['apkamPublicKey'], 'abcd1234');
    });

    test('A test to verify enroll deny params', () {
      String command = 'enroll:deny:{"enrollmentId":"123"}';
      expect(RegExp(VerbSyntax.enroll).hasMatch(command), true);
      command = command.replaceAll('enroll:deny:', '');
      var enrollParams = jsonDecode(command);
      expect(enrollParams['enrollmentId'], '123');
    });

    test('A test to verify enroll revoke params', () {
      String command = 'enroll:revoke:{"enrollmentId":"123"}';
      expect(RegExp(VerbSyntax.enroll).hasMatch(command), true);
      command = command.replaceAll('enroll:revoke:', '');
      var enrollParams = jsonDecode(command);
      expect(enrollParams['enrollmentId'], '123');
    });

    test('A test to verify enroll list regex with params', () {
      String command =
          'enroll:list:{"enrollmentStatusFilter":"[pending, approved]"}';
      expect(RegExp(VerbSyntax.enroll).hasMatch(command), true);

      command = command.replaceAll('enroll:list:', '');
      var enrollParams = jsonDecode(command);
      expect(enrollParams['enrollmentStatusFilter'], '[pending, approved]');
    });

    test('A test to verify enroll list regex without params', () {
      String command = 'enroll:list';
      expect(RegExp(VerbSyntax.enroll).hasMatch(command), true);
    });

    test('A test to verify enroll fetch with enrollment id', () {
      String command = 'enroll:fetch:{"enrollmentId":"123"}';
      expect(RegExp(VerbSyntax.enroll).hasMatch(command), true);

      Map<dynamic, dynamic> enrollmentParams =
          getVerbParams(VerbSyntax.enroll, command);
      expect(enrollmentParams['operation'], 'fetch');
      expect(enrollmentParams['enrollParams'], '{"enrollmentId":"123"}');
    });

    test('A test to verify enroll unrevoke params', () {
      String command = 'enroll:unrevoke:{"enrollmentId":"123"}';
      expect(RegExp(VerbSyntax.enroll).hasMatch(command), true);

      Map<dynamic, dynamic> enrollmentParams =
          getVerbParams(VerbSyntax.enroll, command);
      expect(enrollmentParams['operation'], 'unrevoke');
      expect(enrollmentParams['enrollParams'], '{"enrollmentId":"123"}');
    });
  });

  group('A group of tests to verify toJson and fromJson in EnrollParams', () {
    test('A test to verify toJson', () {
      EnrollParams enrollParams = EnrollParams()
        ..appName = 'wavi'
        ..deviceName = 'pixel'
        ..namespaces = {'wavi': 'rw', '__manage': 'r'}
        ..apkamPublicKey = 'abcd1234'
        ..enrollmentId = '1234'
        ..encryptedAPKAMSymmetricKey = 'dummy_pkam_sym_key'
        ..encryptedDefaultEncryptionPrivateKey = 'dummy_encrypted_private_key'
        ..encryptedDefaultSelfEncryptionKey = 'dummy_self_encryption_key'
        ..enrollmentStatusFilter = [
          EnrollmentStatus.approved,
          EnrollmentStatus.pending
        ];

      Map<String, dynamic> enrollParamsMap = enrollParams.toJson();
      expect(enrollParamsMap['appName'], 'wavi');
      expect(enrollParamsMap['deviceName'], 'pixel');
      expect(enrollParamsMap['namespaces'], {'wavi': 'rw', '__manage': 'r'});
      expect(enrollParamsMap['apkamPublicKey'], 'abcd1234');
      expect(enrollParamsMap['enrollmentId'], '1234');
      expect(
          enrollParamsMap['encryptedAPKAMSymmetricKey'], 'dummy_pkam_sym_key');
      expect(enrollParamsMap['encryptedDefaultEncryptionPrivateKey'],
          'dummy_encrypted_private_key');
      expect(enrollParamsMap['encryptedDefaultSelfEncryptionKey'],
          'dummy_self_encryption_key');
      expect(
          enrollParamsMap['enrollmentStatusFilter'], ['approved', 'pending']);
    });

    test('A test to verify fromJson', () {
      var enrollParamsMap = <String, dynamic>{};
      enrollParamsMap['appName'] = 'wavi';
      enrollParamsMap['deviceName'] = 'pixel';
      enrollParamsMap['namespaces'] = {'wavi': 'rw', '__manage': 'r'};
      enrollParamsMap['apkamPublicKey'] = 'abcd1234';
      enrollParamsMap['enrollmentId'] = '1234';
      enrollParamsMap['encryptedAPKAMSymmetricKey'] = 'dummy_pkam_sym_key';
      enrollParamsMap['encryptedDefaultEncryptionPrivateKey'] =
          'dummy_encrypted_private_key';
      enrollParamsMap['encryptedDefaultSelfEncryptionKey'] =
          'dummy_self_encryption_key';
      enrollParamsMap['otp'] = '123';
      enrollParamsMap['enrollmentStatusFilter'] = ['approved', 'pending'];

      var enrollParams = EnrollParams.fromJson(enrollParamsMap);
      expect(enrollParams.appName, 'wavi');
      expect(enrollParams.deviceName, 'pixel');
      expect(enrollParams.apkamPublicKey, 'abcd1234');
      expect(enrollParams.enrollmentId, '1234');
      expect(enrollParams.encryptedAPKAMSymmetricKey, 'dummy_pkam_sym_key');
      expect(enrollParams.encryptedDefaultEncryptionPrivateKey,
          'dummy_encrypted_private_key');
      expect(enrollParams.encryptedDefaultSelfEncryptionKey,
          'dummy_self_encryption_key');
      expect(enrollParams.otp, '123');
      expect(enrollParams.namespaces, {'wavi': 'rw', '__manage': 'r'});
      expect(enrollParams.enrollmentStatusFilter,
          [EnrollmentStatus.approved, EnrollmentStatus.pending]);
    });
  });

  group('A group of tests to verify EnrollParams.apsk', () {
    // Raw-literal pins: `apsk` is the wire spelling the atServer reads off
    // enroll:request, and the map is written to the enrollment's published
    // `_apsk` record as-is. A rename on either side is a protocol break, so
    // the name and the contents are pinned rather than asserted through the
    // constants that produce them.
    test('an apsk map survives a wire round trip under the name "apsk"', () {
      // The array form, spelled as KeyPackage's keys are (use/alg/pub) so one
      // vocabulary covers every "list of keys with algorithms" in the
      // protocol. `status: retired` marks an entry no longer used for new
      // operations but retained so historic envelopes still verify; the value
      // is use-neutral because `use` already names the operation.
      final apsk = {
        'v': 1,
        'keys': [
          {
            'use': 'sign',
            'alg': 'mldsa65',
            'pub': 'ZmFrZS1tbC1kc2EtcHVibGlj',
            'status': 'active',
          },
          {
            'use': 'sign',
            'alg': 'rsa2048',
            'pub': 'ZmFrZS1yc2EtcHVibGlj',
            'status': 'retired',
          },
        ],
      };

      final json = (EnrollParams()..apsk = apsk).toJson();
      expect(json['apsk'], apsk);

      final command = 'enroll:request:${jsonEncode(json)}';
      expect(RegExp(VerbSyntax.enroll).hasMatch(command), true,
          reason: 'the enroll grammar takes enrollParams as one opaque blob, '
              'so a nested object needs no syntax change');

      final parsed = EnrollParams.fromJson(
          jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
      expect(parsed.apsk, apsk);
    });

    test('the bare form rides apskLegacy, verbatim and unquoted', () {
      // A plain-legacy enrollment publishes the RSA key string itself, which
      // is what every deployed consumer base64-decodes. It travels on its own
      // field rather than sharing `apsk`, so neither the wire type nor the
      // atServer's handling of `apsk` has to be widened to two types.
      const bare = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A';

      final json = (EnrollParams()..apskLegacy = bare).toJson();
      expect(json['apskLegacy'], bare);
      expect(json['apsk'], isNull);

      final parsed = EnrollParams.fromJson(
          jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
      expect(parsed.apskLegacy, bare,
          reason: 'the value is published as-is; a JSON-encoded (quoted) '
              'string is not what a bare-RSA parser reads');
    });

    test('an absent apsk stays absent rather than becoming an empty map', () {
      // The atServer publishes no `_apsk` at all for an enrollment that sends
      // none, so null and {} must not collapse into each other: an empty map
      // would have it publish "{}" as somebody's signing key.
      final parsed = EnrollParams.fromJson(<String, dynamic>{
        'appName': 'wavi',
        'deviceName': 'pixel',
      });
      expect(parsed.apsk, isNull);
      expect(parsed.toJson()['apsk'], isNull);
    });
  });

  group('A group of tests to verify enroll:update', () {
    // Raw-literal pins. The operation token and the field name are what the
    // atServer matches and reads; a rename on either side is a protocol break,
    // so both are pinned as literals rather than through the enum and the
    // getter that produce them.
    test('the operation token is "update"', () {
      expect(getEnrollOperation(EnrollOperationEnum.update), 'update');
    });

    test('the enroll grammar matches an enroll:update command', () {
      final json = (EnrollParams()
            ..enrollmentId = 'abc-123'
            ..apkamPublicKey = 'ZmFrZS1uZXctcHVibGlj'
            ..signingAlgo = 'mldsa65'
            ..apkamPublicKeySignature = 'ZmFrZS1zaWduYXR1cmU=')
          .toJson();

      final match = RegExp(VerbSyntax.enroll)
          .firstMatch('enroll:update:${jsonEncode(json)}');
      expect(match, isNotNull);
      expect(match!.namedGroup('operation'), 'update');
      expect(match.namedGroup('enrollParams'), jsonEncode(json));
    });

    test('adding "update" leaves the existing operations matching as before',
        () {
      // Widening an alternation can change what an earlier token matches —
      // `listns` precedes `list` for exactly that reason — so every existing
      // operation is re-checked rather than assumed unaffected.
      for (final op in [
        'request',
        'approve',
        'deny',
        'revoke',
        'listns',
        'list',
        'fetch',
        'unrevoke',
        'delete',
      ]) {
        final match = RegExp(VerbSyntax.enroll).firstMatch('enroll:$op:{}');
        expect(match?.namedGroup('operation'), op,
            reason: 'operation "$op" must still capture as itself');
      }
    });

    test('apkamPublicKeySignature survives a wire round trip under that name',
        () {
      const signature = 'ZmFrZS1uZXcta2V5LXNpZ25hdHVyZQ==';

      final json =
          (EnrollParams()..apkamPublicKeySignature = signature).toJson();
      expect(json['apkamPublicKeySignature'], signature);

      final parsed = EnrollParams.fromJson(
          jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
      expect(parsed.apkamPublicKeySignature, signature);
    });

    test('an absent apkamPublicKeySignature stays null', () {
      // The atServer refuses an enroll:update that changes apkamPublicKey
      // without one, so absent must be distinguishable from empty.
      final parsed = EnrollParams.fromJson(<String, dynamic>{
        'enrollmentId': 'abc-123',
      });
      expect(parsed.apkamPublicKeySignature, isNull);
      expect(parsed.toJson()['apkamPublicKeySignature'], isNull);
    });
  });
}
