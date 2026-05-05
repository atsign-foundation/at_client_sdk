import 'dart:convert';

import 'package:at_commons/src/keystore/at_key_builder_impl.dart';
import 'package:at_commons/src/keystore/public_key_hash.dart';
import 'package:at_commons/src/utils/at_key_regex_utils.dart';
import 'package:at_commons/src/utils/string_utils.dart';
import 'package:at_commons/src/verb/verb_util.dart';

import '../at_constants.dart';
import '../exception/at_exceptions.dart';
import 'key_type.dart';

class AtKey {
  /// The 'identifier' part of an atProtocol key name. For example if the key is
  /// `@bob:city.address.my_app@alice` then the [key] would be `city.address` and
  /// the [namespace] would be `my_app`
  late String key;
  String? _sharedWith;
  String? _sharedBy;
  String? _namespace;
  Metadata metadata = Metadata();
  bool isRef = false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AtKey &&
          runtimeType == other.runtimeType &&
          key == other.key &&
          _sharedWith == other._sharedWith &&
          _sharedBy == other._sharedBy &&
          namespace == other.namespace &&
          metadata == other.metadata &&
          isRef == other.isRef &&
          _isLocal == other._isLocal;

  @override
  int get hashCode =>
      key.hashCode ^
      _sharedWith.hashCode ^
      _sharedBy.hashCode ^
      namespace.hashCode ^
      metadata.hashCode ^
      isRef.hashCode ^
      _isLocal.hashCode;

  /// When set to true, represents the [LocalKey]
  /// These keys will never be synced between the client and secondary server.
  bool _isLocal = false;

  /// When set to true, indicates that this key is a [LocalKey]. A [LocalKey] will
  /// remain in local storage on the client, and will never be synced to the cloud atServer.
  bool get isLocal => _isLocal;

  set isLocal(bool isLocal) {
    if (isLocal == true && sharedWith != null) {
      throw InvalidAtKeyException(
          'sharedWith must be null when isLocal is set to true');
    }
    _isLocal = isLocal;
  }

  String? get namespace => _namespace;

  set namespace(String? namespace) {
    if (namespace.isNotNullOrEmpty) {
      _namespace = namespace?.toLowerCase();
    }
  }

  /// The 'owner' part of an atProtocol key name. For example if the key is
  /// `@bob:city.address.my_app@alice` then [sharedBy] is `@alice`
  String? get sharedBy => _sharedBy;

  /// The 'owner' part of an atProtocol key name. For example if the key is
  /// `@bob:city.address.my_app@alice` then [sharedBy] is `@alice`
  set sharedBy(String? sharedByAtSign) {
    if (sharedByAtSign != null &&
        sharedByAtSign.isNotEmpty &&
        (!sharedByAtSign.startsWith('@'))) {
      sharedByAtSign = '@$sharedByAtSign';
    }
    _sharedBy = sharedByAtSign?.toLowerCase();
  }

  /// The 'recipient' part of an atProtocol key name. For example if the key is
  /// `@bob:city.address.my_app@alice` then [sharedWith] is `@bob`
  String? get sharedWith => _sharedWith;

  /// The 'recipient' part of an atProtocol key name. For example if the key is
  /// `@bob:city.address.my_app@alice` then [sharedWith] is `@bob`
  set sharedWith(String? sharedWithAtSign) {
    if (sharedWithAtSign != null &&
        sharedWithAtSign.isNotEmpty &&
        (!sharedWithAtSign.startsWith('@'))) {
      sharedWithAtSign = '@$sharedWithAtSign';
    }
    if (sharedWithAtSign.isNotNullOrEmpty &&
        (isLocal == true || metadata.isPublic == true)) {
      throw InvalidAtKeyException(
          'isLocal or isPublic cannot be true when sharedWith is set');
    }
    _sharedWith = sharedWithAtSign?.toLowerCase();
  }

  String _dotNamespaceIfPresent() {
    if (namespace != null && namespace!.isNotEmpty) {
      return '.$namespace';
    } else {
      return '';
    }
  }

  String get fullKey => '$key${_dotNamespaceIfPresent()}';

  String get fullKeyAndOwner => '$fullKey$sharedBy';

  @override
  String toString() {
    if (key.isNullOrEmpty) {
      throw InvalidAtKeyException('Key cannot be null or empty');
    }
    //enforcing lower-case on AtKey.key
    key = key.toLowerCase();
    // If metadata.isPublic is true and metadata.isCached is true,
    // return cached public key
    if (key.startsWith('cached:public:') ||
        (metadata.isPublic) && (metadata.isCached)) {
      return 'cached:public:$key${_dotNamespaceIfPresent()}$_sharedBy';
    }

    // If metadata.isPublic is true, return public key
    if (key.startsWith('public:') || (metadata.isPublic)) {
      return 'public:$key${_dotNamespaceIfPresent()}$_sharedBy';
    }

    //If metadata.isCached is true, return shared cached key
    if (key.startsWith('cached:') || (metadata.isCached)) {
      return 'cached:$_sharedWith:$key${_dotNamespaceIfPresent()}$_sharedBy';
    }

    // If key starts with privatekey:, return private key
    if (metadata.isHidden || key.startsWith('privatekey:')) {
      if (key.startsWith('privatekey:')) {
        return key.toLowerCase();
      }
      return 'privatekey:$key${_dotNamespaceIfPresent()}'.toLowerCase();
    }

    //If _sharedWith is not null, return sharedKey
    if (_sharedWith != null && _sharedWith!.isNotEmpty) {
      return '$_sharedWith:$key${_dotNamespaceIfPresent()}$_sharedBy';
    }

    // if key starts with local: or isLocal set to true, return local key
    if (isLocal == true) {
      String localKey = '$key${_dotNamespaceIfPresent()}$sharedBy';
      if (localKey.startsWith('local:')) {
        return localKey;
      }
      return 'local:$localKey';
    }

    // Defaults to return a self key.
    return '$key${_dotNamespaceIfPresent()}$_sharedBy';
  }

  static void assertStartsWithAtIfNotEmpty(String? atSign) {
    if (atSign != null && atSign.isNotEmpty && !atSign.startsWith('@')) {
      throw InvalidSyntaxException('atSign $atSign does not start with an "@"');
    }
  }

  /// Public keys are visible to everyone and shown in an authenticated/unauthenticated scan
  ///
  /// Builds a public key and returns a [PublicKeyBuilder]
  ///
  ///Example: public:phone.wavi@alice.
  ///```dart
  ///AtKey publicKey = AtKey.public('phone', namespace: 'wavi', sharedBy: '@alice').build();
  ///```
  static PublicKeyBuilder public(String key,
      {String? namespace, String sharedBy = ''}) {
    assertStartsWithAtIfNotEmpty(sharedBy);
    return PublicKeyBuilder()
      ..key(key)
      ..namespace(namespace)
      ..sharedBy(sharedBy);
  }

  /// Shared Keys are shared with other atSign. The owner can see the keys on
  /// authenticated scan. The sharedWith atSign can lookup the value of the key.
  ///
  ///Builds a sharedWith key and returns a [SharedKeyBuilder]. Optionally the key
  ///can be cached on the [AtKey.sharedWith] atSign.
  ///
  ///Example: @bob:phone.wavi@alice.
  ///```dart
  ///AtKey sharedKey = (AtKey.shared('phone', 'wavi')
  ///     ..sharedWith('@bob')).build();
  ///```
  /// To cache a key on the @bob atSign.
  /// ```dart
  ///AtKey atKey = (AtKey.shared('phone', namespace: 'wavi', sharedBy: '@alice')
  ///  ..sharedWith('@bob')
  ///  ..cache(1000, true))
  ///  .build();
  /// ```
  static SharedKeyBuilder shared(String key,
      {String? namespace, String sharedBy = ''}) {
    assertStartsWithAtIfNotEmpty(sharedBy);
    return SharedKeyBuilder()
      ..key(key)
      ..namespace(namespace)
      ..sharedBy(sharedBy);
  }

  /// Self keys that are created by the owner of the atSign and the keys can be
  /// accessed by the owner of the atSign only.
  ///
  /// Builds a self key and returns a [SelfKeyBuilder].
  ///
  ///
  /// Example: phone.wavi@alice
  /// ```dart
  /// AtKey selfKey = AtKey.self('phone', namespace: 'wavi', sharedBy: '@alice').build();
  /// ```
  static SelfKeyBuilder self(String key,
      {String? namespace, String sharedBy = ''}) {
    assertStartsWithAtIfNotEmpty(sharedBy);
    return SelfKeyBuilder()
      ..key(key)
      ..namespace(namespace)
      ..sharedBy(sharedBy);
  }

  /// Obsolete, was never used
  @Deprecated("Obsolete, from the ancient times")
  static PrivateKeyBuilder private(String key, {String? namespace}) {
    return PrivateKeyBuilder()
      ..key(key)
      ..namespace(namespace);
  }

  /// Local key are confined to the client(device)/server it is created.
  /// The key does not sync between the local-secondary and the cloud-secondary.
  ///
  /// Builds a local key and return a [LocalKeyBuilder].
  ///
  /// Example: local:phone.wavi@alice
  /// ```dart
  /// AtKey localKey = AtKey.local('phone',namespace:'wavi').build();
  /// ```
  static LocalKeyBuilder local(String key, String sharedBy,
      {String? namespace}) {
    return LocalKeyBuilder()
      ..key(key)
      ..namespace(namespace)
      ..sharedBy(sharedBy);
  }

  static AtKey fromString(String key) {
    var atKey = AtKey();
    var metaData = Metadata();
    if (key.startsWith(AtConstants.atPkamPrivateKey) ||
        key.startsWith(AtConstants.atPkamPublicKey)) {
      atKey.key = key;
      atKey.metadata = metaData;
      return atKey;
    } else if (key.startsWith(AtConstants.atEncryptionPrivateKey)) {
      atKey.key = key.split('@')[0];
      atKey.sharedBy = '@${key.split('@')[1]}';
      atKey.metadata = metaData;
      return atKey;
    }
    //If key does not contain '@'. or key has space, it is not a valid key.
    if (!key.contains('@') || key.contains(' ')) {
      throw InvalidSyntaxException('$key is not well-formed key');
    }
    var keyParts = key.split(':');
    // If key does not contain ':' Ex: phone@bob; then keyParts length is 1
    // where phone is key and @bob is sharedBy
    if (keyParts.length == 1) {
      atKey.sharedBy = '@${keyParts[0].split('@')[1]}';
      atKey.key = keyParts[0].split('@')[0];
    } else {
      // Example key: public:phone@bob
      if (keyParts[0] == 'public') {
        metaData.isPublic = true;
      } else if (keyParts[0] == 'local') {
        atKey.isLocal = true;
      } else if (keyParts[0] == AtConstants.cached) {
        metaData.isCached = true;
        if (keyParts[1] == 'public') {
          metaData.isPublic = true;
          atKey.sharedWith = null; // Example key: cached:public:phone@bob
        } else {
          atKey.sharedWith =
              keyParts[1]; // Example key: cached:@alice:phone@bob
        }
      } else {
        atKey.sharedWith = keyParts[0];
      }

      List<String> keyArr = [];
      if (keyParts[0] == AtConstants.cached) {
        //cached:@alice:phone@bob
        keyArr = keyParts[2].split('@'); //phone@bob ==> 'phone', 'bob'
      } else {
        // @alice:phone@bob
        keyArr = keyParts[1].split('@'); // phone@bob ==> 'phone', 'bob'
      }
      if (keyArr.length == 2) {
        atKey.sharedBy =
            '@${keyArr[1]}'; // keyArr[1] is 'bob' so sharedBy needs to be @bob
        atKey.key = keyArr[0];
      } else {
        atKey.key = keyArr[0];
      }
    }
    //remove namespace
    if (atKey.key.contains('.')) {
      var namespaceIndex = atKey.key.lastIndexOf('.');
      if (namespaceIndex > -1) {
        atKey.namespace = atKey.key.substring(namespaceIndex + 1);
        atKey.key = atKey.key.substring(0, namespaceIndex);
      }
    } else {
      metaData.namespaceAware = false;
    }
    atKey.metadata = metaData;
    return atKey;
  }

  /// Returns one of the valid keys from [KeyType] if there is a regex match. Otherwise returns [KeyType.invalidKey]
  /// Set enforceNamespace=true for strict namespace validation in the key.
  static KeyType getKeyType(String key, {bool enforceNameSpace = false}) {
    return RegexUtil.keyType(key, enforceNameSpace);
  }
}

/// Represents a public key.
class PublicKey extends AtKey {
  PublicKey() {
    super.metadata = Metadata();
    super.metadata.isPublic = true;
  }
}

///Represents a Self key.
class SelfKey extends AtKey {
  SelfKey() {
    super.metadata = Metadata();
    super.metadata.isPublic = false;
  }
}

/// Represents a key shared to another atSign.
class SharedKey extends AtKey {
  SharedKey() {
    super.metadata = Metadata();
  }
}

/// Obsolete, was never used
@Deprecated("Obsolete, from the ancient times")
class PrivateKey extends AtKey {
  PrivateKey() {
    super.metadata = Metadata()..isHidden = true;
  }

  @override
  String toString() {
    return 'privatekey:$key${_dotNamespaceIfPresent()}'.toLowerCase();
  }
}

/// Represents a local key
/// Local key are confined to the client(device)/server it is created.
/// The key does not sync between the local-secondary and the cloud-secondary.
class LocalKey extends AtKey {
  LocalKey() {
    isLocal = true;
    super.metadata = Metadata();
  }
}

class Metadata {
  /// Time in milliseconds after which the [AtKey] expires.
  int? ttl;

  /// Time in milliseconds after which the [AtKey] becomes active.
  int? ttb;

  /// Represents the time frequency in seconds when the cached key gets refreshed
  /// Time in **seconds** after which a cached copy of this [AtKey] should be refreshed.
  int? ttr;

  /// CCD (Cascade Delete) means if a shared key is deleted, then the corresponding cached key will also be deleted
  ///
  /// When set to true, on deleting the original key, the corresponding cached key will be deleted,
  /// When set to false, the cached key remains even after the original key is deleted.
  bool? ccd;

  /// This is a derived field representing [ttb] in [DateTime] format
  DateTime? availableAt;

  /// This is a derived field representing [ttl] in [DateTime] format
  DateTime? expiresAt;

  /// This is a derived field representing [ttr] in [DateTime] format
  DateTime? refreshAt;

  /// A date and time representing when the key is created
  DateTime? createdAt;

  /// A date and time representing when the key is last modified
  DateTime? updatedAt;

  /// The [dataSignature] is used to verify authenticity of the public data.
  ///
  /// The public data is signed using the key owner's [ReservedKey.encryptionPrivateKey] and resultant is stored into dataSignature.
  String? dataSignature;

  /// Represents the status of the [SharedKey]
  String? sharedKeyStatus;

  /// if [isPublic] is true, then [atKey] is accessible by all atSigns.
  /// if [isPublic] is false, then [atKey] is only accessible by either [sharedWith] or [sharedBy]
  bool isPublic = false;

  /// When set to true, implies the key is a HiddenKey
  bool isHidden = false;

  /// Indicates if the namespace should be appended to the key
  ///
  /// By default, is set to true which implies the namespace is appended key
  ///
  /// For reserved key's, [namespaceAware] is set to false to ignore the namespace appending to key
  bool namespaceAware = true;

  /// Determines whether a value is stored as binary data
  /// If value of the key is blob (images, videos etc), the binary data is encoded to text and [isBinary] is set to true.
  bool isBinary = false;

  /// Is the value encrypted, or not
  bool isEncrypted = false;

  /// When set to true, indicates the key is a cached key
  bool isCached = false;

  /// Stores the shared key, 'inline' and encrypted, in the metadata of the keystore entry for the encrypted data
  ///
  /// Will be set only if [sharedWith] is set. Will be encrypted using a public key of the [sharedWith] atsign.
  /// See also [skeEncKeyName]
  String? sharedKeyEnc;

  /// Stores the checksum of the encryption public key used to encrypt the
  /// [sharedKeyEnc]. We use this to verify that the encryption key-pairs used
  /// to encrypt and decrypt the value are the same
  /// Will be marked as `@Deprecated('Use pubKeyHash')` once at_server and
  /// at_client_sdk fully support pubKeyHash
  String? pubKeyCS;

  /// Stores the hash of the encryption public key used to encrypt the [sharedKeyEnc]
  /// The hash is used to verify whether the current atsign's public key used for encrypting data by another atsign, has changed while decrypting the data
  PublicKeyHash? pubKeyHash;

  /// If the [AtValue] is public data (i.e. it is not encrypted) and contains one or more new line (\n) characters,
  /// then the data will be encoded, and the encoding will be set to type of encoding (e.g. "base64")
  String? encoding;

  /// The name of the key used to encrypt the [AtValue]
  /// * If not provided, use [sharedKeyEnc] in this metaData.
  /// * If [sharedKeyEnc] is not provided in this metadata, use the default shared key.
  /// For example if this is @bob and the data was shared by @alice, then @bob will use
  /// the key at `@bob:shared_key@alice`
  /// * When [encKeyName] is provided, just the key name must be provided - neither the visibility prefix
  /// nor the sharedBy suffix should be included. For example @alice might choose to encrypt some data
  /// to share with bob at `@bob:some_data.wavi@alice`, using the shared key they have shared at
  /// `@bob:key_12345.__shared_keys.wavi@alice`. The [encKeyName] in this case _must_ be provided as
  /// `key_12345.__shared_keys.wavi`
  /// * Note: The same scheme holds for data encrypted by @bob for @bob's own use. In this case
  /// we don't call it a "shared" key but instead we call it a "self" encryption key.
  /// * Note that the legacy default self encryption key is not stored in the keyStore but is kept
  /// in the set of keys held by applications.
  /// * In future we will (1) store the self encryption key in the keyStore, encrypted with one of
  /// our encryption public keys, and (2) allow creation of many 'self' encryption keys and store them
  /// in an application namespace. For example @bob might create a self encryption key at
  /// `key_54321.__self_keys.wavi@bob`; if used to encrypt some data for self, then the encKeyName would be
  /// set to `key_54321.__self_keys.wavi` since the sharedBy of the encrypting key will be the same as the
  /// `sharedBy` of the encrypted key.
  String? encKeyName;

  /// The name of the algorithm used to encrypt the [AtValue].
  /// * For **data**, the default algorithm is `AES/SIC/PKCS7Padding`
  /// * For **keys**, the default algorithm is `RSA`
  String? encAlgo;

  /// Initialization Vector or nonce used when the data was encrypted with the shared symmetric key.
  String? ivNonce;

  /// When [sharedKeyEnc] is provided in the metadata, [skeEncKeyName] is the name of the public
  /// key which was used to encrypt it. `skeEncKeyName` is an abbreviation for the EncryptionKeyName
  /// used to encrypt the SharedKeyEncrypted.
  /// * If [skeEncKeyName] is null, then the name of the default public key is used. For example,
  /// if we are @bob and someone has shared data with us, and has provided the shared key inline in [sharedKeyEnc],
  /// the default public key used is "public:publickey@bob".
  /// * When multiple asymmetric keypairs are in use, @bob will need to know which of them was used to
  /// encrypt [sharedKeyEnc]. [skeEncKeyName] will only be null when the legacy default public key
  /// was used; conversely if the legacy default public key was used then [skeEncKeyName] must be
  /// null. Non-null values _must_ look like this: `<keyName>.__public_keys.<namespace>` - i.e. must not include
  /// either the visibility prefix, which is always `public:`, nor the ownership suffix, which is always
  /// the receiving atSign (in this case `@bob`)
  String? skeEncKeyName;

  /// The name of the algorithm used to encrypt the [sharedKeyEnc]
  ///
  /// When [sharedKeyEnc] is provided in the metadata, [skeEncAlgo] is the name of the algorithm
  /// which was used to encrypt that shared key, using the public key at [skeEncKeyName].
  /// * The default algorithm is `RSA`
  String? skeEncAlgo;

  /// Immutable records may not be changed. They can be deleted, however
  /// deleting an immutable record will require the `force:` flag to be set
  /// when executing the `delete` verb.
  bool immutable = false;

  @override
  String toString() {
    return 'Metadata{${jsonEncode(toJson())}}';
  }

  /// Creates a fragment which can be included in any atProtocol commands which use
  /// Metadata - e.g. `update`, `update:meta` and `notify`
  String toAtProtocolFragment() {
    StringBuffer sb = StringBuffer();

    // NB The order of the verb parameters is important - it MUST match the order
    // in the regular expressions [VerbSyntax.update] and [VerbSyntax.update_meta]
    if (ttl != null) {
      sb.write(':ttl:$ttl');
    }
    if (ttb != null) {
      sb.write(':ttb:$ttb');
    }
    if (ttr != null) {
      sb.write(':ttr:$ttr');
    }
    if (ccd != null) {
      sb.write(':ccd:$ccd');
    }
    if (createdAt != null) {
      sb.write(':cAt:${VerbUtil.formatIso8601Micros(createdAt!)}');
    }
    if (updatedAt != null) {
      sb.write(':uAt:${VerbUtil.formatIso8601Micros(updatedAt!)}');
    }
    if (expiresAt != null) {
      sb.write(':eAt:${VerbUtil.formatIso8601Micros(expiresAt!)}');
    }
    if (availableAt != null) {
      sb.write(':aAt:${VerbUtil.formatIso8601Micros(availableAt!)}');
    }
    if (dataSignature.isNotNullOrEmpty) {
      sb.write(':${AtConstants.publicDataSignature}:$dataSignature');
    }
    if (sharedKeyStatus.isNotNullOrEmpty) {
      sb.write(':${AtConstants.sharedKeyStatus}:$sharedKeyStatus');
    }
    if (isBinary) {
      sb.write(':isBinary:$isBinary');
    }

    sb.write(':isEncrypted:$isEncrypted');

    if (sharedKeyEnc.isNotNullOrEmpty) {
      sb.write(':${AtConstants.sharedKeyEncrypted}:$sharedKeyEnc');
    }
    // ignore: deprecated_member_use_from_same_package
    if (pubKeyCS.isNotNullOrEmpty) {
      // ignore: deprecated_member_use_from_same_package
      sb.write(':${AtConstants.sharedWithPublicKeyCheckSum}:$pubKeyCS');
    }
    if (pubKeyHash != null) {
      sb.write(':${AtConstants.sharedWithPublicKeyHash}:${pubKeyHash!.hash}');
      sb.write(
          ':${AtConstants.sharedWithPublicKeyHashingAlgo}:${pubKeyHash!.hashingAlgo}');
    }
    if (encoding.isNotNullOrEmpty) {
      sb.write(':${AtConstants.encoding}:$encoding');
    }
    if (encKeyName.isNotNullOrEmpty) {
      sb.write(':${AtConstants.encryptingKeyName}:$encKeyName');
    }
    if (encAlgo.isNotNullOrEmpty) {
      sb.write(':${AtConstants.encryptingAlgo}:$encAlgo');
    }
    if (ivNonce.isNotNullOrEmpty) {
      sb.write(':${AtConstants.ivOrNonce}:$ivNonce');
    }
    if (skeEncKeyName.isNotNullOrEmpty) {
      sb.write(
          ':${AtConstants.sharedKeyEncryptedEncryptingKeyName}:$skeEncKeyName');
    }
    if (skeEncAlgo.isNotNullOrEmpty) {
      sb.write(':${AtConstants.sharedKeyEncryptedEncryptingAlgo}:$skeEncAlgo');
    }
    if (immutable) {
      sb.write(':${AtConstants.immutable}:$immutable');
    }
    return sb.toString();
  }

  Map toJson() {
    var map = {};
    map['availableAt'] = availableAt?.toUtc().toString();
    map['expiresAt'] = expiresAt?.toUtc().toString();
    map['refreshAt'] = refreshAt?.toUtc().toString();
    map[AtConstants.createdAt] = createdAt?.toUtc().toString();
    map[AtConstants.updatedAt] = updatedAt?.toUtc().toString();
    map['isPublic'] = isPublic;
    map[AtConstants.ttl] = ttl;
    map[AtConstants.ttb] = ttb;
    map[AtConstants.ttr] = ttr;
    map[AtConstants.ccd] = ccd;
    map[AtConstants.isBinary] = isBinary;
    map[AtConstants.isEncrypted] = isEncrypted;
    map[AtConstants.publicDataSignature] = dataSignature;
    map[AtConstants.sharedKeyStatus] = sharedKeyStatus;
    map[AtConstants.sharedKeyEncrypted] = sharedKeyEnc;
    // ignore: deprecated_member_use_from_same_package
    map[AtConstants.sharedWithPublicKeyCheckSum] = pubKeyCS;
    map[AtConstants.sharedWithPublicKeyHash] = pubKeyHash?.toJson();
    map[AtConstants.encoding] = encoding;
    map[AtConstants.encryptingKeyName] = encKeyName;
    map[AtConstants.encryptingAlgo] = encAlgo;
    map[AtConstants.ivOrNonce] = ivNonce;
    map[AtConstants.sharedKeyEncryptedEncryptingKeyName] = skeEncKeyName;
    map[AtConstants.sharedKeyEncryptedEncryptingAlgo] = skeEncAlgo;
    map[AtConstants.immutable] = immutable;
    map['namespaceAware'] = namespaceAware;
    map['isCached'] = isCached;

    return map;
  }

  static Metadata fromJson(Map json) {
    var metaData = Metadata();

    metaData.expiresAt =
        (json['expiresAt'] == null || json['expiresAt'] == 'null')
            ? null
            : DateTime.parse(json['expiresAt']);
    metaData.refreshAt =
        (json['refreshAt'] == null || json['refreshAt'] == 'null')
            ? null
            : DateTime.parse(json['refreshAt']);
    metaData.availableAt =
        (json['availableAt'] == null || json['availableAt'] == 'null')
            ? null
            : DateTime.parse(json['availableAt']);
    metaData.createdAt = (json[AtConstants.createdAt] == null ||
            json[AtConstants.createdAt] == 'null')
        ? null
        : DateTime.parse(json[AtConstants.createdAt]);
    metaData.updatedAt = (json[AtConstants.updatedAt] == null ||
            json[AtConstants.updatedAt] == 'null')
        ? null
        : DateTime.parse(json[AtConstants.updatedAt]);
    metaData.ttl = (json[AtConstants.ttl] is String)
        ? int.parse(json[AtConstants.ttl])
        : (json[AtConstants.ttl] == null)
            ? 0
            : json[AtConstants.ttl];
    metaData.ttb = (json[AtConstants.ttb] is String)
        ? int.parse(json[AtConstants.ttb])
        : (json[AtConstants.ttb] == null)
            ? 0
            : json[AtConstants.ttb];
    metaData.ttr = (json[AtConstants.ttr] is String)
        ? int.parse(json[AtConstants.ttr])
        : (json[AtConstants.ttr] == null)
            ? 0
            : json[AtConstants.ttr];
    metaData.ccd = json[AtConstants.ccd];
    metaData.isBinary = json[AtConstants.isBinary];
    metaData.isEncrypted = json[AtConstants.isEncrypted];
    metaData.isPublic = json[AtConstants.isPublic];
    metaData.dataSignature = json[AtConstants.publicDataSignature];
    metaData.sharedKeyStatus = json[AtConstants.sharedKeyStatus];
    metaData.sharedKeyEnc = json[AtConstants.sharedKeyEncrypted];
    // ignore: deprecated_member_use_from_same_package
    metaData.pubKeyCS = json[AtConstants.sharedWithPublicKeyCheckSum];
    metaData.pubKeyHash =
        PublicKeyHash.fromJson(json[AtConstants.sharedWithPublicKeyHash]);
    metaData.encoding = json[AtConstants.encoding];
    metaData.encKeyName = json[AtConstants.encryptingKeyName];
    metaData.encAlgo = json[AtConstants.encryptingAlgo];
    metaData.ivNonce = json[AtConstants.ivOrNonce];
    metaData.skeEncKeyName =
        json[AtConstants.sharedKeyEncryptedEncryptingKeyName];
    metaData.skeEncAlgo = json[AtConstants.sharedKeyEncryptedEncryptingAlgo];
    metaData.namespaceAware = json['namespaceAware'] ?? false;
    metaData.immutable = json[AtConstants.immutable] ?? false;

    return metaData;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Metadata &&
          runtimeType == other.runtimeType &&
          ttl == other.ttl &&
          ttb == other.ttb &&
          ttr == other.ttr &&
          ccd == other.ccd &&
          availableAt == other.availableAt &&
          expiresAt == other.expiresAt &&
          refreshAt == other.refreshAt &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          dataSignature == other.dataSignature &&
          sharedKeyStatus == other.sharedKeyStatus &&
          isPublic == other.isPublic &&
          isHidden == other.isHidden &&
          namespaceAware == other.namespaceAware &&
          isBinary == other.isBinary &&
          isEncrypted == other.isEncrypted &&
          isCached == other.isCached &&
          sharedKeyEnc == other.sharedKeyEnc &&
          // ignore: deprecated_member_use_from_same_package
          pubKeyCS == other.pubKeyCS &&
          pubKeyHash == other.pubKeyHash &&
          encoding == other.encoding &&
          encKeyName == other.encKeyName &&
          encAlgo == other.encAlgo &&
          ivNonce == other.ivNonce &&
          skeEncKeyName == other.skeEncKeyName &&
          skeEncAlgo == other.skeEncAlgo &&
          immutable == other.immutable;

  @override
  int get hashCode =>
      ttl.hashCode ^
      ttb.hashCode ^
      ttr.hashCode ^
      ccd.hashCode ^
      availableAt.hashCode ^
      expiresAt.hashCode ^
      refreshAt.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode ^
      dataSignature.hashCode ^
      sharedKeyStatus.hashCode ^
      isPublic.hashCode ^
      isHidden.hashCode ^
      namespaceAware.hashCode ^
      isBinary.hashCode ^
      isEncrypted.hashCode ^
      isCached.hashCode ^
      sharedKeyEnc.hashCode ^
      // ignore: deprecated_member_use_from_same_package
      pubKeyCS.hashCode ^
      pubKeyHash.hashCode ^
      encoding.hashCode ^
      encKeyName.hashCode ^
      encAlgo.hashCode ^
      ivNonce.hashCode ^
      skeEncKeyName.hashCode ^
      skeEncAlgo.hashCode ^
      immutable.hashCode;
}

class AtValue {
  dynamic value;
  Metadata? metadata;

  @override
  String toString() {
    return 'AtValue{value: $value, metadata: $metadata}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AtValue &&
          runtimeType == other.runtimeType &&
          value == other.value &&
          metadata == other.metadata;

  @override
  int get hashCode => value.hashCode ^ metadata.hashCode;
}
