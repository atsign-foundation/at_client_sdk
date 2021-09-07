import 'dart:convert';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/stream/at_stream_notification.dart';

class StreamNotificationParser extends DefaultResponseParser {
  final streamNotificationKey = 'stream_id';

  final namespace;

  StreamNotificationParser(this.namespace);

//  AtStreamNotification? parseStreamNotification(String responseString) {
//    final notificationResponse = super.parse(responseString);
//    var streamNotificationJson = jsonDecode(notificationResponse.response);
//    var notificationKey = streamNotificationJson['key'];
//    var fromAtSign = streamNotificationJson['from'];
//    var atKey = notificationKey.split(':')[1];
//    atKey = atKey.replaceFirst(fromAtSign, '');
//    atKey = atKey.trim();
//    if (atKey == '$streamNotificationKey.$namespace') {
//      var valueObject = streamNotificationJson['value'];
//      var streamId = valueObject.split(':')[0];
//      var fileName = valueObject.split(':')[1];
//      var fileLength = int.parse(valueObject.split(':')[2]);
//      fileName = utf8.decode(base64.decode(fileName));
//      return AtStreamNotification()
//        ..streamId = streamId
//        ..fileName = fileName
//        ..fileLength = fileLength
//        ..senderAtSign = fromAtSign;
//    }
//    return null;
//  }

  AtStreamNotification? parseStreamNotification(AtNotification atNotification) {
    var notificationKey = atNotification.key;
    var fromAtSign = atNotification.from;
    var atKey = notificationKey.split(':')[1];
    atKey = atKey.replaceFirst(fromAtSign, '');
    atKey = atKey.trim();
    if (atKey == '$streamNotificationKey.$namespace') {
      var valueObject = atNotification.value;
      if(valueObject == null) {
        return null;
      }
      var streamId = valueObject.split(':')[0];
      var fileName = valueObject.split(':')[1];
      var fileLength = int.parse(valueObject.split(':')[2]);
      fileName = utf8.decode(base64.decode(fileName));
      return AtStreamNotification()
        ..streamId = streamId
        ..fileName = fileName
        ..fileLength = fileLength
        ..senderAtSign = fromAtSign;
    }
    return null;
  }
}