import 'dart:convert';
import 'dart:io';

import 'package:at_client_mobile/src/onboarding/models/environment.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class RegistrarException implements Exception {
  RegistrarException(this.message);
  final String message;

  @override
  String toString() => 'RegistrarException: $message';
}

/// {@template registrar_service}
/// Service for interacting with the registrar.
/// {@endtemplate}
class RegistrarService {
  /// {@macro registrar_service}
  RegistrarService(this._rootEnvironment) : _http = IOClient(_createHttpClient(_rootEnvironment));

  final RootEnvironment _rootEnvironment;
  final IOClient _http;

  static const String _apiPath = '/api/app/v3';
  static const int _maxRetries = 3;
  static const int _retryDelayMs = 2000;

  /// Creates an `HttpClient` with optional certificate bypass in non-production.
  static HttpClient _createHttpClient(RootEnvironment env) {
    final client = HttpClient();
    if (env != RootEnvironment.prod) {
      client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    }
    return client;
  }

  /// Retrieves the API key for the current environment.
  String _getApiKey() {
    final apiKey = {
      RootEnvironment.dev: dotenv.env['ATSIGN_DEV_API_KEY'],
      RootEnvironment.prod: dotenv.env['ATSIGN_API_KEY'],
      RootEnvironment.staging: dotenv.env['ATSIGN_STAGING_API_KEY'],
    }[_rootEnvironment];

    if (apiKey == null) {
      throw RegistrarException('API key not found for environment: $_rootEnvironment');
    }
    return apiKey;
  }

  /// Sends a POST request to the registrar API with retry logic.
  Future<http.Response> _postRequest(String path, Map<String, String?>? data) async {
    final url = Uri.https(_rootEnvironment.domain, '$_apiPath/$path');
    final body = data != null ? json.encode(data) : null;

    return _retryRequest(() async {
      final response = await _http.post(
        url,
        body: body,
        headers: {
          'Authorization': _getApiKey(),
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      throw RegistrarException('Request failed: ${response.statusCode} - ${response.body}');
    });
  }

  /// Sends a GET request to the registrar API with retry logic.
  Future<http.Response> _getRequest(String path) async {
    final url = Uri.https(_rootEnvironment.domain, '$_apiPath/$path');

    return _retryRequest(() async {
      final response = await _http.get(
        url,
        headers: {
          'Authorization': _getApiKey(),
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      throw RegistrarException('${response.statusCode} - ${response.body}');
    });
  }

  /// Retries a function `_maxRetries` times with a delay.
  Future<T> _retryRequest<T>(Future<T> Function() request) async {
    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        return await request();
      } catch (e) {
        // Would be cleaner to move this logic outside the for loop but
        // keeping this logic so that the error can be reported in exception.
        if (attempt == _maxRetries - 1) {
          final message = e is RegistrarException ? e.message : e.toString();
          throw RegistrarException('Request failed after $_maxRetries attempts: $message');
        }
        await Future.delayed(Duration(milliseconds: _retryDelayMs));
      }
    }
    throw Exception('Unexpected error in _retryRequest');
  }

  /// Gets a free atSign from the registrar.
  Future<String> getFreeAtSign() async {
    final response = await _getRequest('get-free-atsign/');

    final body = jsonDecode(response.body);
    if (body is Map<String, dynamic> && body['data'] is Map<String, dynamic>) {
      final data = body['data'] as Map<String, dynamic>;
      if (data['atsign'] is String) {
        return data['atsign'] as String;
      }
    }
    throw RegistrarException('Invalid response format: $body');
  }

  /// This request is used to register an atSign by assigning it to an email address.
  /// This request accepts an [atSign] and an [email] address.
  /// A one-time password will be sent to the email address provided.
  Future<void> registerPerson({required String atSign, required String email}) async {
    final response = await _postRequest('register-person/', {
      'atsign': atSign,
      'email': email,
    });

    final body = jsonDecode(response.body);
    if (body is Map<String, dynamic> && body['message'] is String) {
      if (body['message'] == 'Sent Successfully') {
        return;
      } else {
        throw RegistrarException(body['message']);
      }
    }
    throw RegistrarException('Invalid response format: $body');
  }
}
