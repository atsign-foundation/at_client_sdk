import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'syntax_test.dart';

void main() {
  group('A group of update verb builder tests to check update command', () {
    test('verify public at key command', () {
      var updateBuilder = UpdateVerbBuilder()
        ..value = 'alice@gmail.com'
        ..atKey.metadata.isPublic = true
        ..atKey.key = 'email'
        ..atKey.sharedBy = '@alice';
      expect(updateBuilder.buildCommand(),
          'update:isEncrypted:false:public:email@alice alice@gmail.com\n');
    });

    test('verify private at key command', () {
      var updateBuilder = UpdateVerbBuilder()
        ..value = 'alice@atsign.com'
        ..atKey.key = 'email'
        ..atKey.sharedBy = '@alice';
      expect(updateBuilder.buildCommand(),
          'update:isEncrypted:false:email@alice alice@atsign.com\n');
    });

    test(
        'verify update command with the shared symmetric key inline and encrypted',
        () {
      var pubKeyCS =
          'the_checksum_of_the_public_key_used_to_encrypted_the_AES_key';
      var ske =
          'the_AES_key__encrypted_with_some_public_key__encoded_as_base64';
      var skeEncKeyName = 'key_45678.__public_keys.__global';
      var skeEncAlgo = 'ECC/SomeCurveName/blah';
      var updateBuilder = UpdateVerbBuilder()
        ..value = 'alice@atsign.com'
        ..atKey.key = 'email.wavi'
        ..atKey.sharedBy = '@alice'
        ..atKey.sharedWith = '@bob'
        // ignore: deprecated_member_use_from_same_package
        ..atKey.metadata.pubKeyCS = pubKeyCS
        ..atKey.metadata.sharedKeyEnc = ske
        ..atKey.metadata.skeEncKeyName = skeEncKeyName
        ..atKey.metadata.skeEncAlgo = skeEncAlgo;
      var updateCommand = updateBuilder.buildCommand();
      expect(
          updateCommand,
          'update:isEncrypted:false'
          ':sharedKeyEnc:$ske'
          ':pubKeyCS:$pubKeyCS'
          ':skeEncKeyName:$skeEncKeyName'
          ':skeEncAlgo:$skeEncAlgo'
          ':@bob:email.wavi@alice alice@atsign.com'
          '\n');
      var updateVerbParams =
          getVerbParams(VerbSyntax.update, updateCommand.trim());
      expect(updateVerbParams[AtConstants.atKey], 'email.wavi');
      expect(updateVerbParams[AtConstants.atSign], 'alice');
      expect(updateVerbParams[AtConstants.forAtSign], 'bob');
      expect(
          updateVerbParams[AtConstants.sharedWithPublicKeyCheckSum], pubKeyCS);
      expect(updateVerbParams[AtConstants.sharedKeyEncrypted], ske);
      expect(updateVerbParams[AtConstants.sharedKeyEncryptedEncryptingKeyName],
          skeEncKeyName);
      expect(updateVerbParams[AtConstants.sharedKeyEncryptedEncryptingAlgo],
          skeEncAlgo);
    });

    test('verify local key command', () {
      var updateBuilder = UpdateVerbBuilder()
        ..value = 'alice@atsign.com'
        ..atKey.key = 'email'
        ..atKey.sharedBy = '@alice'
        ..atKey.isLocal = true;
      expect(updateBuilder.buildCommand(),
          'update:isEncrypted:false:local:email@alice alice@atsign.com\n');
    });
  });

  group('A group of update verb builder tests to check update metadata command',
      () {
    test('verify isBinary metadata', () {
      var updateBuilder = UpdateVerbBuilder()
        ..atKey.metadata.isBinary = true
        ..atKey.key = 'phone'
        ..atKey.sharedBy = '@alice';
      expect(updateBuilder.buildCommandForMeta(),
          'update:meta:phone@alice:isBinary:true:isEncrypted:false\n');
    });

    test('verify ttl metadata', () {
      var updateBuilder = UpdateVerbBuilder()
        ..atKey.metadata.ttl = 60000
        ..atKey.key = 'phone'
        ..atKey.sharedBy = '@alice';
      expect(updateBuilder.buildCommandForMeta(),
          'update:meta:phone@alice:ttl:60000:isEncrypted:false\n');
    });

    test('verify ttr metadata', () {
      var updateBuilder = UpdateVerbBuilder()
        ..atKey.metadata.ttr = 50000
        ..atKey.key = 'phone'
        ..atKey.sharedBy = '@alice';
      expect(updateBuilder.buildCommandForMeta(),
          'update:meta:phone@alice:ttr:50000:isEncrypted:false\n');
    });

    test('verify ttb metadata', () {
      var updateBuilder = UpdateVerbBuilder()
        ..atKey.metadata.ttb = 80000
        ..atKey.key = 'phone'
        ..atKey.sharedBy = '@alice';
      expect(updateBuilder.buildCommandForMeta(),
          'update:meta:phone@alice:ttb:80000:isEncrypted:false\n');
    });

    test(
        'verify update:meta command with the shared symmetric key inline and encrypted ',
        () {
      var pubKeyCS =
          'the_checksum_of_the_public_key_used_to_encrypted_the_AES_key';
      var ske =
          'the_AES_key__encrypted_with_some_public_key__encoded_as_base64';
      var skeEncKeyName = 'key_45678.__public_keys.__global';
      var skeEncAlgo = 'ECC/SomeCurveName/blah';
      var updateBuilder = UpdateVerbBuilder()
        ..atKey.metadata.isEncrypted = true
        ..atKey.key = 'cabbages_and_kings.wonderland'
        ..atKey.sharedBy = '@walrus'
        ..atKey.sharedWith = '@carpenter'
        // ignore: deprecated_member_use_from_same_package
        ..atKey.metadata.pubKeyCS = pubKeyCS
        ..atKey.metadata.sharedKeyEnc = ske
        ..atKey.metadata.skeEncKeyName = skeEncKeyName
        ..atKey.metadata.skeEncAlgo = skeEncAlgo;
      var updateMetaCommand = updateBuilder.buildCommandForMeta();
      expect(
          updateMetaCommand,
          'update:meta:@carpenter:cabbages_and_kings.wonderland@walrus:isEncrypted:true'
          ':sharedKeyEnc:$ske'
          ':pubKeyCS:$pubKeyCS'
          ':skeEncKeyName:$skeEncKeyName'
          ':skeEncAlgo:$skeEncAlgo'
          '\n');
      var updateMetaVerbParams =
          getVerbParams(VerbSyntax.update_meta, updateMetaCommand.trim());
      expect(updateMetaVerbParams[AtConstants.atKey],
          'cabbages_and_kings.wonderland');
      expect(updateMetaVerbParams[AtConstants.atSign], 'walrus');
      expect(updateMetaVerbParams[AtConstants.forAtSign], 'carpenter');
      expect(updateMetaVerbParams[AtConstants.sharedWithPublicKeyCheckSum],
          pubKeyCS);
      expect(updateMetaVerbParams[AtConstants.sharedKeyEncrypted], ske);
      expect(
          updateMetaVerbParams[AtConstants.sharedKeyEncryptedEncryptingKeyName],
          skeEncKeyName);
      expect(updateMetaVerbParams[AtConstants.sharedKeyEncryptedEncryptingAlgo],
          skeEncAlgo);
    });
  });

  group('A group of positive tests to validate the update regex', () {
    var inputToExpectedOutput = {
      'update:ttl:10000:ttb:10000:ttr:10000:ccd:true:dataSignature:123456:encoding:base64:public:phone@bob 12345':
          {
        'ttl': '10000',
        'ttb': '10000',
        'ttr': '10000',
        'ccd': 'true',
        'dataSignature': '123456',
        'encoding': 'base64',
        'forAtSign': null,
        'atKey': 'phone',
        'atSign': 'bob',
        'value': '12345'
      }
    };
    inputToExpectedOutput.forEach((command, expectedVerbParams) {
      test('validating regex for $command', () {
        var actualVerbParams = getVerbParams(VerbSyntax.update, command);
        for (var key in expectedVerbParams.keys) {
          expect(actualVerbParams[key], expectedVerbParams[key]);
        }
      });
    });
    test(
        'Validate the update command when encKeyName, encAlgo are set, but not ivNonce',
        () {
      var encKeyName = 'key_23456.__public_keys.__global';
      var encAlgo = 'RSA';
      final updateCommand = 'update'
          ':ttl:-1:ttr:-1'
          ':dataSignature:abc:isBinary:false:isEncrypted:false'
          ':encKeyName:$encKeyName'
          ':encAlgo:$encAlgo'
          ':@bob:kryz.kryz_9850@alice {"stationName":"KRYZ","frequency":"98.5 Mhz"}';
      var updateVerbParams = getVerbParams(VerbSyntax.update, updateCommand);
      expect(updateVerbParams[AtConstants.ttl], '-1');
      expect(updateVerbParams[AtConstants.ttr], '-1');
      expect(updateVerbParams[AtConstants.atKey], 'kryz.kryz_9850');
      expect(updateVerbParams[AtConstants.atSign], 'alice');
      expect(updateVerbParams[AtConstants.forAtSign], 'bob');
      expect(updateVerbParams[AtConstants.encryptingKeyName], encKeyName);
      expect(updateVerbParams[AtConstants.encryptingAlgo], encAlgo);
      expect(updateVerbParams[AtConstants.ivOrNonce], null);
    });
    test(
        'Validate the update:meta command when encKeyName, encAlgo and ivNonce are set',
        () {
      var encKeyName = 'some_symmetric_key_name.some_app_namespace';
      var encAlgo = 'AES/SIC/PKCS7Padding';
      var ivNonce = 'ABCDEF12456';
      final updateMetaCommand = 'update:meta:@bob:kryz.kryz_9850@alice'
          ':ttl:-1:ttb:1000000:ttr:-1'
          ':dataSignature:abc:isBinary:false:isEncrypted:false'
          ':encKeyName:$encKeyName'
          ':encAlgo:$encAlgo'
          ':ivNonce:$ivNonce';
      var updateMetaVerbParams =
          getVerbParams(VerbSyntax.update_meta, updateMetaCommand);
      expect(updateMetaVerbParams[AtConstants.ttl], '-1');
      expect(updateMetaVerbParams[AtConstants.ttr], '-1');
      expect(updateMetaVerbParams[AtConstants.atKey], 'kryz.kryz_9850');
      expect(updateMetaVerbParams[AtConstants.atSign], 'alice');
      expect(updateMetaVerbParams[AtConstants.forAtSign], 'bob');
      expect(updateMetaVerbParams[AtConstants.encryptingKeyName], encKeyName);
      expect(updateMetaVerbParams[AtConstants.encryptingAlgo], encAlgo);
      expect(updateMetaVerbParams[AtConstants.ivOrNonce], ivNonce);
    });
    test('validate update command with negative ttl and ttr', () {
      final updateCommand =
          'update:ttl:-1:ttr:-1:dataSignature:abc:isBinary:false:isEncrypted:false:public:kryz.kryz_9850@kryz_9850 {"stationName":"KRYZ","frequency":"98.5 Mhz"}';
      var actualVerbParams = getVerbParams(VerbSyntax.update, updateCommand);
      expect(actualVerbParams[AtConstants.ttl], '-1');
      expect(actualVerbParams[AtConstants.ttr], '-1');
      expect(actualVerbParams[AtConstants.atKey], 'kryz.kryz_9850');
      expect(actualVerbParams[AtConstants.atSign], 'kryz_9850');
    });
    test('validate update command with negative ttl and ttb', () {
      final updateCommand =
          'update:ttl:-1:ttb:-1:dataSignature:abc:isBinary:false:isEncrypted:false:public:kryz.kryz_9850@kryz_9850 {"stationName":"KRYZ","frequency":"98.5 Mhz"}';
      var actualVerbParams = getVerbParams(VerbSyntax.update, updateCommand);
      expect(actualVerbParams[AtConstants.ttl], '-1');
      expect(actualVerbParams[AtConstants.ttb], '-1');
      expect(actualVerbParams[AtConstants.atKey], 'kryz.kryz_9850');
      expect(actualVerbParams[AtConstants.atSign], 'kryz_9850');
    });
    test('validate update meta command with negative ttl and ttr', () {
      final updateCommand =
          'update:meta:public:kryz.kryz_9850@kryz_9850:ttl:-1:ttr:-1';
      var actualVerbParams =
          getVerbParams(VerbSyntax.update_meta, updateCommand);
      expect(actualVerbParams[AtConstants.ttl], '-1');
      expect(actualVerbParams[AtConstants.ttr], '-1');
      expect(actualVerbParams[AtConstants.atKey], 'kryz.kryz_9850');
      expect(actualVerbParams[AtConstants.atSign], 'kryz_9850');
    });
    test('validate update meta command with negative ttl and ttb', () {
      final updateCommand =
          'update:meta:public:kryz.kryz_9850@kryz_9850:ttl:-1:ttb:-1';
      var actualVerbParams =
          getVerbParams(VerbSyntax.update_meta, updateCommand);
      expect(actualVerbParams[AtConstants.ttl], '-1');
      expect(actualVerbParams[AtConstants.ttb], '-1');
      expect(actualVerbParams[AtConstants.atKey], 'kryz.kryz_9850');
      expect(actualVerbParams[AtConstants.atSign], 'kryz_9850');
    });
  });

  group('A group of negative test on update verb regex', () {
    test('update verb with encoding value not specified', () {
      var command = 'update:encoding:@alice:phone@bob 123';
      expect(
          () => getVerbParams(VerbSyntax.update, command),
          throwsA(predicate((dynamic e) =>
              e is InvalidSyntaxException &&
              e.message == 'command does not match the regex')));
    });

    test(
        'test to verify local key with isPublic set to true throws invalid atkey exception',
        () {
      var updateVerbBuilder = UpdateVerbBuilder()
        ..atKey.metadata.isPublic = true
        ..atKey.isLocal = true
        ..atKey.key = 'phone'
        ..atKey.sharedBy = '@bob';

      expect(
          () => updateVerbBuilder.buildCommand(),
          throwsA(predicate((dynamic e) =>
              e is InvalidAtKeyException &&
              e.message ==
                  'When isLocal is set to true, cannot set isPublic to true or set a non-null sharedWith')));
    });

    test(
        'test to verify local key with sharedWith populated throws invalid atkey exception',
        () {
      expect(() {
        UpdateVerbBuilder()
          ..atKey.isLocal = true
          ..atKey.sharedWith = '@alice'
          ..atKey.key = 'phone'
          ..atKey.sharedBy = '@bob';
      },
          throwsA(predicate((dynamic e) =>
              e is InvalidAtKeyException &&
              e.message ==
                  'isLocal or isPublic cannot be true when sharedWith is set')));
    });

    test(
        'test to verify isPublic set to true with sharedWith populated throws invalid atkey exception',
        () {
      expect(() {
        UpdateVerbBuilder()
          ..atKey.metadata.isPublic = true
          ..atKey.sharedWith = '@alice'
          ..atKey.key = 'phone'
          ..atKey.sharedBy = '@bob';
      },
          throwsA(predicate((dynamic e) =>
              e is InvalidAtKeyException &&
              e.message ==
                  'isLocal or isPublic cannot be true when sharedWith is set')));
    });

    test('test to verify Key cannot be null or empty', () {
      var updateVerbBuilder = UpdateVerbBuilder()
        ..atKey.sharedWith = '@alice'
        ..atKey.key = ''
        ..atKey.sharedBy = '@bob';

      expect(
          () => updateVerbBuilder.buildCommand(),
          throwsA(predicate((dynamic e) =>
              e is InvalidAtKeyException &&
              e.message == 'Key cannot be null or empty')));
    });

    test(
        'A key with local is set and then sharedWith is set which throws exception',
        () {
      var updateVerbBuilder = UpdateVerbBuilder()
        ..atKey.key = 'phone'
        ..atKey.isLocal = true
        ..atKey.sharedBy = '@bob'
        ..value = '+445 334 3423';
      var command = updateVerbBuilder.buildCommand();
      expect(
          command, 'update:isEncrypted:false:local:phone@bob +445 334 3423\n');
      expect(() => updateVerbBuilder.atKey.sharedWith = '@alice',
          throwsA(predicate((dynamic e) => e is InvalidAtKeyException)));
    });
  });

  group('A group of tests to validate the buildKey', () {
    // The privatekey:<key> is used to insert the pkam keys
    test('privatekey assigned to atKey.key', () {
      var updateVerbBuilder = UpdateVerbBuilder()
        ..atKey.key = 'privatekey:at_private_key';
      expect(updateVerbBuilder.buildKey(), 'privatekey:at_private_key');
    });

    test('test to verify sharedWith is set to null on a local key', () {
      var updateVerbBuilder = UpdateVerbBuilder()
        ..atKey.key = 'phone'
        ..atKey.sharedBy = '@alice'
        ..atKey.isLocal = true;
      expect(updateVerbBuilder.buildKey(), 'local:phone@alice');
      updateVerbBuilder.atKey.sharedWith = null;
      expect(updateVerbBuilder.buildKey(), 'local:phone@alice');
    });

    test('test to verify sharedWith is set to null on a public key', () {
      var updateVerbBuilder = UpdateVerbBuilder()
        ..atKey.key = 'phone'
        ..atKey.sharedBy = '@alice'
        ..atKey.metadata.isPublic = true;
      expect(updateVerbBuilder.buildKey(), 'public:phone@alice');
      expect(updateVerbBuilder.atKey.sharedWith, null);
      updateVerbBuilder.atKey.sharedWith = null;
      expect(updateVerbBuilder.buildKey(), 'public:phone@alice');
    });

    UpdateVerbBuilder createBuilderWithAllMetadata({
      String? sharedWithOrPublic,
      required bool immutable,
    }) {
      var ttl = 12345;
      var ttb = 54321;
      var ccd = false;
      var ttr = 1000;
      var dataSignature = 'someDataSignature';
      var sharedKeyStatus = SharedKeyStatus.localUpdated.name;
      var sharedKeyEncrypted = 'xyz123abc456';
      var pubKeyChecksum = 'the_checksum';
      var encoding = 'some_encoding';
      var encKeyName = 'some_enc_key_name';
      var encAlgo = 'some_enc_algo';
      var ivNonce = 'some_iv_or_nonce';
      var skeEncKeyName = 'some_ske_enc_key_name';
      var skeEncAlgo = 'some_ske_enc_algo';
      var isBinary = true;
      var isEncrypted = true;
      return UpdateVerbBuilder()
        ..atKey.key = 'phone.details.wavi'
        ..atKey.sharedBy = '@alice'
        ..atKey.sharedWith =
            sharedWithOrPublic == 'public' ? null : sharedWithOrPublic
        ..atKey.metadata.isPublic = (sharedWithOrPublic == 'public')
        ..atKey.metadata.ttl = ttl
        ..atKey.metadata.ttb = ttb
        ..atKey.metadata.ccd = ccd
        ..atKey.metadata.ttr = ttr
        ..atKey.metadata.dataSignature = dataSignature
        ..atKey.metadata.sharedKeyStatus = sharedKeyStatus
        ..atKey.metadata.isBinary = isBinary
        ..atKey.metadata.isEncrypted = isEncrypted
        ..atKey.metadata.sharedKeyEnc = sharedKeyEncrypted
        // ignore: deprecated_member_use_from_same_package
        ..atKey.metadata.pubKeyCS = pubKeyChecksum
        ..atKey.metadata.encoding = encoding
        ..atKey.metadata.encKeyName = encKeyName
        ..atKey.metadata.encAlgo = encAlgo
        ..atKey.metadata.ivNonce = ivNonce
        ..atKey.metadata.skeEncKeyName = skeEncKeyName
        ..atKey.metadata.skeEncAlgo = skeEncAlgo
        ..atKey.metadata.immutable = immutable
        ..value = 'HELLO_WORLD';
    }

    group(
        'A group of tests to verify round-tripping of update commands from buildCommand and getBuilder',
        () {
      UpdateVerbBuilder roundTripUpdateTest({
        required String? sharedWithOrPublic,
        required bool immutable,
      }) {
        var initialBuilder = createBuilderWithAllMetadata(
          sharedWithOrPublic: sharedWithOrPublic,
          immutable: immutable,
        );
        var command = initialBuilder.buildCommand();
        var roundTrippedBuilder = UpdateVerbBuilder.getBuilder(command.trim());
        expect(initialBuilder == roundTrippedBuilder, true);
        return roundTrippedBuilder!;
      }

      test(
          'verify round trip from builder, to command for update, back to builder, for public key',
          () {
        var roundTrippedBuilder = roundTripUpdateTest(
          sharedWithOrPublic: 'public',
          immutable: false,
        );
        expect(roundTrippedBuilder.atKey.metadata.isPublic, true);
        expect(roundTrippedBuilder.atKey.metadata.immutable, false);
        roundTrippedBuilder = roundTripUpdateTest(
          sharedWithOrPublic: 'public',
          immutable: true,
        );
        expect(roundTrippedBuilder.atKey.metadata.isPublic, true);
        expect(roundTrippedBuilder.atKey.metadata.immutable, true);
      });

      test(
          'verify round trip from builder, to command for update, back to builder, for shared key',
          () {
        var roundTrippedBuilder = roundTripUpdateTest(
          sharedWithOrPublic: '@bob',
          immutable: false,
        );
        expect(roundTrippedBuilder.atKey.metadata.isPublic, false);
        expect(roundTrippedBuilder.atKey.metadata.immutable, false);
        roundTrippedBuilder = roundTripUpdateTest(
          sharedWithOrPublic: '@bob',
          immutable: true,
        );
        expect(roundTrippedBuilder.atKey.metadata.isPublic, false);
        expect(roundTrippedBuilder.atKey.metadata.immutable, true);
      });

      test(
          'verify round trip from builder, to command for update, back to builder, for self key',
          () {
        var roundTrippedBuilder = roundTripUpdateTest(
          sharedWithOrPublic: null,
          immutable: false,
        );
        expect(roundTrippedBuilder.atKey.metadata.isPublic, false);
        expect(roundTrippedBuilder.atKey.metadata.immutable, false);
        roundTrippedBuilder = roundTripUpdateTest(
          sharedWithOrPublic: null,
          immutable: true,
        );
        expect(roundTrippedBuilder.atKey.metadata.isPublic, false);
        expect(roundTrippedBuilder.atKey.metadata.immutable, true);
      });

      UpdateVerbBuilder roundTripUpdateMetaTest({
        required String? sharedWithOrPublic,
        required bool immutable,
      }) {
        var initialBuilder = createBuilderWithAllMetadata(
          sharedWithOrPublic: sharedWithOrPublic,
          immutable: immutable,
        );
        initialBuilder.operation = AtConstants.updateMeta;

        // When the update:meta command is built, it will NOT include the value, so
        // we'll make two assertions: (1) builder after round-tripping via buildCommandForMeta()
        // will NOT be the same as the initial builder, and (2) builder after round-tripping via
        // buildCommandForMeta() WILL be the same as the initial builder, if the `value` in the
        // initial builder is set to null
        var command = initialBuilder.buildCommandForMeta();
        var roundTrippedBuilder = UpdateVerbBuilder.getBuilder(command.trim());
        expect(initialBuilder == roundTrippedBuilder, false);

        initialBuilder.value = null;
        expect(initialBuilder == roundTrippedBuilder, true);

        return roundTrippedBuilder!;
      }

      test(
          'verify round trip from builder, to command for update meta, back to builder, for public key',
          () {
        var roundTrippedBuilder = roundTripUpdateMetaTest(
          sharedWithOrPublic: 'public',
          immutable: false,
        );
        expect(roundTrippedBuilder.atKey.metadata.isPublic, true);
        expect(roundTrippedBuilder.atKey.metadata.immutable, false);

        roundTrippedBuilder = roundTripUpdateMetaTest(
          sharedWithOrPublic: 'public',
          immutable: true,
        );
        expect(roundTrippedBuilder.atKey.metadata.isPublic, true);
        expect(roundTrippedBuilder.atKey.metadata.immutable, true);
      });
      test(
          'verify round trip from builder, to command for update meta, back to builder, for shared key',
          () {
        var roundTrippedBuilder = roundTripUpdateMetaTest(
          sharedWithOrPublic: '@bob',
          immutable: false,
        );
        expect(roundTrippedBuilder.atKey.metadata.isPublic, false);
        expect(roundTrippedBuilder.atKey.metadata.immutable, false);
        roundTrippedBuilder = roundTripUpdateMetaTest(
          sharedWithOrPublic: '@bob',
          immutable: true,
        );
        expect(roundTrippedBuilder.atKey.metadata.isPublic, false);
        expect(roundTrippedBuilder.atKey.metadata.immutable, true);
      });
      test(
          'verify round trip from builder, to command for update meta, back to builder, for self key',
          () {
        var roundTrippedBuilder = roundTripUpdateMetaTest(
          sharedWithOrPublic: null,
          immutable: false,
        );
        expect(roundTrippedBuilder.atKey.metadata.isPublic, false);
        expect(roundTrippedBuilder.atKey.metadata.immutable, false);
        roundTrippedBuilder = roundTripUpdateMetaTest(
          sharedWithOrPublic: null,
          immutable: true,
        );
        expect(roundTrippedBuilder.atKey.metadata.isPublic, false);
        expect(roundTrippedBuilder.atKey.metadata.immutable, true);
      });
    });
  });
  group('A group of tests to validate isEncrypted flag in update verb builder',
      () {
    test('for public key isEncrypted is false', () {
      var updateBuilder = UpdateVerbBuilder()
        ..value = 'alice@gmail.com'
        ..atKey.metadata.isPublic = true
        ..atKey.metadata.ttl = 5000
        ..atKey.key = 'email'
        ..atKey.sharedBy = '@alice';
      var updateCommand = updateBuilder.buildCommand();
      expect(updateCommand,
          'update:ttl:5000:isEncrypted:false:public:email@alice alice@gmail.com\n');
      var updateVerbParams =
          getVerbParams(VerbSyntax.update, updateCommand.trim());
      print(updateVerbParams);
      expect(updateVerbParams['isEncrypted'], 'false');
    });
    test('for shared key - isEncrypted is true if set in metadata', () {
      var updateBuilder = UpdateVerbBuilder()
        ..value = 'sampleEncryptedValue'
        ..atKey.metadata.ttl = 5000
        ..atKey.metadata.isEncrypted = true
        ..atKey.key = 'email'
        ..atKey.sharedBy = '@alice'
        ..atKey.sharedWith = '@bob';
      var updateCommand = updateBuilder.buildCommand();
      print(updateCommand);
      expect(updateCommand,
          'update:ttl:5000:isEncrypted:true:@bob:email@alice sampleEncryptedValue\n');
      var updateVerbParams =
          getVerbParams(VerbSyntax.update, updateCommand.trim());
      print(updateVerbParams);
      expect(updateVerbParams['isEncrypted'], 'true');
    });
    test('for shared key - isEncrypted is false if NOT set in metadata', () {
      var updateBuilder = UpdateVerbBuilder()
        ..value = 'sampleEncryptedValue'
        ..atKey.metadata.ttl = 5000
        ..atKey.key = 'email'
        ..atKey.sharedBy = '@alice'
        ..atKey.sharedWith = '@bob';
      var updateCommand = updateBuilder.buildCommand();
      print(updateCommand);
      expect(updateCommand,
          'update:ttl:5000:isEncrypted:false:@bob:email@alice sampleEncryptedValue\n');
      var updateVerbParams =
          getVerbParams(VerbSyntax.update, updateCommand.trim());
      print(updateVerbParams);
      expect(updateVerbParams['isEncrypted'], 'false');
    });

    test('for shared key - isEncrypted is false if set to false in metadata',
        () {
      var updateBuilder = UpdateVerbBuilder()
        ..value = 'sampleEncryptedValue'
        ..atKey.metadata.ttl = 5000
        ..atKey.metadata.isEncrypted = false
        ..atKey.key = 'email'
        ..atKey.sharedBy = '@alice'
        ..atKey.sharedWith = '@bob';
      var updateCommand = updateBuilder.buildCommand();
      print(updateCommand);
      expect(updateCommand,
          'update:ttl:5000:isEncrypted:false:@bob:email@alice sampleEncryptedValue\n');
      var updateVerbParams =
          getVerbParams(VerbSyntax.update, updateCommand.trim());
      print(updateVerbParams);
      expect(updateVerbParams['isEncrypted'], 'false');
    });
  });
}
