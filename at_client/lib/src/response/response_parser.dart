import 'package:at_client/src/response/response.dart';

abstract class ResponseParser {
  /// Returns Response object which contains response or error based on the result.
  /// @param responseString - response coming from secondary server
  /// @returns Response
  Response parse(String responseString);
}