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
    Map<String, String?> data, {
    bool requiresAuth = true,
  }) async {
    Uri url = Uri.https(registrarUrl, "$apiBase${endpoint.path}");

    Map<String, String> headers = {'Content-Type': 'application/json'};
    if (requiresAuth) {
      headers['Authorization'] = apiKey;
    }

    // Handle GET vs POST requests
    if (endpoint.method == HttpMethod.get) {
      if (data.isNotEmpty) {
        url = url.replace(queryParameters: data);
      }
      final response = await _http.get(url, headers: headers);
      _throwIfAuthFailure(response, endpoint, requiresAuth);
      return response;
    } else {
      final response = await _http.post(
        url,
        body: jsonEncode(data),
        headers: headers,
      );
      _throwIfAuthFailure(response, endpoint, requiresAuth);
      return response;
    }
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

  // Free AtSign Generation Methods
  @override
  Future<String> getFreeAtSign() async {
    var res = await registrarApiRequest(
      RegistrarApiEndpoint.getFreeAtsign,
      {},
    );
    if (res.statusCode != 200) {
      throw Exception(
          'Failed to get free Atsign: ${res.reasonPhrase} - ${res.body}');
    }
    var payload = jsonDecode(res.body);
    if (payload["data"] == null) {
      throw Exception('Failed to get free Atsign: payload data is null');
    }
    if (payload["success"] == true) {
      return payload["data"]["atsign"];
    }
    throw Exception(
        'Failed to get free Atsign: ${payload["message"] ?? "Unknown error"}');
  }

  @override
  Future<String> getFreeAtSignByCategory(List<String> categories) async {
    Uri url = Uri.https(registrarUrl,
        "$apiBase${RegistrarApiEndpoint.getFreeAtsignByCategory.path}");

    var res = await _http.post(
      url,
      body: jsonEncode({'category': categories}),
      headers: {
        'Authorization': apiKey,
        'Content-Type': 'application/json',
      },
    );
    _throwIfAuthFailure(
        res, RegistrarApiEndpoint.getFreeAtsignByCategory, true);

    if (res.statusCode != 200) {
      _logger.shout('Failed to getFreeAtsignByCategory - ${res.body}');
      throw Exception(
          'Failed to get free Atsign by category: ${res.reasonPhrase}');
    }
    var payload = jsonDecode(res.body);
    if (payload["data"] == null) {
      throw Exception(
          'Failed to get free Atsign by category: payload data is null');
    }
    if (payload["Status"] == "success") {
      return payload["data"]["atsign"];
    }
    throw Exception(
        'Failed to get free Atsign by category: ${payload["message"] ?? "Unknown error"}');
  }

  // Person Registration Methods (Email-based with OTP)
  @override
  Future<void> registerPerson({
    required String atSign,
    required String email,
    String? oldEmail,
  }) async {
    Map<String, String?> data = {
      'atsign': atSign,
      'email': email,
    };
    if (oldEmail != null) {
      data['oldEmail'] = oldEmail;
    }

    var res = await registrarApiRequest(
      RegistrarApiEndpoint.registerPerson,
      data,
    );
    if (res.statusCode != 200) {
      throw Exception(
          'Failed to register person: ${res.reasonPhrase} - ${res.body}');
    }
    var payload = jsonDecode(res.body);
    if (payload["message"] != "Sent Successfully") {
      throw Exception(
          'Failed to register person: ${payload["message"] ?? "Unknown error"}');
    }
  }

  /// validates A Person through atSign, an attached email and otp from the authentication request.
  ///
  /// For a new user, returns cramkey
  /// returns: {
  ///		'success':
  ///   'cramkey':
  /// }
  /// For an existing user, returns existing atsigns, and the new one
  /// returns: {
  ///		'atsigns':
  ///   'newAtsign':
  /// }
  @override
  Future<Map<String, dynamic>> validatePerson({
    required String atSign,
    required String email,
    required String otp,
    bool confirmation = false,
  }) async {
    var res = await registrarApiRequest(
      RegistrarApiEndpoint.validatePerson,
      {
        'atsign': atSign,
        'email': email,
        'otp': otp,
        'confirmation': confirmation.toString(),
      },
    );
    if (res.statusCode != 200) {
      if (!confirmation) {
        _logger.shout(
            'Failed to validate person, try setting confirmation in validatePerson to true');
      }
      throw Exception(
          'Failed to validate person: ${res.reasonPhrase} - ${res.body}');
    }
    var payload = jsonDecode(res.body);

    // Check if validation was successful and return appropriate data
    if (payload["success"] != null && payload["success"] == true) {
      // New user - return cramkey
      return {
        'success': true,
        'cramkey': payload["cramkey"]?.split(':').last ?? '',
      };
    } else if (payload["data"] != null) {
      // Existing user - return list of atSigns
      //describes a successful free atsign path
      if (payload["data"]["newAtsign"] != null) {
        return {
          'atsigns': payload["data"]["atsigns"],
          'newAtsign': payload["data"]["newAtsign"],
        };
      } else {
        // if user has reached maximum free atsigns
        _logger.shout(payload["message"]);
        return {
          'atsigns': payload["data"]["atsigns"],
        };
      }
    }

    throw Exception(
        'Validation failed: ${payload["message"] ?? "Unknown error"}');
  }
}
