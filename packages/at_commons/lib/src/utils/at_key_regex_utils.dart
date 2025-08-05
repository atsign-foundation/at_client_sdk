import 'dart:collection';

import 'package:at_commons/src/keystore/key_type.dart';

abstract class Regexes {
  static const charsInNamespace = r'([\w])+';
  static const charsInAtSign = r'[\w\-_]';
  static const charsInEntity = r'''[\w\.\-_'*"]''';
  static const allowedEmoji =
      r'''((\u00a9|\u00ae|[\u2000-\u3300]|[\ufe00-\ufe0f]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff]))''';

  static const _reservedKeysWithoutAtsignSuffix =
      r'(((?<=privatekey:)(at_pkam_publickey|at_pkam_privatekey'
      '|privatekey|self_encryption_key'
      '|at_secret|at_secret_deleted'
      '|signing_keypair_generated|commitLogCompactionStats'
      '|accessLogCompactionStats'
      '|notificationCompactionStats)\$)|^(configkey)\$|(?:^_($charsInEntity)+)\$)';
  // the last part of the above regex is to match internal keys such as
  // _latestNotificationId (keys that start with an underscore)

  /// The following reserved keys are suffixed by the atsign. [ownershipFragment]
  /// at the end represents the atsign
  static const _reservedKeysWithAtsignSuffix = r'('
      '('
      '(?<=private:)'
      'blocklist'
      '|(?<=public:)signing_publickey'
      '|(?<=$ownershipFragmentWithoutNamedGroup:)signing_privatekey'
      '|(?<=^@($sharedWithFragment))shared_key'
      '|(?<=public:)publickey'
      '|(shared_key\\.$ownershipFragmentWithoutAtPrefix)'
      ')(?=$ownershipFragment)'
      ')';

  static const String namespaceFragment = '\\.(?<namespace>$charsInNamespace)';
  static const String ownershipFragmentWithoutAtPrefix =
      '(($charsInAtSign|$allowedEmoji){1,55})';
  static const String ownershipFragment =
      '@(?<owner>$ownershipFragmentWithoutAtPrefix)';
  static const String ownershipFragmentWithoutNamedGroup =
      '''@($charsInAtSign|$allowedEmoji){1,55}''';
  static const String sharedWithFragment =
      '''((?<sharedWith>($charsInAtSign|$allowedEmoji){1,55}):)''';
  static const String entityFragment =
      '''(?<entity>($charsInEntity|$allowedEmoji)+)''';

  static const String publicKeyStartFragment =
      '''(?<visibility>(public:){1})$entityFragment''';
  static const String privateKeyStartFragment =
      '''(?<visibility>(private:){1})(@$sharedWithFragment)?$entityFragment''';
  static const String selfKeyStartFragment =
      '''(@$sharedWithFragment)?(_*$entityFragment)''';
  static const String sharedKeyStartFragment =
      '''(@$sharedWithFragment)(_*$entityFragment)''';
  static const String cachedSharedKeyStartFragment =
      '''(cached:)(@$sharedWithFragment)(_*$entityFragment)''';
  static const String cachedPublicKeyStartFragment =
      '''(?<visibility>(cached:public:){1})$entityFragment''';
  static const String reservedKeyFragment =
      '''(?<atKey>($_reservedKeysWithoutAtsignSuffix|$_reservedKeysWithAtsignSuffix))''';
  static const String localKeyFragment =
      '''(?<visibility>(local:){1})$entityFragment''';

  String get publicKey;

  String get privateKey;

  String get selfKey;

  String get sharedKey;

  String get cachedSharedKey;

  String get cachedPublicKey;

  String get reservedKey;

  String get localKey;

  static final Regexes _regexesWithMandatoryNamespace =
      RegexesWithMandatoryNamespace();
  static final Regexes _regexesNonMandatoryNamespace =
      RegexesNonMandatoryNamespace();

  factory Regexes(bool enforceNamespace) {
    if (enforceNamespace) {
      return _regexesWithMandatoryNamespace;
    } else {
      return _regexesNonMandatoryNamespace;
    }
  }
}

class RegexesWithMandatoryNamespace implements Regexes {
  // There are currently no tests for this, but the regexes are and must remain mutually exclusive
  static const String _publicKey =
      '''${Regexes.publicKeyStartFragment}${Regexes.namespaceFragment}${Regexes.ownershipFragment}''';
  static const String _privateKey =
      '''${Regexes.privateKeyStartFragment}${Regexes.namespaceFragment}${Regexes.ownershipFragment}''';
  static const String _selfKey =
      '''${Regexes.selfKeyStartFragment}${Regexes.namespaceFragment}${Regexes.ownershipFragment}''';
  static const String _sharedKey =
      '''${Regexes.sharedKeyStartFragment}${Regexes.namespaceFragment}${Regexes.ownershipFragment}''';
  static const String _cachedSharedKey =
      '''${Regexes.cachedSharedKeyStartFragment}${Regexes.namespaceFragment}${Regexes.ownershipFragment}''';
  static const String _cachedPublicKey =
      '''${Regexes.cachedPublicKeyStartFragment}${Regexes.namespaceFragment}${Regexes.ownershipFragment}''';
  static const String _localKey =
      '''${Regexes.localKeyFragment}${Regexes.namespaceFragment}${Regexes.ownershipFragment}''';

  @override
  String get publicKey => _publicKey;

  @override
  String get privateKey => _privateKey;

  @override
  String get selfKey => _selfKey;

  @override
  String get sharedKey => _sharedKey;

  @override
  String get cachedSharedKey => _cachedSharedKey;

  @override
  String get cachedPublicKey => _cachedPublicKey;

  @override
  String get reservedKey => Regexes.reservedKeyFragment;

  @override
  String get localKey => _localKey;
}

class RegexesNonMandatoryNamespace implements Regexes {
  // There are currently no tests for this, but the regexes are and must remain mutually exclusive
  static const String _publicKey =
      '''${Regexes.publicKeyStartFragment}${Regexes.ownershipFragment}''';
  static const String _privateKey =
      '''${Regexes.privateKeyStartFragment}${Regexes.ownershipFragment}''';
  static const String _selfKey =
      '''${Regexes.selfKeyStartFragment}${Regexes.ownershipFragment}''';
  static const String _sharedKey =
      '''${Regexes.sharedKeyStartFragment}${Regexes.ownershipFragment}''';
  static const String _cachedSharedKey =
      '''${Regexes.cachedSharedKeyStartFragment}${Regexes.ownershipFragment}''';
  static const String _cachedPublicKey =
      '''${Regexes.cachedPublicKeyStartFragment}${Regexes.ownershipFragment}''';
  static const String _localKey =
      '''${Regexes.localKeyFragment}${Regexes.ownershipFragment}''';

  @override
  String get publicKey => _publicKey;

  @override
  String get privateKey => _privateKey;

  @override
  String get selfKey => _selfKey;

  @override
  String get sharedKey => _sharedKey;

  @override
  String get cachedSharedKey => _cachedSharedKey;

  @override
  String get cachedPublicKey => _cachedPublicKey;

  @override
  String get reservedKey => Regexes.reservedKeyFragment;

  @override
  String get localKey => _localKey;
}

class RegexUtil {
  /// Returns a first matching key type after matching the key against regexes for each of the key type
  static KeyType keyType(String key, bool enforceNamespace) {
    Regexes regexes = Regexes(enforceNamespace);
    if (isPartialMatch(regexes.reservedKey, key)) {
      return KeyType.reservedKey;
    }
    // matches the key with public key regex.
    if (matchAll(regexes.publicKey, key)) {
      return KeyType.publicKey;
    }
    // matches the key with private key regex.
    if (matchAll(regexes.privateKey, key)) {
      return KeyType.privateKey;
    }
    // matches the key with self key regex.
    if (matchAll(regexes.selfKey, key)) {
      Map<String, String> matches =
          RegexUtil.matchesByGroup(regexes.selfKey, key);
      String? sharedWith = matches[RegexGroup.sharedWith.name()];
      // If owner is not specified set it to a empty string
      String? owner = matches[RegexGroup.owner.name()];
      if ((owner != null && owner.isNotEmpty) &&
          (sharedWith != null && sharedWith.isNotEmpty) &&
          owner != sharedWith) {
        return KeyType.sharedKey;
      }
      return KeyType.selfKey;
    }
    if (matchAll(regexes.cachedPublicKey, key)) {
      return KeyType.cachedPublicKey;
    }
    if (matchAll(regexes.cachedSharedKey, key)) {
      return KeyType.cachedSharedKey;
    }
    if (matchAll(regexes.localKey, key)) {
      return KeyType.localKey;
    }
    return KeyType.invalidKey;
  }

  /// Matches a regex against the input
  /// Returns a true if the regex is matched to the ENTIRE string, false otherwise
  static bool matchAll(String regex, String input) {
    var regExp = RegExp(regex, caseSensitive: false);
    return regExp.hasMatch(input) &&
        regExp.stringMatch(input)!.length == input.length;
  }

  /// Checks if the the [input] is a partial match to the [regex]
  static bool isPartialMatch(String regex, String input) {
    RegExp regExp = RegExp(regex, caseSensitive: false);
    return regExp.hasMatch(input);
  }

  /// Returns a [Map] containing named groups and the matched values in the input
  /// Returns an empty [Map] if no matches are found
  static Map<String, String> matchesByGroup(String regex, String input) {
    var regExp = RegExp(regex, caseSensitive: false);
    var matches = regExp.allMatches(input);

    if (matches.isEmpty) {
      return <String, String>{};
    }

    var paramsMap = HashMap<String, String>();
    for (var f in matches) {
      for (var name in f.groupNames) {
        paramsMap.putIfAbsent(name,
            () => (f.namedGroup(name) != null) ? f.namedGroup(name)! : '');
      }
    }
    return paramsMap;
  }
}

/// Represents groups with in Regexes
/// See [Regexes]
enum RegexGroup { visibility, sharedWith, entity, namespace, owner }

extension RegexGroupToString on RegexGroup {
  String name() {
    return toString().split('.').last;
  }
}
