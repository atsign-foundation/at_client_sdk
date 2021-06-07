import 'package:at_client/src/response/response.dart';
import 'package:at_client/src/response/response_parser.dart';

class DefaultResponseParser implements ResponseParser {

  @override
  Response parse(String responseString) {
    var response = Response();
    if (responseString == null) {
      return response;
    }
    if (responseString.startsWith('data:')) {
      parseSuccessResponse(responseString, response);
    } else if (responseString.startsWith('error:')) {
      parseFailureResponse(responseString, response);
    } else {
      response.response = responseString;
    }
    return response;
  }

  void parseSuccessResponse(String responseString, Response response) {
    response.response = responseString.replaceFirst('data:', '');
  }

  void parseFailureResponse(String responseString, Response response) {
    responseString = responseString.replaceFirst('error:', '');
    response.isError = true;
    if (responseString.isNotEmpty && responseString.startsWith('AT')) {
      response.errorCode = (responseString.split(':')[0]);
      response.errorDescription = (responseString.split(':').length > 1)
          ? responseString.split(':')[1]
          : '';
    } else {
      response.errorDescription = responseString;
    }
  }
}
