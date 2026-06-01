import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'syntax_test.dart';

void main() {
  group('A group of notify verb builder tests to check notify command', () {
    test('notify without namespace', () {
      final nvb = NotifyVerbBuilder()
        ..id = '123'
        ..value = 'foo'
        ..atKey.key = 'foo'
        ..atKey.sharedWith = '@bob'
        ..atKey.sharedBy = '@alice';
      expect(nvb.buildCommand(),
          'notify:id:123:notifier:SYSTEM:isEncrypted:false:@bob:foo@alice:foo\n');
    });

    test('notify with namespace', () {
      final nvb = NotifyVerbBuilder()
        ..useAtKeyToString = true
        ..id = '123'
        ..value = 'foo'
        ..atKey.key = 'foo'
        ..atKey.namespace = 'my_app'
        ..atKey.sharedWith = '@bob'
        ..atKey.sharedBy = '@alice';
      expect(nvb.buildCommand(),
          'notify:id:123:notifier:SYSTEM:isEncrypted:false:@bob:foo.my_app@alice:foo\n');
    });

    test('notify without namespace using atKey toString', () {
      final nvb = NotifyVerbBuilder()
        ..id = '123'
        ..value = 'foo'
        ..atKey = AtKey.fromString('@bob:foo@alice');
      expect(nvb.buildCommand(),
          'notify:id:123:notifier:SYSTEM:isEncrypted:false:@bob:foo@alice:foo\n');
    });

    test('notify with namespace using atKey toString', () {
      final nvb = NotifyVerbBuilder()
        ..useAtKeyToString = true
        ..id = '123'
        ..value = 'foo'
        ..atKey = AtKey.fromString('@bob:foo.my_app@alice');
      expect(nvb.buildCommand(),
          'notify:id:123:notifier:SYSTEM:isEncrypted:false:@bob:foo.my_app@alice:foo\n');
    });

    test('notify public key', () {
      var notifyVerbBuilder = NotifyVerbBuilder()
        ..id = '123'
        ..value = 'alice@gmail.com'
        ..atKey.metadata.isPublic = true
        ..atKey.key = 'email'
        ..atKey.sharedBy = '@alice'
        ..ttln = 100;
      var command = notifyVerbBuilder.buildCommand();
      expect(command,
          'notify:id:123:notifier:SYSTEM:ttln:100:isEncrypted:false:public:email@alice:alice@gmail.com\n');
      var params = VerbUtil.getVerbParam(VerbSyntax.notify, command.trim())!;
      expect(params.length, 8);
      expect(params[AtConstants.id], '123');
      expect(params[AtConstants.value], 'alice@gmail.com');
      expect(params[AtConstants.publicScopeParam], 'public');
      expect(params[AtConstants.atKey], 'email');
      expect(params[AtConstants.atSign], 'alice');
      expect(params[AtConstants.notifier], 'SYSTEM');
      expect(params[AtConstants.ttlNotification], '100');
    });

    test('notify public key with ttl', () {
      var notifyVerbBuilder = NotifyVerbBuilder()
        ..id = '123'
        ..value = 'alice@gmail.com'
        ..atKey.metadata.isPublic = true
        ..atKey.key = 'email'
        ..atKey.sharedBy = '@alice'
        ..atKey.metadata.ttl = 1000;
      var command = notifyVerbBuilder.buildCommand();
      expect(command,
          'notify:id:123:notifier:SYSTEM:ttl:1000:isEncrypted:false:public:email@alice:alice@gmail.com\n');
      var params = VerbUtil.getVerbParam(VerbSyntax.notify, command.trim())!;
      expect(params.length, 8);
      expect(params[AtConstants.id], '123');
      expect(params[AtConstants.value], 'alice@gmail.com');
      expect(params[AtConstants.publicScopeParam], 'public');
      expect(params[AtConstants.atKey], 'email');
      expect(params[AtConstants.atSign], 'alice');
      expect(params[AtConstants.ttl], '1000');
      expect(params[AtConstants.notifier], 'SYSTEM');
    });

    test('notify shared key command', () {
      var notifyVerbBuilder = NotifyVerbBuilder()
        ..id = '123'
        ..value = 'alice@atsign.com'
        ..atKey.key = 'email'
        ..atKey.sharedBy = '@alice'
        ..atKey.sharedWith = '@bob'
        // ignore: deprecated_member_use_from_same_package
        ..atKey.metadata.pubKeyCS = '123'
        ..atKey.metadata.sharedKeyEnc = 'abc'
        ..atKey.metadata.isEncrypted = true
        ..ttln = 100;
      var command = notifyVerbBuilder.buildCommand();
      expect(command,
          'notify:id:123:notifier:SYSTEM:ttln:100:isEncrypted:true:sharedKeyEnc:abc:pubKeyCS:123:@bob:email@alice:alice@atsign.com\n');
      var params = VerbUtil.getVerbParam(VerbSyntax.notify, command.trim())!;
      expect(params.length, 10);
      expect(params[AtConstants.id], '123');
      expect(params[AtConstants.value], 'alice@atsign.com');
      expect(params[AtConstants.atKey], 'email');
      expect(params[AtConstants.atSign], 'alice');
      expect(params[AtConstants.forAtSign], 'bob');
      expect(params[AtConstants.notifier], 'SYSTEM');
      expect(params[AtConstants.sharedWithPublicKeyCheckSum], '123');
      expect(params[AtConstants.sharedKeyEncrypted], 'abc');
    });

    test('notify text message with isEncrypted set to true', () {
      var notifyVerbBuilder = NotifyVerbBuilder()
        ..id = '123'
        ..value = 'alice@atsign.com'
        ..atKey.key = 'email'
        ..atKey.sharedBy = '@alice'
        ..atKey.sharedWith = '@bob'
        // ignore: deprecated_member_use_from_same_package
        ..atKey.metadata.pubKeyCS = '123'
        ..atKey.metadata.sharedKeyEnc = 'abc'
        ..atKey.metadata.isEncrypted = true;
      var command = notifyVerbBuilder.buildCommand();
      expect(command,
          'notify:id:123:notifier:SYSTEM:isEncrypted:true:sharedKeyEnc:abc:pubKeyCS:123:@bob:email@alice:alice@atsign.com\n');
      var params = VerbUtil.getVerbParam(VerbSyntax.notify, command.trim())!;
      expect(params.length, 9);
      expect(params[AtConstants.publicScopeParam], null);
      expect(params[AtConstants.id], '123');
      expect(params[AtConstants.value], 'alice@atsign.com');
      expect(params[AtConstants.atKey], 'email');
      expect(params[AtConstants.atSign], 'alice');
      expect(params[AtConstants.forAtSign], 'bob');
      expect(params[AtConstants.notifier], 'SYSTEM');
      expect(params[AtConstants.isEncrypted], 'true');
      expect(params[AtConstants.sharedWithPublicKeyCheckSum], '123');
      expect(params[AtConstants.sharedKeyEncrypted], 'abc');
    });

    test('notify with every piece of encryption metadata', () {
      var notifyVerbBuilder = NotifyVerbBuilder()
        ..id = '123'
        ..value = 'alice@atsign.com'
        ..atKey.key = 'email'
        ..atKey.sharedBy = '@alice'
        ..atKey.sharedWith = '@bob'
        // ignore: deprecated_member_use_from_same_package
        ..atKey.metadata.pubKeyCS = '123'
        ..atKey.metadata.sharedKeyEnc = 'abc'
        ..atKey.metadata.encKeyName = 'ekn'
        ..atKey.metadata.encAlgo = 'ea'
        ..atKey.metadata.ivNonce = 'ivn'
        ..atKey.metadata.skeEncKeyName = 'ske_ekn'
        ..atKey.metadata.skeEncAlgo = 'ske_ea'
        ..atKey.metadata.isEncrypted = true;
      var command = notifyVerbBuilder.buildCommand();
      expect(
          command,
          'notify:id:123:notifier:SYSTEM:isEncrypted:true'
          ':sharedKeyEnc:abc:pubKeyCS:123'
          ':encKeyName:ekn:encAlgo:ea:ivNonce:ivn'
          ':skeEncKeyName:ske_ekn:skeEncAlgo:ske_ea'
          ':@bob:email@alice:alice@atsign.com\n');
      var params = VerbUtil.getVerbParam(VerbSyntax.notify, command.trim())!;
      expect(params.length, 14);
      expect(params[AtConstants.publicScopeParam], null);
      expect(params[AtConstants.id], '123');
      expect(params[AtConstants.value], 'alice@atsign.com');
      expect(params[AtConstants.atKey], 'email');
      expect(params[AtConstants.atSign], 'alice');
      expect(params[AtConstants.forAtSign], 'bob');
      expect(params[AtConstants.notifier], 'SYSTEM');
      expect(params[AtConstants.sharedWithPublicKeyCheckSum], '123');
      expect(params[AtConstants.sharedKeyEncrypted], 'abc');
      expect(params[AtConstants.encryptingKeyName], 'ekn');
      expect(params[AtConstants.encryptingAlgo], 'ea');
      expect(params[AtConstants.ivOrNonce], 'ivn');
      expect(
          params[AtConstants.sharedKeyEncryptedEncryptingKeyName], 'ske_ekn');
      expect(params[AtConstants.sharedKeyEncryptedEncryptingAlgo], 'ske_ea');
    });

    test('notify command with app metadata', () {
      final appMetadata = AppMetadata('test_provider', additional: {
        'encKeyName': 'key_12345.__shared_keys.wavi',
        'encAlgo': 'test_algo',
      });
      final encodedAppMetadata = Metadata.encodeAppMetadata(appMetadata);

      var notifyVerbBuilder = NotifyVerbBuilder()
        ..id = '123'
        ..value = 'alice@atsign.com'
        ..atKey.key = 'email.wavi'
        ..atKey.sharedBy = '@alice'
        ..atKey.sharedWith = '@bob'
        ..atKey.metadata.appMetadata = appMetadata;

      var command = notifyVerbBuilder.buildCommand();
      expect(command, contains(':appMetadata:$encodedAppMetadata'));

      var params = VerbUtil.getVerbParam(VerbSyntax.notify, command.trim())!;
      expect(params[AtConstants.appMetadata], encodedAppMetadata);
      expect(Metadata.decodeAppMetadata(params[AtConstants.appMetadata]),
          appMetadata);
    });
  });

  try {
    group('A group of tests to verify notification id generation', () {
      // The below test validates the following:
      //  1. custom notification id overrides default notification id
      //  2. IsEncrypted flag when set true is added to verb params.
      test('Test to verify all notify fields in the verb builder', () {
        var verbHandler = NotifyVerbBuilder()
          ..id = 'abc-123'
          ..atKey.key = 'phone'
          ..atKey.sharedWith = '@alice'
          ..atKey.sharedBy = '@bob'
          ..atKey.metadata.isEncrypted = true;

        var notifyCommand = verbHandler.buildCommand();
        var verbParams = getVerbParams(VerbSyntax.notify, notifyCommand.trim());
        expect(verbParams[AtConstants.id], 'abc-123');
        expect(verbParams[AtConstants.isEncrypted], 'true');
      });

      // The below test validates the following:
      //  1. Default notification id is generated
      //  2. IsEncrypted flag is not set by default.
      test('Test to verify default notification id is generated', () {
        var verbHandler = NotifyVerbBuilder()
          ..atKey.key = 'phone'
          ..atKey.sharedWith = '@alice'
          ..atKey.sharedBy = '@bob';

        var notifyCommand = verbHandler.buildCommand();
        var verbParams = getVerbParams(VerbSyntax.notify, notifyCommand.trim());
        expect(verbParams[AtConstants.id] != null, true);
        expect(verbParams[AtConstants.isEncrypted], 'false');
      });
      test('Test to verify custom set notification id to verb builder', () {
        var verbHandler = NotifyVerbBuilder()
          ..id = 'abc-123'
          ..atKey.key = 'phone'
          ..atKey.sharedWith = '@alice'
          ..atKey.sharedBy = '@bob';

        var notifyCommand = verbHandler.buildCommand();
        var verbParams = getVerbParams(VerbSyntax.notify, notifyCommand.trim());
        expect(verbParams[AtConstants.id], 'abc-123');
      });
    });
  } catch (e, s) {
    print(s);
  }

  group('A group of test to validate notify fetch verb', () {
    test('Test to verify to notify:fetch', () {
      var notifyFetch = NotifyFetchVerbBuilder()..notificationId = '123';
      var notifyFetchCommand = notifyFetch.buildCommand();
      expect(notifyFetchCommand, 'notify:fetch:123\n');
      var verbParams =
          getVerbParams(VerbSyntax.notifyFetch, notifyFetchCommand.trim());
      expect(verbParams['notificationId'], '123');
    });

    test('Negative test to verify to notify:fetch when notification id not set',
        () {
      var notifyFetch = NotifyFetchVerbBuilder();
      expect(() => notifyFetch.buildCommand(),
          throwsA(predicate((dynamic e) => e is InvalidSyntaxException)));
    });

    test('Negative test to verify to notify:fetch when empty string is set',
        () {
      var notifyFetch = NotifyFetchVerbBuilder()..notificationId = '';
      expect(() => notifyFetch.buildCommand(),
          throwsA(predicate((dynamic e) => e is InvalidSyntaxException)));
    });
  });
}
