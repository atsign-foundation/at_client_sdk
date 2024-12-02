import 'package:at_commons/at_commons.dart';

/// Returns an instance of [AtKeyValidator]
class AtKeyValidators {
  static AtKeyValidator get() {
    return _AtKeyValidatorImpl();
  }
}

/// Class responsible for validating the atKey.
/// Use [AtKeyValidators.get()] to get an instance of [_AtKeyValidatorImpl]
class _AtKeyValidatorImpl extends AtKeyValidator {
  late String _regex;
  late KeyType _type;

  @override
  ValidationResult validate(String key, ValidationContext context) {
    // Init the state
    _initParams(key, context);
    List<Validation> validations = [];
    validations.add(KeyLengthValidation(key));
    validations.add(KeyFormatValidation(key, _regex, _type));
    if (context.validateOwnership) {
      if (context.atSign == null || context.atSign!.isEmpty) {
        throw AtException(
            'atSign should be set to perform ownership validation');
      }
      Map<String, String?> matches = RegexUtil.matchesByGroup(_regex, key);
      // If sharedWith is not specified default it to empty string.
      String sharedWith = matches[RegexGroup.sharedWith.name()] ?? '';
      // If owner is not specified set it to a empty string
      String owner = matches[RegexGroup.owner.name()] ?? '';
      validations.add(KeyOwnershipValidation(owner, context.atSign!, _type));
      validations.add(KeyShareValidation(owner, sharedWith, _type));
    }

    for (var i = 0; i < validations.length; i++) {
      var result = validations[i].doValidate();
      if (!result.isValid) {
        return result;
      }
    }
    return ValidationResult.noFailure();
  }

  void _initParams(String key, ValidationContext context) {
    // If the atSign is passed with @ remove it.
    context.atSign = context.atSign?.replaceFirst('@', '');
    // If context.type is null, setType and regex.
    if (context.type == null) {
      _type = RegexUtil.keyType(key, context.enforceNamespace);
    } else {
      // if the type of the key is passed in the validation use that to init the regex
      _type = context.type!;
    }
    _setRegex(_type, context.enforceNamespace);
  }

  void _setRegex(KeyType type, bool enforceNamespace) {
    Regexes regexes = Regexes(enforceNamespace);

    switch (type) {
      case KeyType.publicKey:
        _regex = regexes.publicKey;
        break;
      case KeyType.privateKey:
        _regex = regexes.privateKey;
        break;
      case KeyType.selfKey:
        _regex = regexes.selfKey;
        break;
      case KeyType.sharedKey:
        _regex = regexes.sharedKey;
        break;
      case KeyType.cachedPublicKey:
        _regex = regexes.cachedPublicKey;
        break;
      case KeyType.cachedSharedKey:
        _regex = regexes.cachedSharedKey;
        break;
      case KeyType.reservedKey:
        _regex = regexes.reservedKey;
        break;
      case KeyType.localKey:
        _regex = regexes.localKey;
        break;
      case KeyType.invalidKey:
        _regex = '';
        break;
    }
  }
}

/// Verifies if the key belongs to reserved key list.
class ReservedEntityValidation extends Validation {
  String key;

  ReservedEntityValidation(this.key);

  @override
  ValidationResult doValidate() {
    // If key is in reserved key list, return false.
    var reservedKey = _reservedKey(key);
    if (reservedKey != ReservedKey.nonReservedKey &&
        ReservedKey.values.contains(reservedKey)) {
      return ValidationResult('Reserved key cannot be created');
    }
    return ValidationResult.noFailure();
  }

  /// Returns the [ReservedKey] enum for given key.
  ReservedKey _reservedKey(String key) {
    if (key == _getEntityFromConstant(AtConstants.atEncryptionSharedKey)) {
      return ReservedKey.encryptionSharedKey;
    }
    if (key == _getEntityFromConstant(AtConstants.atEncryptionPublicKey)) {
      return ReservedKey.encryptionPublicKey;
    }
    if (key == _getEntityFromConstant(AtConstants.atEncryptionPrivateKey)) {
      return ReservedKey.encryptionPrivateKey;
    }
    if (key == _getEntityFromConstant(AtConstants.atPkamPublicKey)) {
      return ReservedKey.pkamPublicKey;
    }
    if (key == _getEntityFromConstant(AtConstants.atSigningPrivateKey)) {
      return ReservedKey.signingPrivateKey;
    }
    return ReservedKey.nonReservedKey;
  }

  /// Returns the entity part from the key constants.
  /// Eg: AT_ENCRYPTION_PUBLIC_KEY = 'public:publickey';
  ///     return 'publickey';
  String _getEntityFromConstant(String key) {
    if (key.contains(':')) {
      return key.split(':')[1];
    }
    return key;
  }
}

/// Validates key length of a key
class KeyLengthValidation extends Validation {
  static const int maxKeyLength = 255;
  static const int maxKeyLengthWithoutCached = 248;
  String key;

  KeyLengthValidation(this.key);

  @override
  ValidationResult doValidate() {
    int maxLength =
        key.startsWith('cached:') ? maxKeyLength : maxKeyLengthWithoutCached;
    if (key.length > maxLength) {
      return ValidationResult(
          'Key length exceeds maximum permissible length of $maxLength characters');
    }
    return ValidationResult.noFailure();
  }
}

/// Validates if the Key adheres to a format represented by a regex
class KeyFormatValidation extends Validation {
  String key, regex;
  KeyType type;

  KeyFormatValidation(this.key, this.regex, this.type);

  @override
  ValidationResult doValidate() {
    if (type == KeyType.invalidKey) {
      return ValidationResult('$key is not a valid key');
    }

    bool match = RegexUtil.matchAll(regex, key);
    if (!match) {
      return ValidationResult('$key does not adhere to the regex $regex');
    }
    return ValidationResult.noFailure();
  }
}

/// Validates if the ownership is right for a given key type
class KeyOwnershipValidation extends Validation {
  String owner, atSign;
  KeyType type;

  KeyOwnershipValidation(this.owner, this.atSign, this.type);

  @override
  ValidationResult doValidate() {
    // Ownership rules:
    // ------------------
    // Rule 1: For a cached key owner should be different from the current @sign.
    // Rule 2: For a non cached key owner should be same as the current @sign.
    // A non cached key can be Public, Private, Hidden or just a self key
    if ((type == KeyType.cachedPublicKey || type == KeyType.cachedSharedKey) &&
        (owner == atSign)) {
      return ValidationResult(
          'Owner of the key $owner should not be same as the the current @sign $atSign for a cached key');
    }
    if ((type != KeyType.cachedPublicKey && type != KeyType.cachedSharedKey) &&
        owner != atSign) {
      return ValidationResult(
          'Owner of the key $owner should be same as current @sign $atSign');
    }
    return ValidationResult.noFailure();
  }
}

/// Validates if key is rightly shared
class KeyShareValidation extends Validation {
  String owner, sharedWith;
  KeyType type;

  KeyShareValidation(this.owner, this.sharedWith, this.type);

  @override
  ValidationResult doValidate() {
    // Ownership rules:
    // ------------------
    // Rule 1: For a self key if sharedWith is present it should be same as the @sign
    // Rule 2: For a shared key sharedWith should be different from the current @sign

    if ((type == KeyType.selfKey) &&
        sharedWith.isNotEmpty &&
        owner != sharedWith) {
      return ValidationResult(
          'For a self key owner $owner should be same as with whom it is shared with $sharedWith.');
    }
    if (type == KeyType.sharedKey && sharedWith.isEmpty) {
      return ValidationResult(
          'Shared with cannot be null for a shared key $sharedWith');
    }
    if (type == KeyType.sharedKey && owner == sharedWith) {
      return ValidationResult(
          'For a shared key owner $owner should not be same as with whom it is shared with $sharedWith.');
    }
    return ValidationResult.noFailure();
  }
}
