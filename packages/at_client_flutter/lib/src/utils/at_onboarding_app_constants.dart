import 'package:at_client_flutter/src/at_onboarding_status.dart';

class AtOnboardingConstants {
  static String _rootDomain = 'root.atsign.org';
  static dynamic contentType = 'application/json';
  static String getFreeAtsign = 'get-free-atsign';
  static String authWithAtsign = 'login/atsign';
  static String validationWithAtsign = 'login/atsign/validate';
  static String registerPerson = 'register-person';
  static String validatePerson = 'validate-person';
  static String? website;
  static String apiEndPoint = 'my.atsign.com';
  static String apiPath = '/api/app/v2/';
  static String package = 'at_onboarding_flutter';
  static String encryptKeys = '_encrypt_keys';
  static const String deviceapikey = '477b-876u-bcez-c42z-6a3d';
  static String backupFileExtension = '.atKeys';
  static String backupZipExtension = '_atKeys.zip';
  static int responseTimeLimit = 30;
  static String contactAddress = 'support@atsign.com';
  static String activateAtSign = '/api/activateAtSign';
  static const String faqUrl = 'https://atsign.com/faqs/#atsigns';
  static const String atsignHintText = 'alice';
  static const String assetImagePath = 'assets/images';
  static const String backupZip = '$assetImagePath/backup_key.png';
}