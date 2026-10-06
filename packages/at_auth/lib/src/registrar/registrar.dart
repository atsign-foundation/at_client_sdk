import 'package:http/http.dart';

enum RegistrarApiEndpoint {
  // Atsign authentication
  requestOtp('/authenticate/atsign', HttpMethod.post),
  validateOtp('/authenticate/atsign/activate', HttpMethod.post),

  // Check availability and/or activate an atSign in one call
  registerAtsign('/register-atsign/', HttpMethod.post),

  // AtSign deletion (Super API key)
  manageAtsigns('/manage-atsigns/', HttpMethod.post);

  final String path;
  final HttpMethod method;
  const RegistrarApiEndpoint(this.path, this.method);
}

enum HttpMethod { post }

/// What [Registrar.registerAtSign] asks the server to do: just check whether
/// [atSign] is available, or check and activate it in the same call.
enum RegisterOperation {
  lookup,
  register;

  String get wireValue => name;
}

/// The result of [Registrar.registerAtSign].
///
/// [cramKey] is set only when [RegisterOperation.register] succeeds and the
/// server started a secondary (i.e. `startAtServer` was not `false`).
/// [atSign] and [message] are set for a lookup, or alongside [cramKey] when
/// the server echoes them back on a register.
class RegisterAtSignResult {
  final String? cramKey;
  final String? atSign;
  final String? message;

  const RegisterAtSignResult({this.cramKey, this.atSign, this.message});
}

abstract interface class Registrar {
  String get registrarUrl;
  String get apiKey;

  /// Core API request method that handles HTTP communication with the registrar
  ///
  /// [endpoint] - The API endpoint to call
  /// [data] - Request body data
  /// [requiresAuth] - Whether to include the Authorization header (default: true)
  Future<Response> registrarApiRequest(
    RegistrarApiEndpoint endpoint,
    Map<String, dynamic> data, {
    bool requiresAuth = true,
  });

  // ===========================================================================
  // AtSign Activation Methods
  // ===========================================================================

  /// Sends an activation OTP to the email/phone associated with the atSign
  Future<bool> sendActivationOtp(String atSign);

  /// Verifies the activation OTP and returns the CRAM key
  Future<String?> verifyActivation({
    required String atSign,
    required String otp,
  });

  // ===========================================================================
  // AtSign Registration/Activation Methods (v4, hybrid/custom atSigns)
  // ===========================================================================

  /// Checks availability and/or activates an atSign in one call.
  ///
  /// [atSign] - Optional. If omitted, the server generates one.
  /// [operation] - [RegisterOperation.lookup] (check availability only) or
  /// [RegisterOperation.register] (check + activate, returning a cramkey).
  /// [startAtServer] - Optional; pass `false` to skip secondary creation on
  /// registration (no cramkey will be returned in that case).
  Future<RegisterAtSignResult> registerAtSign({
    String? atSign,
    required RegisterOperation operation,
    bool? startAtServer,
  });
}
