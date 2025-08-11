class AppConstants {
  static const String atLoginWidgetNamespace = 'at_login';
  static String regex = '.$atLoginWidgetNamespace@';
  static const String publicImage = 'image.persona';
  static const String publicFirstname = 'firstname.persona';
  static const String publicLastname = 'lastname.persona';
  static String appUrl = 'atprotocol://at_login';
  static const int responseTimeLimit = 30;
  static String _rootDomain = 'root.atsign.org';
  static String? website;
  static get serverDomain => _rootDomain;
  static set rootDomain(String? domain) {
    _rootDomain = domain ?? 'root.atsign.org';
    website = _rootDomain == 'root.atsign.org'
        ? 'https://atsign.com'
        : 'https://atsign.wtf';
  }
}
