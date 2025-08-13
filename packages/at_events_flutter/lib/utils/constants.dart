// ignore_for_file: constant_identifier_names, non_constant_identifier_names

class MixedConstants {
  static const String CREATE_EVENT = 'createevent';

  static const String EVENT_MEMBER_LOCATION_KEY = 'updateeventlocation';

  static List<String> startTimeOptions = [
    '2 hours before the event',
    '60 minutes before the event',
    '30 minutes before the event'
  ];

  static List<String> endTimeOptions = [
    '10 mins after I reach the venue',
    'After everyone’s at the venue',
    'At the end of the day'
  ];

  static String? _map_key;

  /// sets the map key used for map services
  static String setMapKey(String _key) => _map_key = _key;

  static String? get MAP_KEY => _map_key;

  static String? _api_key;

  /// sets the API key used for API services
  static String setApiKey(String _key) => _api_key = _key;

  static String? get API_KEY => _api_key;
}
