import 'dart:convert';

import 'dart:typed_data';

enum MessageType { incoming, outgoing }

enum MessageContentType { text, image }

extension MessageContentTypeExt on MessageContentType {
  static MessageContentType? fromIndex(int index) {
    if (index >= 0 && index < MessageContentType.values.length) {
      return MessageContentType.values[index];
    } else {
      return null;
    }
  }
}

/// data of each message
class Message {
  String? id;
  int? time;
  String? message;
  MessageType? type;
  MessageContentType? contentType;
  String? sender;
  Uint8List? imageData;

  Message(
      {this.id,
      this.time,
      this.message,
      this.type,
      this.contentType = MessageContentType.text,
      this.sender,
      this.imageData});

  Message copyWith(
      {String? id,
      int? time,
      String? message,
      MessageType? type,
      MessageContentType? contentType,
      String? sender,
      Uint8List? imageData}) {
    return Message(
        id: id ?? this.id,
        time: time ?? this.time,
        message: message ?? this.message,
        type: type ?? this.type,
        contentType: contentType ?? this.contentType,
        sender: sender ?? this.sender,
        imageData: imageData ?? this.imageData);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'time': time,
      'message': message,
      'type': type == MessageType.values[0] ? 0 : 1,
      'content_type': contentType?.index,
      'sender': sender,
      'imageData': imageData
    };
  }

  factory Message.fromMap(Map<String, dynamic>? map) {
    if (map == null) return Message();

    return Message(
        id: map['id'],
        time: map['time'],
        message: map['message'],
        type: MessageType.values[map['type']],
        contentType: MessageContentTypeExt.fromIndex(map['content_type'] ?? 0),
        sender: map['sender'],
        imageData: map['imageData'] ?? Uint8List(0));
  }

  String toJson() => json.encode(toMap());

  factory Message.fromJson(String source) =>
      Message.fromMap(json.decode(source));

  @override
  String toString() =>
      'Message(id: $id, time: $time, message: $message, type: ${type.toString()}, '
      'contentType ${contentType.toString()}, sender: $sender, imageType: $imageData)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Message &&
        other.id == id &&
        other.time == time &&
        other.message == message &&
        other.type == type &&
        other.contentType == contentType &&
        other.sender == sender &&
        other.imageData == imageData;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      time.hashCode ^
      message.hashCode ^
      type.hashCode ^
      sender.hashCode ^
      imageData.hashCode;
}
