import 'package:at_server_status/at_server_status.dart';

class Strings {
  static const String BackButton = 'Back';
  static const String Search = 'Filter @signs';
  static const String Error = 'Error';
  static const String Close = 'Close';
  static const String atsign = '@';
  static const String package = 'at_login_flutter';
  static const String atLogin = 'atLogin';
  static const String invalidAtsign = 'Invalid atsign';
  static const String pairAtsign = 'Pair Atsign';
  static const String notPairAtsign = 'Do not pair atsign';
  static const String completeAtLogin = 'Complete Login';
  static const String loginAllowed = 'Allow Login';
  static const String loginDenied = 'Deny Login';
  static const String atSignIsPaired = 'Atsign is paired';
  static const String atSignNotPaired = 'Atsign is not paired';
  static const String loginRequest = 'Login required';
  static const String atServerNotAvailable =
      'The service for this atsign is not available';

  // dasboard content
  static const String dashboardTitle = 'Dashboard';

  //public content
  static String? directoryUrl;
  static String? rootdomain;
  static const String cancel = 'Cancel';
  static String allowLoginDescription(String? requestorUrl) {
    return '$requestorUrl would like to use your atSign to authenticate.';
  }

  //qrscan texts
  static const String enterAtsignButton = 'Type the @sign';
  static const String enterAtsignTitle = 'Enter the @sign';
  static const String atsignHintText = 'alice';
  static const String qrTitle = 'Follow @sign';
  static const String qrscanDescription =
      'Toggle to scan the QR code of an @sign to follow';
  static const String submitButton = 'Submit';
  static const String invalidAtsignMessage =
      'Please provide or scan a valid @sign to follow';
  static const String badQr = 'Not able to scah this QR code';
  static String getAtSignStatusMessage(AtSignStatus? status) {
    status ??= AtSignStatus.error;
    switch (status) {
      case AtSignStatus.unavailable:
      case AtSignStatus.notFound:
        return '@sign is not registered yet. Please try with the registered one.';
      case AtSignStatus.error:
        return '@sign and the server is unreachable. Please try again';
      default:
        return 'Unknown status. Please try again later.';
    }
  }

  //error dialog texts
  static const String errorTitle = 'Error';
  static const String closeButton = 'Close';

  //loading texts
  static const String loadingDescription =
      'Please wait while loading your data';
}
