import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart' as at_client;
import 'package:at_onboarding_cli/src/util/registrar_api_constants.dart';
import 'package:at_utils/at_logger.dart';
import 'package:chalkdart/chalk.dart';
import 'package:http/http.dart';
import 'package:http/io_client.dart';

///class containing utilities to perform registration of a free atsign
class OnboardingUtil {
  static bool allowBadCertificates = false;
  final logger = AtSignLogger(' OnboardingUtil ');
  IOClient? _ioClient;

  void _createClient() {
    HttpClient ioc = HttpClient();
    ioc.badCertificateCallback = (X509Certificate cert, String host, int port) {
      if (allowBadCertificates) {
        logger.shout('*************');
        logger.shout('************* Ignoring bad certificate from $host:$port');
        logger.shout('*************');
        return true;
      }
      return false;
    };
    _ioClient = IOClient(ioc);
  }

  /// Returns a `Future<List<String>>` containing free available atSigns of count provided as input.
  Future<List<String>> getFreeAtSigns(
      {int amount = 1,
      String authority = RegistrarApiConstants.apiHostProd}) async {
    List<String> atSigns = <String>[];
    Response response;
    for (int i = 0; i < amount; i++) {
      // get request at my.atsign.com/api/app/v3/get-free-atsign/
      response =
          await getRequest(authority, RegistrarApiConstants.pathGetFreeAtSign);
      if (response.statusCode == 200) {
        String atSign = jsonDecode(response.body)['data']['atsign'];
        atSigns.add(atSign);
      } else {
        throw at_client.AtClientException.message(
            '${response.statusCode} ${response.reasonPhrase}');
      }
    }
    return atSigns;
  }

  /// Registers the [atSign] provided in the input to the provided [email]
  /// The `atSign` provided should be an unregistered and free atsign
  /// Returns true if the request to send the OTP was successful.
  /// Sends an OTP to the `email` provided.
  /// Throws [AtException] if [atSign] is invalid
  Future<bool> registerAtSign(String atSign, String email,
      {oldEmail, String authority = RegistrarApiConstants.apiHostProd}) async {
    Response response =
        await postRequest(authority, RegistrarApiConstants.pathRegisterAtSign, {
      'atsign': atSign,
      'email': email,
      'oldEmail': oldEmail,
    });
    if (response.statusCode == 200) {
      Map<String, dynamic> jsonDecoded = jsonDecode(response.body);
      bool sentSuccessfully =
          jsonDecoded['message'].toLowerCase().contains('success');
      return sentSuccessfully;
    } else {
      throw at_client.AtClientException.message(
          '${response.statusCode} ${response.reasonPhrase}');
    }
  }

  /// Registers the [atSign] provided in the input to the provided [email]
  /// The `atSign` provided should be an unregistered and free atsign
  /// Validates the OTP against the atsign and registers it to the provided email if OTP is valid.
  /// Returns the CRAM secret of the atsign which is registered.
  ///
  /// [confirmation] - Mandatory parameter for validateOTP API call. First request to be sent with confirmation as false, in this
  /// case API will return cram key if the user is new otherwise will return list of already existing atsigns.
  /// If the user already has existing atsigns user will have to select a listed atsign old/new and place a second call
  /// to the same API endpoint with confirmation set to true with previously received OTP. The second follow-up call
  /// is automated by this client using new atsign for user simplicity
  ///
  ///return value -  Case 1("verified") - the API has registered the atsign to provided email and CRAM key present in HTTP_RESPONSE Body.
  /// Case 2("follow-up"): User already has existing atsigns and new atsign registered successfully. To receive the CRAM key, follow-up by calling
  /// the API with one of the existing listed atsigns, with confirmation set to true.
  /// Case 3("retry"): Incorrect OTP send request again with correct OTP.
  /// Throws [AtException] if [atSign] or [otp] is invalid
  Future<String> validateOtp(String atSign, String email, String otp,
      {String confirmation = 'true',
      String authority = RegistrarApiConstants.apiHostProd}) async {
    Response response =
        await postRequest(authority, RegistrarApiConstants.pathValidateOtp, {
      'atsign': atSign,
      'email': email,
      'otp': otp,
      'confirmation': confirmation,
    });
    if (response.statusCode == 200) {
      Map<String, dynamic> jsonDecoded = jsonDecode(response.body);
      Map<String, dynamic> dataFromResponse = {};
      if (jsonDecoded.containsKey('data')) {
        dataFromResponse.addAll(jsonDecoded['data']);
      }
      if ((jsonDecoded.containsKey('message') &&
              (jsonDecoded['message'] as String)
                  .toLowerCase()
                  .contains('verified')) &&
          jsonDecoded.containsKey('cramkey')) {
        return jsonDecoded['cramkey'];
      } else if (jsonDecoded.containsKey('data') &&
          dataFromResponse.containsKey('newAtsign')) {
        return 'follow-up';
      } else if (jsonDecoded.containsKey('message') &&
          jsonDecoded['message'] ==
              'The code you have entered is invalid or expired. Please try again?') {
        return 'retry';
      } else if (jsonDecoded.containsKey('message') &&
          (jsonDecoded['message'] ==
              'Oops! You already have the maximum number of free atSigns. Please select one of your existing atSigns.')) {
        stdout.writeln(
            '${chalk.brightRed('[Unable to proceed]')} This email address already has 10 free atSigns associated with it.\n'
            'To register a new atSign to this email address, please log into the dashboard \'my.atsign.com/login\'.\n'
            'Remove at least 1 atSign from your account and then try again.\n'
            'Alternatively, you can retry this process with a different email address.');
        throw at_client.AtClientException.message(jsonDecoded['message']);
      } else {
        throw at_client.AtClientException.message(
            '${response.statusCode} ${jsonDecoded['message']}');
      }
    } else {
      throw at_client.AtClientException.message(
          '${response.statusCode} ${response.reasonPhrase}');
    }
  }

  /// Accepts a registered [atsign] as a parameter and sends a one-time verification code
  /// to the email that the atsign is registered with
  /// Throws an exception in the following cases:
  /// 1) HTTP 400 BAD_REQUEST
  /// 2) Invalid atsign
  Future<void> requestAuthenticationOtp(String atsign,
      {String authority = RegistrarApiConstants.apiHostProd}) async {
    stdout.writeln('${chalk.blue('[Information]')}'
        ' Requesting $authority to send a verification code');

    Response response = await postRequest(authority,
        RegistrarApiConstants.requestAuthenticationOtpPath, {'atsign': atsign});
    String apiResponseMessage =
        jsonDecode(response.body)['message'] ?? '[Empty Response]';
    if (response.statusCode == 200) {
      if (apiResponseMessage.contains('Sent Successfully')) {
        stdout.writeln('${chalk.green('[Information]')}'
            ' Successfully sent verification code'
            ' to your registered e-mail or phone');
        return;
      }
      throw at_client.InternalServerError(
          'Unable to send verification code for authentication.\nCause: $apiResponseMessage');
    }
    throw at_client.InvalidRequestException(apiResponseMessage);
  }

  /// Returns the cram key for an atsign by fetching it from the registrar API
  /// Accepts a registered [atsign], the verification code that was sent to
  /// the registered email
  /// Throws exception in the following cases:
  /// 1) HTTP 400 BAD_REQUEST
  Future<String> getCramKey(String atsign, String verificationCode,
      {String authority = RegistrarApiConstants.apiHostProd}) async {
    stdout.writeln(
        '${chalk.blue('[Information]')} Fetching CRAM Key from $authority');
    Response response = await postRequest(
        authority,
        RegistrarApiConstants.getCramKeyWithOtpPath,
        {'atsign': atsign, 'otp': verificationCode});
    Map<String, dynamic> jsonDecodedBody;
    try {
      jsonDecodedBody = jsonDecode(response.body);
    } catch (e) {
      throw at_client.InvalidDataException(
          'Unexpected response from registrar: ${response.body}');
    }
    if (response.statusCode == 200) {
      if (jsonDecodedBody['message'] == 'Verified') {
        String cram = jsonDecodedBody['cramkey'];
        cram = cram.split(':')[1];
        stdout.writeln('${chalk.green('[Information]')}'
            ' CRAM Key fetched successfully');
        return cram;
      }
      throw at_client.InvalidDataException(
          'Invalid verification code. Please enter a valid verification code');
    }
    throw at_client.InvalidDataException(jsonDecodedBody['message']);
  }

  /// generic GET request
  Future<Response> getRequest(String authority, String path) async {
    if (_ioClient == null) _createClient();
    Uri uri = Uri.https(authority, path);
    Response response = await _ioClient!.get(uri, headers: <String, String>{
      'Authorization': RegistrarApiConstants.authorization,
      'Content-Type': RegistrarApiConstants.contentType,
    });
    return response;
  }

  /// generic POST request
  Future<Response> postRequest(
      String authority, String path, Map<String, String?> data) async {
    _ioClient = null;
    if (_ioClient == null) _createClient();

    Uri uri = Uri.https(authority, path);

    String body = json.encode(data);
    logger.finer('Sending request to url: $uri\nRequest Body: $body');
    Response response = await _ioClient!.post(
      uri,
      body: body,
      headers: <String, String>{
        'Authorization': RegistrarApiConstants.authorization,
        'Content-Type': RegistrarApiConstants.contentType,
      },
    );
    logger.finer('Got Response: ${response.body}');
    return response;
  }

  bool validateEmail(String email) {
    return RegExp(
            r"^[a-zA-Z0-9.a-zA-Z0-9!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+")
        .hasMatch(email);
  }

  bool validateVerificationCode(String otp) {
    if (otp.length == 4) {
      return RegExp(r"^[a-zA-z0-9]").hasMatch(otp);
    }
    return false;
  }

  /// Method to get verification code from user input
  /// validates code locally and retries taking user input if invalid
  /// Returns only when the user has provided a 4-length String only containing numbers and alphabets
  String getVerificationCodeFromUser() {
    String? otp;
    stdout.write(
        '${chalk.blue('[Action Required]')} Enter your verification code: ');
    otp = stdin.readLineSync()!.toUpperCase();
    while (!validateVerificationCode(otp!)) {
      stderr.writeln(
          '${chalk.red('[Unable to proceed]')} The verification code you entered is invalid.\n'
          'Please check your email for a 4-character verification code.\n'
          'If you cannot see the code in your inbox, please check your spam/junk/promotions folders.\n'
          '\n'
          '${chalk.blue('[Action Required]')} Enter your verification code:');
      otp = stdin.readLineSync()!.toUpperCase();
    }
    return otp;
  }
}
