import 'dart:convert';
import 'dart:io';

import 'package:at_client_mobile/src/onboarding/models/environment.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class RegistrarException implements Exception {
  RegistrarException({required this.error, required this.message});

  /// Error message. Internal use only.
  final String error;

  /// Helpful message to display to end-user.
  final String message;

  @override
  String toString() => 'RegistrarException - Error: $error, Message: $message';
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

  /// Creates an `HttpClient` with a certificate bypass in non-production environments.
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
      throw RegistrarException(
        error: 'API key not found for environment: $_rootEnvironment',
        message: "API key not found",
      );
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
      throw RegistrarException(
        error: 'Request failed: ${response.statusCode} - ${response.body}',
        message: 'Request failed with status code ${response.statusCode}',
      );
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
      throw RegistrarException(
        error: '${response.statusCode} - ${response.body}',
        message: 'Request failed with status code ${response.statusCode}',
      );
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
          throw RegistrarException(
            error: 'Request failed after $_maxRetries attempts: $message',
            message: message,
          );
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
    throw RegistrarException(
      error: 'Invalid response format: $body',
      message: 'Invalid response format',
    );
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
        throw RegistrarException(
          error: body['message'],
          message: body['message'],
        );
      }
    }
    throw RegistrarException(
      error: 'Invalid response format: $body',
      message: 'Invalid response format',
    );
  }

  /// This request is used to validate the person registering for an atSign by verifying the one-time password that was
  /// sent to the email address provided. The one-time password is valid for 15 minutes.
  Future<ValidatePersonResponse> validatePerson({
    required String atSign,
    required String email,
    required String otp,
  }) async {
    final response = await _postRequest('validate-person/', {
      'atsign': atSign,
      'email': email,
      'otp': otp,
    });

    final body = jsonDecode(response.body);

    if (body is Map<String, dynamic>) {
      return ValidatePersonResponse.fromJson(body);
    }

    throw RegistrarException(
      error: 'Invalid response format: $body',
      message: 'Invalid response format',
    );
  }

  /// This request is used to check whether the person attempting to activate an atSign is its rightful owner.
  /// The request takes an atSign and sends a one-time password to the email address and/or phone number associated
  /// with that atSign.
  Future<void> authenticateAtSign({required String atSign}) async {
    final response = await _postRequest('authenticate/atsign', {
      'atsign': atSign,
    });

    final body = jsonDecode(response.body);

    if (body is Map<String, dynamic>) {
      final message = body['message'];
      if (message == 'Sent Successfully') {
        return;
      } else {
        throw RegistrarException(
          error: 'authenticate/atsign failed: $message',
          message: message,
        );
      }
    }

    throw RegistrarException(
      error: 'Invalid response format: $body',
      message: 'Invalid response format',
    );
  }

  /// This request is used to check whether the person attempting to activate an atSign is its rightful owner.
  /// The request takes an atSign and a one-time password then provides the cramkey once verified.
  Future<String> authenticateAtSignAndActivate({required String atSign, required String otp}) async {
    final response = await _postRequest('authenticate/atsign/activate', {
      'atsign': atSign,
      'otp': otp,
    });

    final body = jsonDecode(response.body);

    if (body is Map<String, dynamic>) {
      final cramKey = (body['cramKey'] as String?)?.split(':')[1];
      if (cramKey != null) {
        return cramKey;
      } else {
        final message = body['message'] as String;
        throw RegistrarException(
          error: 'authenticate/atsign/activate failed: $message',
          message: message,
        );
      }
    }

    throw RegistrarException(
      error: 'Invalid response format: $body',
      message: 'Invalid response format',
    );
  }
}

class ValidatePersonResponse {
  const ValidatePersonResponse({
    this.existingAtSigns = const [],
    this.errorMessage,
    this.cramKey,
    this.newAtSign,
  });

  final List<String> existingAtSigns;
  final String? errorMessage;
  final String? cramKey;
  final String? newAtSign;

  factory ValidatePersonResponse.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('success') && json['success'] == true) {
      // Remove the atsign identifier from the beginning of the cramKey.
      final cramKey = (json['cramKey'] as String?)?.split(':')[1];
      return ValidatePersonResponse(
        cramKey: cramKey,
      );
    }

    if (json.containsKey('data')) {
      final data = json['data'] as Map<String, dynamic>;
      final atSigns = (data['atsigns'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [];
      final newAtSign = data['newAtsign'] as String?;

      return ValidatePersonResponse(
        existingAtSigns: atSigns,
        newAtSign: newAtSign,
      );
    }

    if (json.containsKey('status') && json['status'] == "error") {
      return ValidatePersonResponse(
        errorMessage: json['message'] as String?,
      );
    }

    throw RegistrarException(
      error: 'Invalid response format',
      message: 'Unexpected response structure: $json',
    );
  }

  bool get success => newAtSign != null || cramKey != null;
}
