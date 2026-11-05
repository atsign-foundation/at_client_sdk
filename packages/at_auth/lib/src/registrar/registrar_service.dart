import 'dart:convert';

import 'package:at_auth/src/registrar/registrar.dart';
import 'package:at_auth/src/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

import 'package:http/http.dart' as http;

const apiBase = '/api/app/v4';

class RegistrarService implements Registrar {
  @override
  final String registrarUrl;
  @override
  final String apiKey;
  late final http.Client _http;
  final AtSignLogger _logger = AtSignLogger('RegistrarService');

  RegistrarService({
    required this.registrarUrl,
    required this.apiKey,
    AtAuth? atAuth,
    http.Client? httpClient,
  }) {
    if (apiKey.trim().isEmpty) {
      throw AtException('Registrar API key is required and cannot be empty.');
    }
    // A plain `package:http` client: it validates certificates, and it works
    // under WASM because it reaches the network without `dart:io`. A caller
    // needing the `dart:io` stack — to talk to a registrar whose certificate
    // does not validate, for instance — passes `RegistrarIoClient.create()`
    // from `package:at_auth/at_auth_io.dart` as [httpClient].
    _http = httpClient ?? http.Client();
  }

  @override
  Future<http.Response> registrarApiRequest(
    RegistrarApiEndpoint endpoint,
    Map<String, dynamic> data, {
    bool requiresAuth = true,
  }) async {
    Uri url = Uri.https(registrarUrl, "$apiBase${endpoint.path}");

    Map<String, String> headers = {'Content-Type': 'application/json'};
    if (requiresAuth) {
      headers['Authorization'] = apiKey;
    }

    final response = await _http.post(
      url,
      body: jsonEncode(data),
      headers: headers,
    );
    _throwIfAuthFailure(response, endpoint, requiresAuth);
    return response;
  }

  void _throwIfAuthFailure(
    http.Response response,
    RegistrarApiEndpoint endpoint,
    bool requiresAuth,
  ) {
    if (!requiresAuth) return;
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw AtException(
        'Registrar authentication failed: invalid or missing API key. '
        'endpoint=${endpoint.path}, status=${response.statusCode}',
      );
    }
  }

  // AtSign Activation Methods
  @override
  //TODO: this should return void, throw if fails
  Future<bool> sendActivationOtp(String atsign) async {
    var res = await registrarApiRequest(
      RegistrarApiEndpoint.requestOtp,
      {'atsign': atsign},
    );
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
  //TODO: this really should be Future<String>
  Future<String?> verifyActivation({
    required String atSign,
    required String otp,
  }) async {
    var res = await registrarApiRequest(
      RegistrarApiEndpoint.validateOtp,
      {'atsign': atSign, 'otp': otp},
    );
    if (res.statusCode != 200) {
      _logger.warning('Failed to verify activation: ${res.body}');
      throw Exception('Failed to verify activation: ${res.reasonPhrase}');
    }
    var payload = jsonDecode(res.body);
    if (payload["message"] != "Verified") {
      throw Exception('Verification failed: ${payload["message"].toString()}');
    }

    String? cramKey = payload["cramkey"]?.split(':').last;
    if (cramKey == null) {
      throw Exception('Verification failed: cramKey missing from payload');
    }
    return cramKey;
  }

  // AtSign Registration/Activation Methods (v4, hybrid/custom atSigns)
  @override
  Future<RegisterAtSignResult> registerAtSign({
    String? atSign,
    required RegisterOperation operation,
    bool? startAtServer,
  }) async {
    Map<String, dynamic> data = {'operation': operation.wireValue};
    if (atSign != null) data['atSign'] = atSign;
    if (startAtServer != null) {
      data['startatServer'] = startAtServer.toString();
    }

    var res = await registrarApiRequest(
      RegistrarApiEndpoint.registerAtsign,
      data,
    );
    if (res.statusCode != 200) {
      throw Exception(
          'Failed to register atSign: ${res.reasonPhrase} - ${res.body}');
    }
    var payload = jsonDecode(res.body);
    if (payload["status"] != "success") {
      throw Exception(
          'Failed to register atSign: ${payload["message"] ?? "Unknown error"}');
    }

    String? cramKey = payload["cramkey"]?.split(':').last;
    if (operation == RegisterOperation.register &&
        startAtServer != false &&
        cramKey == null) {
      throw Exception(
          'Failed to register atSign: cramKey missing from payload');
    }

    return RegisterAtSignResult(
      cramKey: cramKey,
      atSign: payload["atSign"],
      message: payload["message"],
    );
  }
}
