import 'package:at_commons/src/keystore/at_key.dart';
import 'package:at_commons/src/keystore/key_type.dart';

/// Implement a validation on a key
abstract class Validation {
  ValidationResult doValidate();
}

/// Validates String representation of a [AtKey]
/// For example String representation of a public key [PublicKey] will be public:phone.wavi@bob
abstract class AtKeyValidator {
  ValidationResult validate(String key, ValidationContext context);
}

/// Represents context of a validation
/// See [AtKeyValidator]
class ValidationContext {
  // Set it to the currentAtSign
  String? atSign;

  // It is being set in _initParams
  KeyType? type;

  // validate the ownership of the key
  bool validateOwnership = true;

  // enforce presence of namespace
  bool enforceNamespace = false;
}

/// Represents outcome of a key validation
/// See [AtKeyValidator] and [AtConcreteKeyValidator]
class ValidationResult {
  late bool isValid = false;
  late String failureReason = '';

  ValidationResult(this.failureReason);

  static ValidationResult noFailure() {
    return ValidationResult('')..isValid = true;
  }
}
