import 'package:at_client/src/response/response.dart';

abstract class ResponseParser {
  Response parse(String responseString);
}