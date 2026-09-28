import 'package:http/http.dart';

enum HttpMethod { get, post }

enum RegistrarApiEndpoint {
  // Atsign authentication
  requestOtp('/authenticate/atsign', HttpMethod.post),
  validateOtp('/authenticate/atsign/activate', HttpMethod.post),

  // Check availability and/or activate an atSign in one call
  registerAtsign('/register-atsign/', HttpMethod.post),

  // AtSign deletion (Super API key)
  manageAtsigns('/manage-atsigns', HttpMethod.post);

  final String path;
  final HttpMethod method;
  const RegistrarApiEndpoint(this.path, this.method);
}

abstract interface class Registrar {
  String get registrarUrl;
  String get apiKey;

  /// Core API request method that handles HTTP communication with the registrar
  ///
  /// [endpoint] - The API endpoint to call
  /// [data] - Request body data (for POST) or query parameters (for GET)
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
  /// [operation] - 'lookup' (check availability only) or 'register' (check +
  /// activate, returning a cramkey).
  /// [startAtServer] - Optional; pass 'false' to skip secondary creation on
  /// registration (no cramkey will be returned in that case).
  ///
  /// Returns a map that may contain 'cramkey' (register), or 'atSign' +
  /// 'message' (lookup / availability confirmation).
  Future<Map<String, dynamic>> registerAtSign({
    String? atSign,
    required String operation,
    String? startAtServer,
  });

  // ===========================================================================
  // AtSign Deletion Methods (Super API key)
  // ===========================================================================

  /// Generates a one-time delete token for [atSigns].
  ///
  /// Returns { 'token': String, 'atSigns': List, 'skippedAtSigns': List }
  Future<Map<String, dynamic>> generateAtSignDeleteToken(
      List<String> atSigns);

  /// Deletes [atSigns] using a previously generated delete [token].
  ///
  /// Returns { 'deleted': List, 'failed': List }
  Future<Map<String, dynamic>> deleteAtSigns({
    required String token,
    required List<String> atSigns,
  });
}
