import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests to verify key types', () {
    test('Test to verify a public key type with namespace', () {
      var keyType = AtKey.getKeyType('public:phone.wavi@bob');
      expect(keyType, equals(KeyType.publicKey));
    });

    test('Test to verify a cached public key type with namespace', () {
      var keyType = AtKey.getKeyType('cached:public:phone.buzz@bob');
      expect(keyType, equals(KeyType.cachedPublicKey));
    });

    test('Test to verify a shared key type with namespace', () {
      var keyType = AtKey.getKeyType('@alice:phone.wavi@bob');
      expect(keyType, equals(KeyType.sharedKey));
    });

    test('Test to verify a cached shared key type with namespace', () {
      var keyType = AtKey.getKeyType('cached:@alice:phone.buzz@bob');
      expect(keyType, equals(KeyType.cachedSharedKey));
    });

    test('Test to verify self key type with namespace', () {
      var keyType = AtKey.getKeyType('@bob:phone.buzz@bob');
      expect(keyType, equals(KeyType.selfKey));
    });

    test('Test to verify local key type with namespace', () {
      var keyType = AtKey.getKeyType('local:latestNotification.wavi@bob',
          enforceNameSpace: true);
      expect(keyType, equals(KeyType.localKey));
    });
  });

  group('A group of tests to check invalid key types', () {
    test('Test public key type without namespace', () {
      var keyType =
          AtKey.getKeyType('public:phone@bob', enforceNameSpace: true);
      expect(keyType, equals(KeyType.invalidKey));
    });

    test('Test cached public key type without namespace', () {
      var keyType =
          AtKey.getKeyType('cached:public:phone@bob', enforceNameSpace: true);
      expect(keyType, equals(KeyType.invalidKey));
    });

    test('Test shared key type without namespace', () {
      var keyType =
          AtKey.getKeyType('@alice:phone@bob', enforceNameSpace: true);
      expect(keyType, equals(KeyType.invalidKey));
    });

    test('Test cached shared key type without namespace', () {
      var keyType =
          AtKey.getKeyType('cached:@alice:phone@bob', enforceNameSpace: true);
      expect(keyType, equals(KeyType.invalidKey));
    });

    test('Test self key type without sharedWith atsign and without namespace',
        () {
      var keyType = AtKey.getKeyType('phone@bob', enforceNameSpace: true);
      expect(keyType, equals(KeyType.invalidKey));
    });

    test('Test self key type with atsign and without namespace', () {
      var keyType = AtKey.getKeyType('@bob:phone@bob', enforceNameSpace: true);
      expect(keyType, equals(KeyType.invalidKey));
    });

    test('Test local key type with atsign and without namespace', () {
      var keyType = AtKey.getKeyType('local:phone@bob', enforceNameSpace: true);
      expect(keyType, equals(KeyType.invalidKey));
    });

    test(
        'Test malformed key cached:public:cached:public:privateaccount.wavi@dying36dragonfly',
        () {
      var keyType = AtKey.getKeyType(
          'cached:public:cached:public:privateaccount.wavi@dying36dragonfly',
          enforceNameSpace: false);
      expect(keyType, equals(KeyType.invalidKey));
    });

    test('Test malformed key public:@public:image.wavi@colin', () {
      var keyType = AtKey.getKeyType('public:@public:image.wavi@colin',
          enforceNameSpace: false);
      expect(keyType, equals(KeyType.invalidKey));
    });
  });

  group('A group of tests to check reserved key types', () {
    test('A positive test to validate reserved key type', () {
      var keyTypeList = [];
      var fails = [];
      // keys with atsign
      keyTypeList.add('shared_key.bob@alice');
      keyTypeList.add('@bob:shared_key@alice');
      keyTypeList.add('${AtConstants.atBlocklist}@☎️_0002');
      keyTypeList.add('@allen:${AtConstants.atSigningPrivateKey}@allen');
      keyTypeList.add('${AtConstants.atEncryptionPublicKey}@owner');
      keyTypeList.add('public:signing_publickey@alice');
      keyTypeList.add('public:signing_publickey@☎️_0002');
      // keys without atsign
      keyTypeList.add(AtConstants.atPkamPublicKey);
      keyTypeList.add(AtConstants.atPkamPrivateKey);
      keyTypeList.add(AtConstants.atEncryptionPrivateKey);
      keyTypeList.add(AtConstants.atEncryptionSelfKey);
      keyTypeList.add(AtConstants.atCramSecret);
      keyTypeList.add(AtConstants.atCramSecretDeleted);
      keyTypeList.add(AtConstants.atSigningKeypairGenerated);
      keyTypeList.add(AtConstants.commitLogCompactionKey);
      keyTypeList.add(AtConstants.accessLogCompactionKey);
      keyTypeList.add(AtConstants.notificationCompactionKey);
      keyTypeList.add('configkey');
      keyTypeList.add('_latestNotificationIdv2');

      for (var key in keyTypeList) {
        var type = RegexUtil.keyType(key, false);
        print(key);
        if (type != KeyType.reservedKey) {
          fails.add('$key classified as $type - should be reservedKey');
        }
      }
      expect(fails, []);
    });

    test('Validate no false positives for reserved keys with atsign', () {
      var keyTypeList = [];
      var fails = [];
      // these keys are supposed to have an atsign at the end
      // to test a negative case, the @atsign at the end has been removed
      keyTypeList.add('public:publickey');
      keyTypeList.add('public:signing_publickey');
      keyTypeList.add(AtConstants.atBlocklist);
      keyTypeList.add('@bob:shared_key');
      keyTypeList.add('shared_key.bob');
      keyTypeList.add(AtConstants.atEncryptionSharedKey);
      keyTypeList.add('@allen:${AtConstants.atSigningPrivateKey}');
      keyTypeList.add(AtConstants.atSigningPrivateKey);

      for (var key in keyTypeList) {
        var type = RegexUtil.keyType(key, false);
        if (type == KeyType.reservedKey) {
          fails.add('got $type for $key - which is not a reserved key');
        }
      }
      expect(fails, []);
    });

    test('Validate no false positives for reserved keys without atsign', () {
      var keysList = [];
      var fails = [];
      // the following keys are not supposed to have an atsign at the end
      // for the sake of testing a negative case, atsigns have been appended
      // to the keys
      keysList.add('${AtConstants.atPkamPublicKey}@alice123');
      keysList.add('${AtConstants.atPkamPrivateKey}@alice123');
      keysList.add('${AtConstants.atEncryptionPrivateKey}@alice123');
      keysList.add('${AtConstants.atEncryptionSelfKey}@alice123');
      keysList.add('${AtConstants.atCramSecret}@alice123');
      keysList.add('${AtConstants.atCramSecretDeleted}@alice123');
      keysList.add('${AtConstants.atSigningKeypairGenerated}@alice123');
      keysList.add('${AtConstants.commitLogCompactionKey}@alice123');
      keysList.add('${AtConstants.accessLogCompactionKey}@alice123');
      keysList.add('${AtConstants.notificationCompactionKey}@alice123');
      keysList.add('configkey@alice123');
      keysList.add('_latestNotificationIdv2@client');

      for (var key in keysList) {
        var type = RegexUtil.keyType(key, false);
        if (type == KeyType.reservedKey) {
          fails.add('got $type for $key - which is not a reserved key');
        }
      }
      expect(fails, []);
    });

    test(
        'Validate no false positives for reserved keys with incorrect visibility',
        () {
      var keysList = [];
      var fails = [];
      // negative test to validate that e.g. only public:publickey@owner is a
      // reserved key. @owner:publickey@owner is NOT a reserved key
      keysList.add('public:blocklist@☎️_0002');
      keysList.add('public:shared_key@alice');
      keysList.add('public:signing_privatekey@allen');
      keysList.add('☎️@owner:publickey@owner');
      keysList.add('@alice:signing_publickey@alice');
      keysList.add('@☎️_0002:signing_publickey@☎️_0002');
      keysList.add('public:at_pkam_publickey');
      keysList.add('public:at_pkam_privatekey');
      keysList.add('public:privatekey');
      keysList.add('public:self_encryption_key');
      keysList.add('public:at_secret');
      keysList.add('public:at_secret_deleted');
      keysList.add('public:signing_keypair_generated');
      keysList.add('public:commitLogCompactionStats');
      keysList.add('public:accessLogCompactionStats');
      keysList.add('public:notificationCompactionStats');
      keysList.add('privatekey:configkey');
      keysList.add('privatekey:_latestNotificationIdv2');

      for (var key in keysList) {
        var type = RegexUtil.keyType(key, false);
        if (type == KeyType.reservedKey) {
          fails.add('got $type for $key - which is not a reserved key');
        }
      }
      expect(fails, []);
    });

    test('Ensure public hidden keys should NOT be classified as reserved keys',
        () {
      var keyType = AtKey.getKeyType(
          'public:__secretKey@cia', //double underscore after 'public:'
          enforceNameSpace: false);
      expect(keyType, isNot(KeyType.reservedKey));
      expect(keyType, KeyType.publicKey);
    });

    test('Ensure underscore keys should NOT be classified as reserved keys',
        () {
      var keyType =
          AtKey.getKeyType('public:_secretKey@test', enforceNameSpace: false);
      expect(keyType, isNot(KeyType.reservedKey));
      expect(keyType, KeyType.publicKey);
    });
  });
}
