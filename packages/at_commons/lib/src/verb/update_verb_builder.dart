import 'dart:collection';
import 'dart:convert';

import 'package:at_commons/at_commons.dart';
import 'package:at_commons/src/verb/abstract_verb_builder.dart';

/// Update builder generates a command to update [value] for a key [atKey] in the secondary server of [sharedBy].
/// Use [getBuilder] method if you want to convert command to a builder.
///
///  * Setting a public value for the key 'phone'
///
///  * When isPublic is set to true, throws [InvalidAtKeyException] if isLocal is set to true or sharedWith is populated
///```dart
///  var updateBuilder = UpdateVerbBuilder()
///  ..isPublic=true
///  ..key='phone'
///  ..sharedBy='bob'
///  ..value='+1-1234';
///```
///
///   * @bob setting a value for the key 'phone' to share with @alice
///
///   * When sharedWith is populated, throws [InvalidAtKeyException] if isLocal or isPublic is set to true
///```dart
///  var updateBuilder = UpdateVerbBuilder()
///  ..sharedWith=’alice’
///  ..key='phone'
///  ..sharedBy='bob'
///  ..value='+1-5678';
///```
///
/// * Creating a local key for storing data that does not sync
///
/// * When isLocal is set to true, throws [InvalidAtKeyException] if isPublic is set to true or sharedWith is populated
///```dart
///  var updateBuilder = UpdateVerbBuilder()
///                      ..isLocal = true
///                      ..key = 'preferences'
///                      ..sharedBy = '@bob'
///                      ..value = jsonEncode(myPrefObj)
///```
class UpdateVerbBuilder extends AbstractVerbBuilder {
  /// Value of the key typically in string format. Images, files, etc.,
  /// must be converted to unicode string before storing.
  dynamic value;

  String? operation;

  bool isJson = false;

  /// When true, the server is asked not to write a commit-log entry for this
  /// update. Emitted on the wire as the `:nc` flag, valid for both the
  /// metadata-fragment and the `update:json:...` forms.
  bool noCommit = false;

  @override
  String buildCommand() {
    String atKeyName = buildKey();
    var noCommitFragment = noCommit ? ':nc' : '';
    if (isJson) {
      var updateParams = UpdateParams()
        ..atKey = atKeyName
        ..value = value
        ..sharedBy = atKey.sharedBy
        ..sharedWith = atKey.sharedWith
        ..metadata = atKey.metadata;
      var json = updateParams.toJson();
      var command = 'update$noCommitFragment:json:${jsonEncode(json)}\n';
      return command;
    } else {
      var metadataFragment = atKey.metadata.toAtProtocolFragment();
      var command =
          'update$noCommitFragment$metadataFragment:$atKeyName $value\n';
      return command;
    }
  }

  /// Get the string representation (e.g. `@bob:city.address.my_app@alice`) of the key
  /// for which this update command is being built.
  ///
  /// First of all calls [validateKey]. If validation fails an exception will be thrown. If not
  /// then we return the string representation of the key.
  String buildKey() {
    validateKey();
    return super.atKey.toString();
  }

  String buildCommandForMeta() {
    String atKeyName = buildKey();
    var metadataFragment = atKey.metadata.toAtProtocolFragment();
    var noCommitFragment = noCommit ? ':nc' : '';
    var command = 'update:meta$noCommitFragment:$atKeyName$metadataFragment\n';
    return command;
  }

  static UpdateVerbBuilder? getBuilder(String command) {
    if (command != command.trim()) {
      throw IllegalArgumentException(
          'Commands may not have leading or trailing whitespace');
    }
    var builder = UpdateVerbBuilder();
    HashMap<String, String?>? verbParams;
    if (command.contains(AtConstants.updateMeta)) {
      verbParams = VerbUtil.getVerbParam(VerbSyntax.update_meta, command);
      builder.operation = AtConstants.updateMeta;
    } else {
      verbParams = VerbUtil.getVerbParam(VerbSyntax.update, command);
    }
    if (verbParams == null) {
      return null;
    }
    builder.atKey.metadata.isPublic =
        verbParams[AtConstants.publicScopeParam] == 'public';
    builder.atKey.sharedWith =
        VerbUtil.formatAtSign(verbParams[AtConstants.forAtSign]);
    builder.atKey.sharedBy =
        VerbUtil.formatAtSign(verbParams[AtConstants.atSign]);
    builder.atKey.key = verbParams[AtConstants.atKey]!;
    builder.value = verbParams[AtConstants.atValue];
    if (builder.value is String) {
      builder.value = VerbUtil.replaceNewline(builder.value);
    }
    if (verbParams[AtConstants.ttl] != null) {
      builder.atKey.metadata.ttl = int.parse(verbParams[AtConstants.ttl]!);
    }
    if (verbParams[AtConstants.ttb] != null) {
      builder.atKey.metadata.ttb = int.parse(verbParams[AtConstants.ttb]!);
    }
    if (verbParams[AtConstants.ttr] != null) {
      builder.atKey.metadata.ttr = int.parse(verbParams[AtConstants.ttr]!);
    }
    if (verbParams[AtConstants.ccd] != null) {
      builder.atKey.metadata.ccd =
          _getBoolVerbParams(verbParams[AtConstants.ccd]!);
    }
    builder.noCommit = verbParams['noCommit'] != null;
    if (verbParams[AtConstants.createdAt] != null) {
      builder.atKey.metadata.createdAt =
          DateTime.parse(verbParams[AtConstants.createdAt]!);
    }
    if (verbParams[AtConstants.updatedAt] != null) {
      builder.atKey.metadata.updatedAt =
          DateTime.parse(verbParams[AtConstants.updatedAt]!);
    }
    if (verbParams['expiresAt'] != null) {
      builder.atKey.metadata.expiresAt =
          DateTime.parse(verbParams['expiresAt']!);
    }
    if (verbParams['availableAt'] != null) {
      builder.atKey.metadata.availableAt =
          DateTime.parse(verbParams['availableAt']!);
    }

    builder.atKey.metadata.dataSignature =
        verbParams[AtConstants.publicDataSignature];

    if (verbParams[AtConstants.isBinary] != null) {
      builder.atKey.metadata.isBinary =
          _getBoolVerbParams(verbParams[AtConstants.isBinary]!);
    }
    if (verbParams[AtConstants.isEncrypted] != null) {
      builder.atKey.metadata.isEncrypted =
          _getBoolVerbParams(verbParams[AtConstants.isEncrypted]!);
    }

    builder.atKey.metadata.sharedKeyEnc =
        verbParams[AtConstants.sharedKeyEncrypted];
    // ignore: deprecated_member_use_from_same_package
    builder.atKey.metadata.pubKeyCS =
        verbParams[AtConstants.sharedWithPublicKeyCheckSum];
    builder.atKey.metadata.sharedKeyStatus =
        verbParams[AtConstants.sharedKeyStatus];
    builder.atKey.metadata.encoding = verbParams[AtConstants.encoding];
    builder.atKey.metadata.encKeyName =
        verbParams[AtConstants.encryptingKeyName];
    builder.atKey.metadata.encAlgo = verbParams[AtConstants.encryptingAlgo];
    builder.atKey.metadata.ivNonce = verbParams[AtConstants.ivOrNonce];
    builder.atKey.metadata.skeEncKeyName =
        verbParams[AtConstants.sharedKeyEncryptedEncryptingKeyName];
    builder.atKey.metadata.skeEncAlgo =
        verbParams[AtConstants.sharedKeyEncryptedEncryptingAlgo];

    if (verbParams[AtConstants.sharedWithPublicKeyHash] != null &&
        verbParams[AtConstants.sharedWithPublicKeyHashingAlgo] != null) {
      builder.atKey.metadata.pubKeyHash = PublicKeyHash(
          verbParams[AtConstants.sharedWithPublicKeyHash]!,
          verbParams[AtConstants.sharedWithPublicKeyHashingAlgo]!);
    }

    if (verbParams[AtConstants.immutable] != null) {
      builder.atKey.metadata.immutable =
          _getBoolVerbParams(verbParams[AtConstants.immutable]!);
    }
    builder.value = verbParams[AtConstants.value];

    return builder;
  }

  @override
  bool checkParams() {
    var isValid = true;
    if ((atKey.key.isEmpty || value == null) ||
        (atKey.metadata.isPublic == true && atKey.sharedWith != null)) {
      isValid = false;
    }
    return isValid;
  }

  static bool _getBoolVerbParams(String arg1) {
    if (arg1.toLowerCase() == 'true') {
      return true;
    }
    return false;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdateVerbBuilder &&
          runtimeType == other.runtimeType &&
          atKey.key == other.atKey.key &&
          value == other.value &&
          atKey.sharedWith == other.atKey.sharedWith &&
          atKey.sharedBy == other.atKey.sharedBy &&
          atKey.metadata.isPublic == other.atKey.metadata.isPublic &&
          atKey.metadata.isBinary == other.atKey.metadata.isBinary &&
          atKey.metadata.isEncrypted == other.atKey.metadata.isEncrypted &&
          operation == other.operation &&
          isJson == other.isJson &&
          atKey.isLocal == other.atKey.isLocal &&
          atKey.metadata.ttl == other.atKey.metadata.ttl &&
          atKey.metadata.ttb == other.atKey.metadata.ttb &&
          atKey.metadata.ttr == other.atKey.metadata.ttr &&
          atKey.metadata.ccd == other.atKey.metadata.ccd &&
          atKey.metadata.createdAt == other.atKey.metadata.createdAt &&
          atKey.metadata.updatedAt == other.atKey.metadata.updatedAt &&
          atKey.metadata.expiresAt == other.atKey.metadata.expiresAt &&
          atKey.metadata.availableAt == other.atKey.metadata.availableAt &&
          noCommit == other.noCommit &&
          atKey.metadata.dataSignature == other.atKey.metadata.dataSignature &&
          atKey.metadata.sharedKeyStatus ==
              other.atKey.metadata.sharedKeyStatus &&
          atKey.metadata.sharedKeyEnc == other.atKey.metadata.sharedKeyEnc &&
          // ignore: deprecated_member_use_from_same_package
          atKey.metadata.pubKeyCS == other.atKey.metadata.pubKeyCS &&
          atKey.metadata.encoding == other.atKey.metadata.encoding &&
          atKey.metadata.encKeyName == other.atKey.metadata.encKeyName &&
          atKey.metadata.encAlgo == other.atKey.metadata.encAlgo &&
          atKey.metadata.ivNonce == other.atKey.metadata.ivNonce &&
          atKey.metadata.skeEncKeyName == other.atKey.metadata.skeEncKeyName &&
          atKey.metadata.skeEncAlgo == other.atKey.metadata.skeEncAlgo;

  @override
  int get hashCode =>
      atKey.key.hashCode ^
      value.hashCode ^
      atKey.sharedWith.hashCode ^
      atKey.sharedBy.hashCode ^
      atKey.metadata.isPublic.hashCode ^
      atKey.metadata.isBinary.hashCode ^
      atKey.metadata.isEncrypted.hashCode ^
      operation.hashCode ^
      isJson.hashCode ^
      atKey.isLocal.hashCode ^
      atKey.metadata.ttl.hashCode ^
      atKey.metadata.ttb.hashCode ^
      atKey.metadata.ttr.hashCode ^
      atKey.metadata.ccd.hashCode ^
      atKey.metadata.createdAt.hashCode ^
      atKey.metadata.updatedAt.hashCode ^
      atKey.metadata.expiresAt.hashCode ^
      atKey.metadata.availableAt.hashCode ^
      noCommit.hashCode ^
      atKey.metadata.dataSignature.hashCode ^
      atKey.metadata.sharedKeyStatus.hashCode ^
      atKey.metadata.sharedKeyEnc.hashCode ^
      // ignore: deprecated_member_use_from_same_package
      atKey.metadata.pubKeyCS.hashCode ^
      atKey.metadata.encoding.hashCode ^
      atKey.metadata.encKeyName.hashCode ^
      atKey.metadata.encAlgo.hashCode ^
      atKey.metadata.ivNonce.hashCode ^
      atKey.metadata.skeEncKeyName.hashCode ^
      atKey.metadata.skeEncAlgo.hashCode;
}
