import 'package:at_commons/at_commons.dart';

class AtAuthenticationException extends AtException {
  AtAuthenticationException(super.message);
}

class AtPasswordRequiredException extends AtDecryptionException{
  AtPasswordRequiredException(super.message);
}