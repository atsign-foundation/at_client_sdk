import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/registrar/registrar.dart';
import 'package:at_auth/src/at_auth.dart';

import 'package:http/http.dart';
import 'package:http/io_client.dart';

const apiBase = '/api/app/v4';

class RegistrarService implements Registrar{
	@override
	final String registrarUrl;
	@override
	final String apiKey;
  late final IOClient _http;
  RegistrarService({
    required this.registrarUrl,
    required this.apiKey,
    AtAuth? atAuth,
  }) {
    var innerClient = HttpClient();
    innerClient.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    _http = IOClient(innerClient);
  }
	
	@override
  Future<Response> registrarApiRequest(
    ActivateApiEndpoint endpoint,
    Map<String, String?> data,
  ) async {
    Uri url = Uri.https(registrarUrl, "$apiBase${endpoint.path}");

    return _http.post(
      url,
      body: jsonEncode(data),
      headers: <String, String>{
        'Authorization': apiKey,
        'Content-Type': 'application/json',
      },
    );
  }

	@override
  Future<bool> sendActivationOtp(String atsign) async {
    var res = await registrarApiRequest(ActivateApiEndpoint.login, {
      'atsign': atsign,
    });
    if (res.statusCode != 200) {
      return false;
    }
    var payload = jsonDecode(res.body);
    if (payload["message"] != "Sent Successfully") {
      return false;
    }
    return true;
  }

	@override
  Future<String?> verifyActivation({
    required String atSign,
    required String otp,
  }) async {
    var res = await registrarApiRequest(ActivateApiEndpoint.validate, {
      'atsign': atSign,
      'otp': otp,
    });
    if (res.statusCode != 200) {
      throw Exception('Failed to verify activation: ${res.reasonPhrase} - ${res.body}');
    }
    var payload = jsonDecode(res.body);
    if (payload["message"] != "Verified") {
      // The toString is for typesafety & to prevent unexpected crashes
      throw Exception('Verification failed: ${payload["message"].toString()}');
    }
    String cramkey = payload["cramkey"]?.split(':').last ?? '';
    return cramkey;
  }
}
