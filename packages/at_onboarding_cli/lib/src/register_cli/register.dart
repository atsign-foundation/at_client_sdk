import 'dart:collection';
import 'dart:io';

import 'package:args/args.dart';
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/src/cli/auth_cli.dart' as auth_cli;
import 'package:at_onboarding_cli/src/util/api_call_status.dart';
import 'package:at_onboarding_cli/src/util/at_onboarding_exceptions.dart';
import 'package:at_onboarding_cli/src/util/register_api_result.dart';
import 'package:at_onboarding_cli/src/util/register_api_task.dart';
import 'package:at_utils/at_logger.dart';

import '../util/onboarding_util.dart';
import '../util/registrar_api_constants.dart';

///Class containing logic to register a free atsign to email provided
///through [args] by utilizing methods defined in [RegisterUtil]
///Requires `List<String> args` containing the following arguments: email
class Register {
  Future<void> main(List<String> args) async {
    Map<String, String> params = HashMap<String, String>();
    OnboardingUtil registerUtil = OnboardingUtil();

    final argParser = ArgParser()
      ..addOption('email',
          abbr: 'e',
          help: 'The email address you would like to assign your atSign to')
      ..addFlag('help',
          abbr: 'h', help: 'Usage instructions', negatable: false);

    ArgResults argResults = argParser.parse(args);

    if (argResults.wasParsed('help')) {
      stderr.writeln(
          '[Usage] dart run register.dart -e email@email.com\n[Options]\n${argParser.usage}');
      exit(0);
    }

    if (!argResults.wasParsed('email')) {
      stderr.writeln(
          '[Unable to run Register CLI] Please enter your email address'
          '\n[Usage] dart run register.dart -e email@email.com\n[Options]\n${argParser.usage}');
      exit(6);
    }

    if (registerUtil.validateEmail(argResults['email'])) {
      params['email'] = argResults['email'];
    } else {
      stderr.writeln(
          '[Unable to run Register CLI] You have entered an invalid email address. Check your email address and try again.');
      exit(7);
    }

    //set the following parameter to RegisterApiConstants.apiHostStaging
    //to use the staging environment
    params['authority'] = RegistrarApiConstants.apiHostProd;

    //create stream of tasks each of type [RegisterApiTask] and then
    // call start on the stream of tasks
    await RegistrationFlow(params, registerUtil)
        .add(GetFreeAtsign())
        .add(RegisterAtsign())
        .add(ValidateOtp())
        .start();

    await auth_cli.wrappedMain(
      [
        '-a',
        params['atsign']!,
        '-c',
        params['cramkey']!,
      ],
    );
  }
}

///class that handles multiple tasks of type [RegisterApiTask]
///Initialized with a params map that needs to be populated with - email and api host address
///[add] method can be used to add tasks[RegisterApiTask] to the [processFlow]
///[start] needs to be called after all required tasks are added to the [processFlow]
class RegistrationFlow {
  final logger = AtSignLogger(' RegistrationFlow ');
  List<RegisterApiTask> processFlow = [];
  RegisterApiResult result = RegisterApiResult();
  late OnboardingUtil registerUtil;
  Map<String, String> params;

  RegistrationFlow(this.params, this.registerUtil);

  RegistrationFlow add(RegisterApiTask task) {
    processFlow.add(task);
    return this;
  }

  Future<void> start() async {
    for (RegisterApiTask task in processFlow) {
      task.init(params, registerUtil);
      logger.finer('Current Task: $task  [params=$params]\n');
      result = await task.run();
      if (result.apiCallStatus == ApiCallStatus.retry) {
        while (
            task.shouldRetry() && result.apiCallStatus == ApiCallStatus.retry) {
          result = await task.run();
          task.retryCount++;
        }
      }
      if (result.apiCallStatus == ApiCallStatus.success) {
        params.addAll(result.data);
      } else {
        throw AtOnboardingException(result.exceptionMessage);
      }
    }
  }
}

///This is a [RegisterApiTask] that fetches a free atsign
///throws [AtException] with concerned message which was encountered in the
///HTTP GET/POST request
class GetFreeAtsign extends RegisterApiTask {
  @override
  Future<RegisterApiResult> run() async {
    stdout
        .writeln('[Information] Getting your randomly generated free atSign…');
    try {
      List<String> atsignList =
          await registerUtil.getFreeAtSigns(authority: params['authority']!);
      result.data['atsign'] = atsignList[0];
      stdout.writeln('[Information] Your new atSign is **@${atsignList[0]}**');
      result.apiCallStatus = ApiCallStatus.success;
    } on Exception catch (e) {
      result.exceptionMessage = e.toString();
      result.apiCallStatus =
          shouldRetry() ? ApiCallStatus.retry : ApiCallStatus.failure;
    }

    return result;
  }
}

///This is a [RegisterApiTask] that registers a free atsign fetched in
///[GetFreeAtsign] to the email provided as args
///throws [AtException] with concerned message which was encountered in the
///HTTP GET/POST request
class RegisterAtsign extends RegisterApiTask {
  @override
  Future<RegisterApiResult> run() async {
    stdout.writeln(
        '[Information] Sending verification code to: ${params['email']}');
    try {
      result.data['otpSent'] = (await registerUtil.registerAtSign(
              params['atsign']!, params['email']!,
              authority: params['authority']!))
          .toString();
      stdout.writeln(
          '[Information] Verification code sent to: ${params['email']}');
      result.apiCallStatus = ApiCallStatus.success;
    } on Exception catch (e) {
      result.exceptionMessage = e.toString();
      result.apiCallStatus =
          shouldRetry() ? ApiCallStatus.retry : ApiCallStatus.failure;
    }
    return result;
  }
}

///This is a [RegisterApiTask] that validates the otp which was sent as a part
///of [RegisterAtsign] to email provided in args
///throws [AtException] with concerned message which was encountered in the
///HTTP GET/POST request
class ValidateOtp extends RegisterApiTask {
  @override
  void init(Map<String, String> params, OnboardingUtil registerUtil) {
    params['confirmation'] = 'false';
    this.params = params;
    this.registerUtil = registerUtil;
    result.data = HashMap<String, String>();
  }

  @override
  Future<RegisterApiResult> run() async {
    if (params['otp'] == null) {
      params['otp'] = registerUtil.getVerificationCodeFromUser();
    }
    stdout.writeln('[Information] Validating your verification code...');
    try {
      String apiResponse = await registerUtil.validateOtp(
          params['atsign']!, params['email']!, params['otp']!,
          confirmation: params['confirmation']!,
          authority: params['authority']!);
      if (apiResponse == 'retry') {
        stderr.writeln(
            '[Unable to proceed] The verification code you entered is either invalid or expired.\n'
            ' Check your verification code and try again.');
        params['otp'] = registerUtil.getVerificationCodeFromUser();
        result.apiCallStatus = ApiCallStatus.retry;
        result.exceptionMessage =
            'Incorrect otp entered 3 times. Max retries reached.';
      } else if (apiResponse == 'follow-up') {
        params.update('confirmation', (value) => 'true');
        result.data['otp'] = params['otp'];
        result.apiCallStatus = ApiCallStatus.retry;
      } else if (apiResponse.startsWith("@")) {
        result.data['cramkey'] = apiResponse.split(":")[1];
        stdout.writeln(
            '[Information] Your cram secret: ${result.data['cramkey']}');
        stdout.writeln('[Success] Your atSign **@${params['atsign']}** has been'
            ' successfully registered to ${params['email']}');
        result.apiCallStatus = ApiCallStatus.success;
      }
    } on Exception catch (e) {
      result.exceptionMessage = e.toString();
      result.apiCallStatus =
          shouldRetry() ? ApiCallStatus.retry : ApiCallStatus.failure;
    }
    return result;
  }
}

Future<void> main(List<String> args) async {
  Register register = Register();
  AtSignLogger.root_level = 'severe';
  try {
    await register.main(args);
  } on FormatException catch (e) {
    if (e.toString().contains('Missing argument')) {
      stderr.writeln(
          '[Unable to run Register CLI] Please re-run with your email address');
      stderr
          .writeln('Usage: \'dart run register_cli.dart -e email@email.com\'');
      exit(1);
    } else if (e.toString().contains('Could not find an option or flag')) {
      stderr
          .writeln('[Unable to run Register CLI] The option entered is invalid.'
              ' Please use the \'-e\' flag to input your email');
      stderr
          .writeln('Usage: \'dart run register_cli.dart -e email@email.com\'');
      exit(2);
    } else {
      stderr.writeln(
          '[Error] Failed getting an atsign. It looks like something went wrong on our side.\n'
          'Please try again or contact support@atsign.com, quoting the text displayed below.');
      stderr.writeln('Cause: $e');
      exit(3);
    }
  } on AtOnboardingException catch (e) {
    stderr.writeln(
        '[Error] Failed getting an atsign. It looks like something went wrong on our side.\n'
        'Please try again or contact support@atsign.com, quoting the text displayed below.');
    stderr.writeln('Cause: $e  ExceptionType:${e.runtimeType}');
    exit(4);
  } on Exception catch (e) {
    if (e
        .toString()
        .contains('Incorrect otp entered 3 times. Max retries reached.')) {
      stderr.writeln(
          '[Unable to proceed] Registration has been terminated as you have'
          ' reached the maximum number of verification attempts.\n'
          'Please start again or contact support@atsign.com');
      exit(5);
    } else {
      stderr.writeln(
          '[Error] Failed getting an atsign. It looks like something went wrong on our side.\n'
          'Please try again or contact support@atsign.com, quoting the text displayed below.');
      stderr.writeln('Cause: ${e.toString()}');
      exit(6);
    }
  }
}
