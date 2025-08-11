import 'package:at_client_mobile/at_client_mobile.dart';

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

  //.atKeys file key name
  static String atSelfEncryptionKey = 'selfEncryptionKey';

  //Button titles

  static String get serverDomain => _rootDomain;
  static RootEnvironment rootEnvironment = RootEnvironment.Production;

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

extension CustomMessages on OnboardingStatus {
  String get message {
    switch (this) {
      case (OnboardingStatus.ACTIVATE):
        return 'Your atsign got reactivated. Please activate with the new QRCode available on ${AtOnboardingConstants.serverDomain} website.';
      case (OnboardingStatus.ENCRYPTION_PRIVATE_KEY_NOT_FOUND):
      case (OnboardingStatus.ENCRYPTION_PUBLIC_KEY_NOT_FOUND):
      case (OnboardingStatus.PKAM_PRIVATE_KEY_NOT_FOUND):
      case (OnboardingStatus.PKAM_PUBLIC_KEY_NOT_FOUND):
        return 'Fatal error occurred. Please contact support@atsign.com';
      case (OnboardingStatus.RESTORE):
        return 'Please restore it with the available backup zip file as the local keys were missing.';
      default:
        return '';
    }
  }
}

enum RootEnvironment {
  /// Staging will provide you all the flexibility of
  /// latest server updates which are used for testing,
  /// but will not be available for production.
  // ignore: constant_identifier_names
  Staging,

  /// Production is used for production environment.
  // ignore: constant_identifier_names
  Production,

  /// Testing is used for testing(docker) environment.
  // ignore: constant_identifier_names
  Testing,
}

extension Value on RootEnvironment {
  String get domain {
    switch (this) {
      case RootEnvironment.Staging:
        return 'root.atsign.wtf';
      case RootEnvironment.Production:
        return 'root.atsign.org';
      case RootEnvironment.Testing:
        return 'vip.ve.atsign.zone';
      default:
        return 'root.atsign.wtf';
    }
  }

  String? get apikey {
    switch (this) {
      case RootEnvironment.Staging:
        return AtOnboardingConstants.deviceapikey;
      case RootEnvironment.Production:
        return AtOnboardingConstants.apiKey;
      case RootEnvironment.Testing:
        return AtOnboardingConstants.deviceapikey;
      default:
        return AtOnboardingConstants.deviceapikey;
    }
  }

  String get website {
    switch (this) {
      case RootEnvironment.Staging:
        return 'https://atsign.wtf';
      case RootEnvironment.Production:
        return 'https://atsign.com';
      case RootEnvironment.Testing:
        return 'https://atsign.wtf';
      default:
        return 'https://atsign.wtf';
    }
  }

  String get previewLink {
    switch (this) {
      case RootEnvironment.Staging:
        return 'https://directory.atsign.wtf/';
      case RootEnvironment.Production:
        return 'https://wavi.ng/';
      case RootEnvironment.Testing:
        return 'https://directory.atsign.wtf/';
      default:
        return 'https://directory.atsign.wtf/';
    }
  }
}
