import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/registrar/registrar.dart';
import 'package:at_auth/src/at_auth.dart';
import 'package:at_utils/at_logger.dart';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

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
    if (httpClient != null) {
      _http = httpClient;
    } else {
      var innerClient = HttpClient();
      innerClient.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
      _http = IOClient(innerClient);
    }
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
      return _http.get(url, headers: headers);
    } else {
      return _http.post(
        url,
        body: jsonEncode(data),
        headers: headers,
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
