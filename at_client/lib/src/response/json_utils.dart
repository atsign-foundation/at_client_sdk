import 'dart:convert';

import 'package:at_utils/at_logger.dart';

class JsonUtils {
  static var logger = AtSignLogger('JsonDecode');

  static dynamic jsonDecodeWrapper(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) {
      logger.severe('Failed to decode jsonString. Received empty string');
      return;
    }
    var json;
    try {
      json = jsonDecode(jsonString);
    } on FormatException catch (e) {
      logger.severe('Failed to decode jsonString : $jsonString Error : $e');
    }
    return json;
  }
}
