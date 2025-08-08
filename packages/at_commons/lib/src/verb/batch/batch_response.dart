import 'package:at_commons/at_commons.dart';

class BatchResponse {
  Response? response;
  int? id;

  BatchResponse(this.id, this.response);

  factory BatchResponse.fromJson(dynamic json) {
    return BatchResponse(json['id'] as int?, json['response'] as Response?);
  }

  Map toJson() => {'id': id, 'response': response!.toJson()};

  @override
  String toString() {
    return '$id, $response';
  }
}
