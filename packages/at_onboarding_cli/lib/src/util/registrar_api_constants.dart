class RegistrarApiConstants {
  /// Authorities
  static const String apiHostProd = 'my.atsign.com';
  static const String apiHostStaging = 'my.atsign.wtf';

  /// API Paths
  static const String pathGetFreeAtSign = '/api/app/v3/get-free-atsign';
  static const String pathRegisterAtSign = '/api/app/v3/register-person';
  static const String pathValidateOtp = '/api/app/v3/validate-person';
  static const String requestAuthenticationOtpPath =
      '/api/app/v3/authenticate/atsign';
  static const String getCramKeyWithOtpPath =
      '/api/app/v3/authenticate/atsign/activate';

  /// API headers
  static const String contentType = 'application/json';
  static const String authorization = '477b-876u-bcez-c42z-6a3d';
}
