class BatchRequest {
  String? command;
  int? id;

  BatchRequest(this.id, this.command);

  factory BatchRequest.fromJson(dynamic json) {
    return BatchRequest(json['id'] as int?, json['command'] as String?);
  }

  Map toJson() => {
        'id': id,
        'command': '$command',
      };

  @override
  String toString() {
    return '$id, $command';
  }
}
