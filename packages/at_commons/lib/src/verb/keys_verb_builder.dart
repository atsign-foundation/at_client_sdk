import 'package:at_commons/src/verb/verb_builder.dart';

/// KeysVerbBuilder is used to build commands for key (encryption keys) specific put, get and delete operations.
class KeysVerbBuilder implements VerbBuilder {
  /// specifies the keys verb operation (get|put|delete)
  final String operation;

  /// visibility - public. Used for public encryption key from asymmetric keypair
  /// visibility - private. Used for private encryption key from asymmetric keypair
  /// visibility - self. Used for self encryption key.
  String? visibility;

  /// Unique name to identify this key
  String? keyName;

  /// namespace of the key e.g __global, __private
  String? namespace;

  /// name of the app which requested this key operation
  String? appName;

  /// name of the device which requested this key operation
  String? deviceName;

  /// Encryption key type e.g rsa2048,aes256, ecdsa
  String? keyType;

  /// if the [value] is encrypted, then [encryptionKeyName] specifies [keyName] which encrypted the [value]
  String? encryptionKeyName;

  /// value of the key. Can be plain text for public keys and encrypted for other keys.
  String? value;

  KeysVerbBuilder(this.operation);

  @override
  String buildCommand() {
    var sb = StringBuffer("keys:")
      ..write(operation)
      ..write(':$visibility')
      ..write(_getValueWithParamName('namespace', namespace))
      ..write(_getValueWithParamName('appName', appName))
      ..write(_getValueWithParamName('deviceName', deviceName))
      ..write(_getValueWithParamName('keyType', keyType))
      ..write(_getValueWithParamName('encryptionKeyName', encryptionKeyName))
      ..write(_getValueWithParamName('keyName', keyName))
      ..write(
          _getValue(value)) //value is prepended with a whitespace as per regex
      ..write('\n');

    return sb.toString();
  }

  String _getValue(String? paramValue) {
    if (paramValue != null && paramValue.isNotEmpty && paramValue != 'null') {
      return ' $paramValue'; //value is prepended with a whitespace as per regex
    }
    return '';
  }

  String _getValueWithParamName(String paramName, String? paramValue) {
    if (paramValue != null && paramValue.isNotEmpty && paramValue != 'null') {
      return ':$paramName:$paramValue';
    }
    return '';
  }

  @override
  bool checkParams() {
    return operation.isNotEmpty;
  }
}
