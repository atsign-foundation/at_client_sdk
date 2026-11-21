import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart' show errorResponseException;
import 'package:at_client/src/response/response.dart';
import 'package:at_client/src/response/response_parser.dart';

/// The default implementation of [ResponseParser]
class DefaultResponseParser implements ResponseParser {
  /// Returns Response object which contains response or error based on the result.
  /// @param responseString - response coming from secondary server
  /// @returns Response
  @override
  AtResponse parse(String responseString) {
    var response = AtResponse();
    // if responseString starts with data: will call parseSuccessResponse
    if (responseString.startsWith('data:')) {
      parseSuccessResponse(responseString, response);
      // if responseString starts with data: will call parseFailureResponse
    } else if (responseString.startsWith('error:')) {
      parseFailureResponse(responseString, response);
    } else {
      response.response = responseString;
    }
    return response;
  }

  /// Remove data: in responseString and set remaining string to response in Response object
  /// @param responseString - response coming from secondary server
  /// @param response - Response object from parse method
  /// @returns void
  void parseSuccessResponse(String responseString, AtResponse response) {
    response.response = responseString.replaceFirst(RegExp('^data:'), '');
  }

  /// Throws the exception an atServer's `error:` [responseString] stands
  /// for, read in any form an atServer writes as a lookup reads it, after
  /// setting [response]'s error fields from it.
  void parseFailureResponse(String responseString, AtResponse response) {
    final error = errorResponseException(responseString);
    response
      ..isError = true
      ..errorCode = error.errorCode
      ..errorDescription = error.errorMessage;
    throw AtExceptionUtils.get(error.errorCode, error.errorMessage);
  }
}
