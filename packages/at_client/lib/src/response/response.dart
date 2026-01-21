class AtResponse {
  String response = '';
  bool isError = false;
  String? errorCode;
  String errorDescription = 'Error description n/a';

  AtResponse fromJson(Map<String, dynamic> json) {
    response = json['response'];
    isError = json['isError'];
    errorCode = json['errorCode'];
    errorDescription = json['errorDescription'] ?? 'Error description n/a';
    return this;
  }

  Map<String, dynamic> toJson() => {
        'response': response,
        'isError': isError,
        'errorCode': errorCode,
        'errorDescription': errorDescription,
      };

  @override
  String toString() => toJson().toString();
}
