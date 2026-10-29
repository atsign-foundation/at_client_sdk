import 'package:at_client_cli/src/register/api_call_status.dart';

/// What a call to the atSign registrar answered: its [data], whether it
/// succeeded, and the message when it did not.
class RegisterApiResult {
  dynamic data;

  late ApiCallStatus apiCallStatus;

  String exceptionMessage = '';
}
