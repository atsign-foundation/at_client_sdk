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
  static String apiEndPoint = 'my.atsign.wtf';
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

  //.atKeys file key name
  static String atSelfEncryptionKey = 'selfEncryptionKey';

  //Button titles

  static String get serverDomain => _rootDomain;

  static set rootDomain(String? domain) {
    _rootDomain = domain ?? 'root.atsign.org';
    if (_rootDomain == 'root.atsign.org') {
      website = 'https://atsign.com';
      apiEndPoint = 'my.atsign.com';
    } else {
      website = 'https://atsign.wtf';
      apiEndPoint = 'my.atsign.wtf';
    }
  }

  static String? _apiKey;
  static String setApiKey(String key) => _apiKey = key;
  static String? get apiKey => _apiKey;
}

extension CustomMessages on AtOnboardingStatus {
  String get message {
    switch (this) {
      case (AtOnboardingStatus.activate):
        return 'Your atsign got reactivated. Please activate with the new QRCode available on ${AtOnboardingConstants.serverDomain} website.';
      case (AtOnboardingStatus.encryptionKeyNotFound):
      case (AtOnboardingStatus.pkamKeyNotFound):
        return 'Fatal error occurred. Please contact support@atsign.com';
      case (AtOnboardingStatus.restoreBackup):
        return 'Please restore it with the available backup zip file as the local keys were missing.';
      default:
        return '';
    }
  }
}