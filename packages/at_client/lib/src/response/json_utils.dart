import 'dart:convert';

import 'package:at_utils/at_logger.dart';

class JsonUtils {
  static var logger = AtSignLogger('JsonDecode');

  /// Returns null when [jsonString] is null or empty.
  /// For a valid json string decodes and returns the decoded json, else null
  static dynamic decodeJson(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) {
      logger.severe('Failed to decode jsonString. Received empty string');
      return;
    }
    dynamic map;
    try {
      map = jsonDecode(jsonString);
    } on FormatException catch (e) {
      logger.severe('Failed to decode jsonString : $jsonString Error : $e');
    }
    return map;
  }
}
