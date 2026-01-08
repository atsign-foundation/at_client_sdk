import 'package:at_client/at_client.dart';

class AtOnboardingException extends AtClientException {
  AtOnboardingException(super.message, {super.intent, super.exceptionScenario})
      : super.message();
}

class AtActivateException extends AtOnboardingException {
  AtActivateException(super.message, {super.intent, super.exceptionScenario});
}

class AtAuthenticationFailureException extends AtOnboardingException {
  AtAuthenticationFailureException(super.message,
      {super.intent, super.exceptionScenario});
}

class InvalidResourceException extends AtOnboardingException {
  InvalidResourceException(super.message,
      {super.intent, super.exceptionScenario});
}

class AtKeysFileExistsException extends AtOnboardingException {
  AtKeysFileExistsException(super.message,
      {super.intent, super.exceptionScenario});
}
