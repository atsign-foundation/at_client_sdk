// ignore_for_file: constant_identifier_names, non_constant_identifier_names

class MixedConstants {
  static const String WEBSITE_URL = 'https://atsign.com/';

  // for local server
  // static const String ROOT_DOMAIN = 'vip.ve.atsign.zone';
  // for staging server
  // static const String ROOT_DOMAIN = 'root.atsign.wtf';
  // for production server
  // static const String ROOT_DOMAIN = 'root.atsign.org';

  static const String TERMS_CONDITIONS = 'https://atsign.com/terms-conditions/';
  static const String PRIVACY_POLICY = 'https://atsign.com/privacy-policy/';

  static const String SHARE_LOCATION = 'sharelocation';
  static const String SHARE_LOCATION_ACK = 'sharelocationacknowledged';

  static const String REQUEST_LOCATION = 'requestlocation';
  static const String REQUEST_LOCATION_ACK = 'requestlocationacknowledged';
  static const String DELETE_REQUEST_LOCATION_ACK = 'deleterequestacklocation';

  // static const bool isDedicated = false;

  static String? _map_key;
  static String setMapKey(String _key) => _map_key = _key;
  static String? get MAP_KEY => _map_key;

  static String? _api_key;
  static String setApiKey(String _key) => _api_key = _key;
  static String? get API_KEY => _api_key;
}
