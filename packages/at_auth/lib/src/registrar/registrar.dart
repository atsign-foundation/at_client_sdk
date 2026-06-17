import 'package:at_commons/atsign.dart';
import 'package:http/http.dart';

enum HttpMethod { get, post }

enum RegistrarApiEndpoint {
  // Free atSign generation (Public)
  getFreeAtsign('/get-free-atsign/', HttpMethod.get),
  getFreeAtsignByCategory('/get-free-atsign/', HttpMethod.post),

  // Person registration (Email-based with OTP)
  registerPerson('/register-person/', HttpMethod.post),
  validatePerson('/validate-person/', HttpMethod.post),

  // Atsign authentication
  requestOtp('/authenticate/atsign', HttpMethod.post),
  validateOtp('/authenticate/atsign/activate', HttpMethod.post);

  final String path;
  final HttpMethod method;
  const RegistrarApiEndpoint(this.path, this.method);
}

/// Legacy enum name for backward compatibility
@Deprecated('Use RegistrarApiEndpoint instead')
typedef ActivateApiEndpoint = RegistrarApiEndpoint;

/// Backward compatibility extension for legacy enum values
extension ActivateApiEndpointLegacy on RegistrarApiEndpoint {
  /// Legacy alias for authenticateAtSign
  @Deprecated('Use RegistrarApiEndpoint.authenticateAtSign instead')
  static RegistrarApiEndpoint get login => RegistrarApiEndpoint.requestOtp;

  /// Legacy alias for validateAtSignActivation
  @Deprecated('Use RegistrarApiEndpoint.validateAtSignActivation instead')
  static RegistrarApiEndpoint get validate => RegistrarApiEndpoint.validateOtp;
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
    Map<String, String?> data, {
    bool requiresAuth = true,
  });

  // ===========================================================================
  // AtSign Activation Methods
  // ===========================================================================

  /// Sends an activation OTP to the email/phone associated with the atSign
  @Deprecated('Use requestActivationOtp instead')
  Future<bool> sendActivationOtp(String atSign);

  Future<void> requestActivationOtp(Atsign atsign);

  //TODO: change signatures to Atsign atsign

  /// Verifies the activation OTP and returns the CRAM key
  Future<String?> verifyActivation({
    required String atSign,
    required String otp,
  });

  // ===========================================================================
  // Free AtSign Generation Methods
  // ===========================================================================

  /// Generates a random free atSign
  ///
  /// Returns the generated atSign or null if generation failed
  Future<String?> getFreeAtSign();

  /// Generates a free atSign from specified categories
  ///
  /// [categories] - List of categories (zodiac, foods, colors, animals, sports, movies, music, hobbies)
  /// Returns the generated atSign or null if generation failed
  Future<String?> getFreeAtSignByCategory(List<String> categories);

  // ===========================================================================
  // Person Registration Methods (Email-based with OTP)
  // ===========================================================================

  /// Registers an atSign to an email address and sends OTP
  ///
  /// [atSign] - The atSign to register
  /// [email] - Email address to associate with the atSign
  /// [oldEmail] - Optional previous email address if changing email
  /// Throws an exception if registration fails (e.g., atSign already registered, email already in use)
  Future<void> registerPerson({
    required String atSign,
    required String email,
    String? oldEmail,
  });

  /// Validates the person registration using the OTP
  ///
  /// [atSign] - The atSign being validated
  /// [email] - Email address used for registration
  /// [otp] - 4-character OTP sent to email
  /// [confirmation] - Set to true if validating previously validated atSign
  /// note: if you have existing atsigns, you need to resend the same request with confirmation set to true
  ///
  /// Returns a map with validation results:
  /// - If new user: { 'success': true, 'cramkey': '...' }
  /// - If existing user: { 'atsigns': [...], 'newAtsign': '...' }
  Future<Map<String, dynamic>> validatePerson({
    required String atSign,
    required String email,
    required String otp,
    bool confirmation = false,
  });
}
