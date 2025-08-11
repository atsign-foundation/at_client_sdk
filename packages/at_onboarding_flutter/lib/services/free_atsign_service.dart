import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_onboarding_flutter/utils/at_onboarding_app_constants.dart';
import 'package:http/io_client.dart';
import 'package:http/http.dart';

/// Service to generate free atsigns randomly
class FreeAtsignService {
  static FreeAtsignService freeAtsignService = FreeAtsignService._internal();
  FreeAtsignService._internal() {
    _init();
  }

  factory FreeAtsignService() => freeAtsignService;

  late IOClient _http;
  bool initialized = false;

  void _init() {
    HttpClient ioc = HttpClient();
    ioc.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    _http = IOClient(ioc);
    initialized = true;
  }

  /// To login with an @sign
  Future<dynamic> loginWithAtsign(String atsign) async {
    // if init was not called earlier, call here to initialize the http
    if (!initialized) {
      _init();
    }
    Map<String, String?> data = <String, String?>{'atsign': atsign};

    String path =
        AtOnboardingConstants.apiPath + AtOnboardingConstants.authWithAtsign;

    dynamic response = await postRequest(path, data);

    return response;
  }

  /// validating atsign with verification code
  Future<dynamic> verificationWithAtsign(
      String atsign, String verificationCode) async {
    // if init was not called earlier, call here to initialize the http
    if (!initialized) {
      _init();
    }
    String path = AtOnboardingConstants.apiPath +
        AtOnboardingConstants.validationWithAtsign;
    Map<String, String?> data = <String, String?>{
      'atsign': atsign,
      'otp': verificationCode
    };

    dynamic response = await postRequest(path, data);

    return response;
  }

  /// To get free @sign from the server
  Future<dynamic> getFreeAtsigns() async {
    // if init was not called earlier, call here to initialize the http
    if (!initialized) {
      _init();
    }
    Uri url = Uri.https(AtOnboardingConstants.apiEndPoint,
        '${AtOnboardingConstants.apiPath}${AtOnboardingConstants.getFreeAtsign}');

    Response response = await _http.get(
      url,
      headers: <String, String>{
        'Authorization': AtOnboardingConstants.apiKey!,
        'Content-Type': 'application/json',
      },
    );

    return response;
  }

  /// To register the person with the provided atsign and email
  /// It will send an OTP to the registered email
  Future<dynamic> registerPerson(String atsign, String email,
      {String? oldEmail}) async {
    if (!initialized) {
      _init();
    }
    Map<String, String?> data;
    String path =
        AtOnboardingConstants.apiPath + AtOnboardingConstants.registerPerson;
    if (oldEmail != null) {
      data = <String, String?>{
        'email': email,
        'atsign': atsign,
        'oldEmail': oldEmail
      };
    } else {
      data = <String, String?>{'email': email, 'atsign': atsign};
    }

    dynamic response = await postRequest(path, data);
    return response;
  }

  /// It will validate the person with atsign, email and the OTP.
  /// If the validation is successful, it will return a cram secret for the user to login
  Future<dynamic> validatePerson(String atsign, String email, String? otp,
      {bool confirmation = false}) async {
    if (!initialized) {
      _init();
    }
    Map<String, String?> data;
    String path =
        AtOnboardingConstants.apiPath + AtOnboardingConstants.validatePerson;
    data = <String, String?>{
      'email': email,
      'atsign': atsign,
      'otp': otp,
      'confirmation': confirmation.toString()
    };
    dynamic response = await postRequest(path, data);

    return response;
  }

  /// common POST request call
  Future<dynamic> postRequest(String path, Map<String, String?> data) async {
    Uri url = Uri.https(AtOnboardingConstants.apiEndPoint, path);

    String body = json.encode(data);
    return _http.post(
      url,
      body: body,
      headers: <String, String>{
        'Authorization': AtOnboardingConstants.apiKey!,
        'Content-Type': 'application/json',
      },
    );
  }
}
