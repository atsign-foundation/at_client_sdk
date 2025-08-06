import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'test_keys.dart';

void main() {
  group('A group of tests to validate keyType', () {
    test('Tests to validate public key type, namespace mandatory', () {
      var keyTypeList = [];
      keyTypeList.add('public:phone.buzz@bob');
      keyTypeList.add('public:p.b@bob');
      keyTypeList.add('public:pho_-ne.b@bob');
      keyTypeList.add('public:phone😀.buzz@bob💙');
      keyTypeList.add('public:phone.me@bob');

      for (var key in keyTypeList) {
        var type = RegexUtil.keyType(key, true);
        expect(type == KeyType.publicKey, true);
      }
    });

    test('Tests to validate public key type, namespace not mandatory', () {
      var keyTypeList = [];
      keyTypeList.add('public:phone.buzz@bob');
      keyTypeList.add('public:phone@bob');

      keyTypeList.add('public:phone.buzz@bob');
      keyTypeList.add('public:phone@bob');

      keyTypeList.add('public:p.b@bob');
      keyTypeList.add('public:p@bob');

      keyTypeList.add('public:pho_-ne.b@bob');
      keyTypeList.add('public:pho_-ne@bob');

      keyTypeList.add('public:phone😀.buzz@bob💙');
      keyTypeList.add('public:phone😀@bob💙');

      keyTypeList.add('public:phone.me@bob');
      keyTypeList.add('public:phone@bob');

      for (var key in keyTypeList) {
        var type = RegexUtil.keyType(key, false);
        expect(type == KeyType.publicKey, true);
      }
    });

    test('Tests to validate private key types, namespace mandatory', () {
      var keyTypeList = [];
      keyTypeList.add("private:@bob:phone.buzz@bob");
      keyTypeList.add("private:phone.buzz@bob");
      keyTypeList.add("private:@bob:p.b@bob");
      keyTypeList.add("private:pho_-ne.b@bob");
      keyTypeList.add("private:@bob💙:phone😀.buzz@bob💙");

      for (var key in keyTypeList) {
        var type = RegexUtil.keyType(key, true);
        expect(type == KeyType.privateKey, true);
      }
    });

    test('Tests to validate private key types, namespace not mandatory', () {
      var keyTypeList = [];
      keyTypeList.add("private:@bob:phone.buzz@bob");
      keyTypeList.add("private:@bob:phone@bob");

      keyTypeList.add("private:phone.buzz@bob");
      keyTypeList.add("private:phone@bob");

      keyTypeList.add("private:@bob:p.b@bob");
      keyTypeList.add("private:@bob:p@bob");

      keyTypeList.add("private:pho_-ne.b@bob");
      keyTypeList.add("private:pho_-ne@bob");

      keyTypeList.add("private:@bob💙:phone😀.buzz@bob💙");
      keyTypeList.add("private:@bob💙:phone😀@bob💙");

      for (var key in keyTypeList) {
        var type = RegexUtil.keyType(key, false);
        expect(type == KeyType.privateKey, true);
      }
    });

    test('Tests to validate self key types, namespace mandatory', () {
      var keyTypeList = [];
      keyTypeList.add("@bob:phone.buzz@bob");
      keyTypeList.add("phone.buzz@bob");
      keyTypeList.add("@bob:p.b@bob");
      keyTypeList.add("pho_-ne.b@bob");
      keyTypeList.add("@bob💙:phone😀.buzz@bob💙");

      for (var key in keyTypeList) {
        var type = RegexUtil.keyType(key, true);
        expect(type == KeyType.selfKey, true);
      }
    });

    test('Tests to validate self key types, namespace not mandatory', () {
      var keyTypeList = [];
      keyTypeList.add("@bob:phone.buzz@bob");
      keyTypeList.add("@bob:phone@bob");

      keyTypeList.add("phone.buzz@bob");
      keyTypeList.add("phone@bob");

      keyTypeList.add("@bob:p.b@bob");
      keyTypeList.add("@bob:p@bob");

      keyTypeList.add("pho_-ne.b@bob");
      keyTypeList.add("pho_-ne@bob");

      keyTypeList.add("@bob💙:phone😀.buzz@bob💙");
      keyTypeList.add("@bob💙:phone😀@bob💙");

      for (var key in keyTypeList) {
        var type = RegexUtil.keyType(key, false);
        expect(type == KeyType.selfKey, true);
      }
    });

    test('Tests to validate shared key types, namespace mandatory', () {
      var keyTypeList = [];
      keyTypeList.add("@alice:phone.buzz@bob");
      keyTypeList.add("@alice:phone.buzz@bob");
      keyTypeList.add("@alice:p.b@bob");
      keyTypeList.add("@alice:pho_-ne.b@bob");
      keyTypeList.add("@alice💙:phone😀.buzz@bob💙");

      for (var key in keyTypeList) {
        var type = RegexUtil.keyType(key, true);
        expect(type == KeyType.sharedKey, true);
      }
    });

    test('Tests to validate shared key types, namespace not mandatory', () {
      var keyTypeList = [];
      keyTypeList.add("@alice:phone.buzz@bob");
      keyTypeList.add("@alice:phone@bob");

      keyTypeList.add("@alice:phone.buzz@bob");
      keyTypeList.add("@alice:phone@bob");

      keyTypeList.add("@alice:p.b@bob");
      keyTypeList.add("@alice:p@bob");

      keyTypeList.add("@alice:pho_-ne.b@bob");
      keyTypeList.add("@alice:pho_-ne@bob");

      keyTypeList.add("@alice💙:phone😀.buzz@bob💙");
      keyTypeList.add("@alice💙:phone😀@bob💙");

      for (var key in keyTypeList) {
        var type = RegexUtil.keyType(key, false);
        expect(type == KeyType.sharedKey, true);
      }
    });

    test('Tests to validate cached public keys, namespace mandatory', () {
      var keyTypeList = [];
      keyTypeList.add("cached:public:phone.buzz@jagannadh");
      keyTypeList.add("cached:public:p.b@jagannadh");
      keyTypeList.add("cached:public:pho_-n________e.b@jagannadh");
      keyTypeList.add("cached:public:phone😀.buzz@jagannadh💙");

      for (var key in keyTypeList) {
        var type = RegexUtil.keyType(key, true);
        expect(type == KeyType.cachedPublicKey, true);
      }
    });

    test('Tests to validate cached public keys, namespace not mandatory', () {
      var keyTypeList = [];
      keyTypeList.add("cached:public:phone.buzz@jagannadh");
      keyTypeList.add("cached:public:phone@jagannadh");

      keyTypeList.add("cached:public:p.b@jagannadh");
      keyTypeList.add("cached:public:p@jagannadh");

      keyTypeList.add("cached:public:pho_-n________e.b@jagannadh");
      keyTypeList.add("cached:public:pho_-n________e@jagannadh");

      keyTypeList.add("cached:public:phone😀.buzz@jagannadh💙");
      keyTypeList.add("cached:public:phone😀@jagannadh💙");

      for (var key in keyTypeList) {
        var type = RegexUtil.keyType(key, false);
        expect(type == KeyType.cachedPublicKey, true);
      }
    });

    test('Tests to validate cached shared keys, namespace mandatory', () {
      var keyTypeList = [];
      keyTypeList.add(
          "cached:@sitaram0123456789012345678901234567890123456789012345:phone.buzz@jagannadh");
      keyTypeList.add("cached:@sitaram:phone.buzz@jagannadh");
      keyTypeList.add("cached:@sitaram:pho_-n________e.b@jagannadh");
      keyTypeList.add("cached:@sitaram💙:phone😀.buzz@jagannadh💙");

      for (var key in keyTypeList) {
        var type = RegexUtil.keyType(key, true);
        expect(type == KeyType.cachedSharedKey, true);
      }
    });

    test('Tests to validate cached shared keys, namespace not mandatory', () {
      var keyTypeList = [];
      keyTypeList.add(
          "cached:@sitaram0123456789012345678901234567890123456789012345:phone.buzz@jagannadh");
      keyTypeList.add(
          "cached:@sitaram0123456789012345678901234567890123456789012345:phone@jagannadh");

      keyTypeList.add("cached:@sitaram:phone.buzz@jagannadh");
      keyTypeList.add("cached:@sitaram:phone@jagannadh");

      keyTypeList.add("cached:@sitaram:pho_-n________e.b@jagannadh");
      keyTypeList.add("cached:@sitaram:pho_-n________e@jagannadh");

      keyTypeList.add("cached:@sitaram💙:phone😀.buzz@jagannadh💙");
      keyTypeList.add("cached:@sitaram💙:phone😀@jagannadh💙");

      for (var key in keyTypeList) {
        var type = RegexUtil.keyType(key, false);
        expect(type == KeyType.cachedSharedKey, true);
      }
    });
  });

  group('Validate reserved keys regex', () {
    test(
        'Validate appropriate parts of signing_pub_key are identified correctly',
        () {
      String key = 'public:signing_publickey@owner';
      var type = RegexUtil.keyType(key, false);
      expect(type, KeyType.reservedKey);

      var matches = RegexUtil.matchesByGroup(Regexes(false).reservedKey, key);
      expect(matches['owner'], 'owner');
      expect(matches['atKey'], 'signing_publickey');
    });

    test(
        'Validate appropriate parts of enc_shared_key are identified correctly',
        () {
      String key = '@reno:${AtConstants.atEncryptionSharedKey}@ajax';
      var type = RegexUtil.keyType(key, false);
      expect(type, KeyType.reservedKey);

      var matches = RegexUtil.matchesByGroup(Regexes(false).reservedKey, key);
      expect(matches['owner'], 'ajax');
      expect(matches['atKey'], AtConstants.atEncryptionSharedKey);
      expect(matches['sharedWith'], 'reno');
    });

    test('Validate appropriate parts of pkam_pub_key are identified correctly',
        () {
      String key = 'privatekey:at_pkam_publickey';
      var type = RegexUtil.keyType(key, false);
      expect(type, KeyType.reservedKey);

      var matches = RegexUtil.matchesByGroup(Regexes(false).reservedKey, key);
      expect(matches['owner'], '');
      expect(matches['atKey'], 'at_pkam_publickey');
      expect(matches['sharedWith'], '');
    });

    test(
        'Validate appropriate parts of _latestNotificationId are identified correctly',
        () {
      String key = '_latestNotificationId';
      var type = RegexUtil.keyType(key, false);
      print('Expected reservedKey, got $type for $key');
      expect(type, KeyType.reservedKey);

      var matches = RegexUtil.matchesByGroup(Regexes(false).reservedKey, key);
      expect(matches['owner'], '');
      expect(matches['atKey'], '_latestNotificationId');
      expect(matches['sharedWith'], '');
    });
  });

  group('Public or private key regex match tests', () {
    test('Valid public keys', () {
      var pubKeys = TestKeys().validPublicKeys;
      for (var i = 0; i < pubKeys.length; i++) {
        expect(RegexUtil.matchAll(Regexes(true).publicKey, pubKeys[i]), true);
        expect(RegexUtil.matchAll(Regexes(false).publicKey, pubKeys[i]), true);
      }
    });

    test('Invalid public keys', () {
      List<String> invalidPubKeys;
      invalidPubKeys = TestKeys().invalidPublicKeysNamespaceMandatory;
      for (var i = 0; i < invalidPubKeys.length; i++) {
        expect(RegexUtil.matchAll(Regexes(true).publicKey, invalidPubKeys[i]),
            false);
      }
      invalidPubKeys = TestKeys().invalidPublicKeysNamespaceOptional;
      for (var i = 0; i < invalidPubKeys.length; i++) {
        expect(RegexUtil.matchAll(Regexes(false).publicKey, invalidPubKeys[i]),
            false);
      }
    });

    test('Valid private keys', () {
      var privateKeys = TestKeys().validPrivateKeys;
      for (var i = 0; i < privateKeys.length; i++) {
        expect(
            RegexUtil.matchAll(Regexes(true).privateKey, privateKeys[i]), true);
        expect(RegexUtil.matchAll(Regexes(false).privateKey, privateKeys[i]),
            true);
      }
    });

    test('Invalid private keys', () {
      List<String> invalidPrivateKeys;
      invalidPrivateKeys = TestKeys().invalidPrivateKeysNamespaceMandatory;
      for (var i = 0; i < invalidPrivateKeys.length; i++) {
        print(invalidPrivateKeys[i]);
        expect(
            RegexUtil.matchAll(Regexes(true).privateKey, invalidPrivateKeys[i]),
            false);
      }
      invalidPrivateKeys = TestKeys().invalidPrivateKeysNamespaceOptional;
      for (var i = 0; i < invalidPrivateKeys.length; i++) {
        print(invalidPrivateKeys[i]);
        expect(
            RegexUtil.matchAll(
                Regexes(false).privateKey, invalidPrivateKeys[i]),
            false);
      }
    });
  });

  group('Cached public keys regex match tests', () {
    test('Valid cached public keys', () {
      var cachedPubKeys = TestKeys().validCachedPublicKeys;
      for (var i = 0; i < cachedPubKeys.length; i++) {
        expect(
            RegexUtil.matchAll(Regexes(true).cachedPublicKey, cachedPubKeys[i]),
            true);
        expect(
            RegexUtil.matchAll(
                Regexes(false).cachedPublicKey, cachedPubKeys[i]),
            true);
      }
    });

    test('Invalid cached public keys', () {
      List<String> invalidCachedPubKeys;
      invalidCachedPubKeys =
          TestKeys().invalidCachedPublicKeysNamespaceMandatory;
      for (var i = 0; i < invalidCachedPubKeys.length; i++) {
        expect(
            RegexUtil.matchAll(
                Regexes(true).cachedPublicKey, invalidCachedPubKeys[i]),
            false);
      }
      invalidCachedPubKeys =
          TestKeys().invalidCachedPublicKeysNamespaceOptional;
      for (var i = 0; i < invalidCachedPubKeys.length; i++) {
        expect(
            RegexUtil.matchAll(
                Regexes(false).cachedPublicKey, invalidCachedPubKeys[i]),
            false);
      }
    });
  });

  group('Self or hidden key regex match tests', () {
    test('Valid Self keys', () {
      var validSelfKeys = TestKeys().validSelfKeys;
      for (var i = 0; i < validSelfKeys.length; i++) {
        expect(
            RegexUtil.matchAll(Regexes(true).selfKey, validSelfKeys[i]), true);
        expect(
            RegexUtil.matchAll(Regexes(false).selfKey, validSelfKeys[i]), true);
      }
    });

    test('Invalid self keys', () {
      List<String> invalidSelfKeys;
      invalidSelfKeys = TestKeys().invalidSelfKeysNamespaceMandatory;
      for (var i = 0; i < invalidSelfKeys.length; i++) {
        expect(RegexUtil.matchAll(Regexes(true).selfKey, invalidSelfKeys[i]),
            false);
      }
      invalidSelfKeys = TestKeys().invalidSelfKeysNamespaceOptional;
      for (var i = 0; i < invalidSelfKeys.length; i++) {
        expect(RegexUtil.matchAll(Regexes(false).selfKey, invalidSelfKeys[i]),
            false);
      }
    });

    group('Shared or cached key regex match tests', () {
      test('Valid shared keys', () {
        var validSharedKeys = TestKeys().validSharedKeys;
        for (var i = 0; i < validSharedKeys.length; i++) {
          expect(
              RegexUtil.matchAll(Regexes(true).sharedKey, validSharedKeys[i]),
              true);
          expect(
              RegexUtil.matchAll(Regexes(false).sharedKey, validSharedKeys[i]),
              true);
        }
      });

      test('Invalid shared keys', () {
        List<String> invalidSharedKeys;
        invalidSharedKeys = TestKeys().invalidSharedKeysNamespaceMandatory;
        for (var i = 0; i < invalidSharedKeys.length; i++) {
          expect(
              RegexUtil.matchAll(Regexes(true).sharedKey, invalidSharedKeys[i]),
              false);
        }
        invalidSharedKeys = TestKeys().invalidSharedKeysNamespaceOptional;
        for (var i = 0; i < invalidSharedKeys.length; i++) {
          expect(
              RegexUtil.matchAll(
                  Regexes(false).sharedKey, invalidSharedKeys[i]),
              false);
        }
      });

      test('Valid cached shared keys', () {
        var validCachedSharedKeys = TestKeys().validCachedSharedKeys;
        for (var i = 0; i < validCachedSharedKeys.length; i++) {
          print(validCachedSharedKeys[i]);
          expect(
              RegexUtil.matchAll(
                  Regexes(true).cachedSharedKey, validCachedSharedKeys[i]),
              true);
          expect(
              RegexUtil.matchAll(
                  Regexes(false).cachedSharedKey, validCachedSharedKeys[i]),
              true);
        }
      });

      test('Invalid cached shared keys', () {
        List<String> invalidCachedSharedKeys;
        invalidCachedSharedKeys =
            TestKeys().invalidCachedSharedKeysNamespaceMandatory;
        for (var i = 0; i < invalidCachedSharedKeys.length; i++) {
          expect(
              RegexUtil.matchAll(
                  Regexes(true).cachedSharedKey, invalidCachedSharedKeys[i]),
              false);
        }
        invalidCachedSharedKeys =
            TestKeys().invalidCachedSharedKeysNamespaceOptional;
        for (var i = 0; i < invalidCachedSharedKeys.length; i++) {
          expect(
              RegexUtil.matchAll(
                  Regexes(false).cachedSharedKey, invalidCachedSharedKeys[i]),
              false);
        }
      });
    });
  });

  group('A group of test to validate local keys', () {
    test('Test to validate local keys with enforcing namespaces', () {
      var keyTypeList = [];
      keyTypeList.add('local:phone.buzz@alice');
      keyTypeList.add('local:pho_-n________e.b@alice');
      keyTypeList.add('local:phone😀.buzz@alice💙');
      for (var key in keyTypeList) {
        var type = RegexUtil.keyType(key, true);
        expect(type == KeyType.localKey, true);
      }
    });

    test('Test to validate local keys without enforcing namespaces', () {
      var keyTypeList = [];
      keyTypeList.add('local:phone@alice');
      keyTypeList.add('local:pho_-n________e@alice');
      keyTypeList.add('local:phone😀@alice💙');
      for (var key in keyTypeList) {
        var type = RegexUtil.keyType(key, false);
        expect(type == KeyType.localKey, true);
      }
    });
  });
}
