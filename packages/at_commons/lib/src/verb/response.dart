import 'package:at_commons/at_commons.dart';

class Response {
  String? data;
  String? type;
  bool isError = false;
  String? errorMessage;
  String? errorCode;
  AtException? atException;
  bool isStream = false;

  Response();

  Response.factory(this.data, this.errorCode, this.errorMessage);

  factory Response.fromJson(dynamic json) {
    return Response.factory(json['data'] as String?,
        json['error_code'] as String?, json['error_message'] as String?);
  }

  Map toJson() {
    var jsonMap = {};
    if (data != null) {
      jsonMap['data'] = data;
    }
    if (errorCode != null) {
      jsonMap['error_code'] = errorCode;
    }
    if (errorMessage != null) {
      jsonMap['error_message'] = errorMessage;
    }
    return jsonMap;
  }

  @override
  String toString() {
    return 'Response{_data: $data, _type: $type, _isError: $isError, _errorMessage: $errorMessage}';
  }
}
