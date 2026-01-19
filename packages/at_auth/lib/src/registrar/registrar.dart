import 'package:http/http.dart';

enum ActivateApiEndpoint {
  login('/authenticate/atsign'),
  validate('/authenticate/atsign/activate');

  final String path;
  const ActivateApiEndpoint(this.path);
}

abstract interface class Registrar {
  String get registrarUrl;
  String get apiKey;

  Future<Response> registrarApiRequest(
    ActivateApiEndpoint endpoint,
    Map<String, String> data,
  );

  Future<bool> sendActivationOtp(String atSign);

  Future<String?> verifyActivation({
    required String atSign,
    required String otp,
  });
}
