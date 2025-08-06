import 'package:at_commons/at_commons.dart';
import 'package:at_commons/src/keystore/at_key_builder.dart';

/// Abstract base class for the KeyBuilder
abstract class AbstractKeyBuilder implements KeyBuilder {
  final _meta = Metadata();
  late AtKey _atKey;

  @override
  void key(String key) {
    key = key.trim();
    _atKey.key = key;
  }

  @override
  void namespace(String? namespace) {
    namespace = namespace?.trim();
    _atKey.namespace = namespace;
  }

  @override
  void timeToLive(int ttl) {
    _meta.ttl = ttl;
  }

  @override
  void timeToBirth(int ttb) {
    _meta.ttb = ttb;
  }

  @override
  AtKey build() {
    // Validate if the data is set properly
    validate();
    // Set Metadata data on the key
    _atKey.metadata = _meta;
    return _atKey;
  }

  @override
  void validate() {
    if (_atKey.key.isEmpty) {
      throw AtException("Key cannot be empty");
    }
    // validate the atKey
    // Setting the validateOwnership to false to skip KeyOwnerShip validation and
    // KeyShare validation. These validation will be performed on put and get of the key.
    AtKeyValidators.get()
        .validate(toString(), ValidationContext()..validateOwnership = false);
  }

  @override
  void sharedBy(String atSign) {
    _atKey.sharedBy = atSign;
  }
}

/// Builder class for cached key's.
abstract class CachedKeyBuilder extends AbstractKeyBuilder {
  CachedKeyBuilder() : super();

  ///Cache's the key on [AtKey.sharedWith] atSign.
  /// TTR denotes the time to refresh the cached key. Accepts an integer value
  /// which represents the time units in seconds.
  /// CCD denotes the cascade delete. Accepts a boolean value.
  /// When set to true, deletes the cached key when corresponding key is deleted.
  /// When set to false, the cached key remains when corresponding key is deleted.
  void cache(int ttr, bool ccd);
}

/// Builder to build the public keys
class PublicKeyBuilder extends CachedKeyBuilder {
  PublicKeyBuilder() : super() {
    _atKey = PublicKey();
    _meta.isPublic = true;
    _meta.isHidden = false;
  }

  @override
  void cache(int ttr, bool ccd) {
    _meta.ttr = ttr;
    _meta.ccd = ccd;
    _meta.isCached = (ttr != 0);
  }
}

/// Builder to build the shared keys
class SharedKeyBuilder extends CachedKeyBuilder {
  SharedKeyBuilder() : super() {
    _atKey = SharedKey();
    _meta.isPublic = false;
    _meta.isHidden = false;
  }

  @override
  void cache(int ttr, bool ccd) {
    _meta.ttr = ttr;
    _meta.ccd = ccd;
  }

  /// Accepts a string which represents an atSign for the key is created.
  void sharedWith(String sharedWith) {
    sharedWith = sharedWith.trim();
    _atKey.sharedWith = sharedWith;
  }

  @override
  void validate() {
    //Call AbstractKeyBuilder validate method to perform the common validations.
    super.validate();
    if (_atKey.sharedWith == null || _atKey.sharedWith!.isEmpty) {
      throw AtException("sharedWith cannot be empty");
    }
  }
}

/// Builder to build the Self keys
class SelfKeyBuilder extends AbstractKeyBuilder {
  SelfKeyBuilder() : super() {
    _atKey = SelfKey();
    _meta.isPublic = false;
    _meta.isHidden = false;
  }
}

/// Obsolete, was never used
@Deprecated("Obsolete, from the ancient times")
class PrivateKeyBuilder extends AbstractKeyBuilder {
  PrivateKeyBuilder() : super() {
    _atKey = PrivateKey();
    _meta.isHidden = true;
    _meta.isPublic = false;
  }
}

/// Builder to build the local keys
class LocalKeyBuilder extends AbstractKeyBuilder {
  LocalKeyBuilder() : super() {
    _atKey = LocalKey();
    _atKey.isLocal = true;
  }
}
