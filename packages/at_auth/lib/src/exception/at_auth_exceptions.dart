import 'package:at_commons/at_commons.dart';

class AtAuthenticationException extends AtException {
  AtAuthenticationException(super.message);
}

class AtKeysFileOverwriteException extends AtException {
  AtKeysFileOverwriteException(super.message);
}

class AtKeysParseException extends AtException {
  AtKeysParseException(super.message);
}

class AtKeysValidationException extends AtException {
  AtKeysValidationException(super.message);
}

class AtKeysUnsupportedVersionException extends AtKeysValidationException {
  AtKeysUnsupportedVersionException(super.message);
}

class AtKeysUnsupportedAlgorithmException extends AtKeysValidationException {
  AtKeysUnsupportedAlgorithmException(super.message);
}

class AtKeysProtectionException extends AtKeysValidationException {
  AtKeysProtectionException(super.message);
}

class AtKeysDecryptionException extends AtDecryptionException {
  AtKeysDecryptionException(super.message);
}
