class Response {
  String? response;
  bool isError = false;
  String? errorCode;
  String? errorDescription;

  Response fromJson(Map<String, dynamic> json) {
    response = json['response'];
    isError = json['isError'];
    errorCode = json['errorCode'];
    errorDescription = json['errorDescription'];
    return this;
  }

  Map<String, dynamic> toJson() => {
    'response': response,
    'isError': isError,
    'errorCode': errorCode,
    'errorDescription': errorDescription,
  };
}
