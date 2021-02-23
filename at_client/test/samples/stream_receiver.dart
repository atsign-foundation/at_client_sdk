import 'package:at_client/src/client/at_client_impl.dart';
import 'test_util.dart';
import 'dart:convert';

AtClientImpl atClient;
void main() async {
  try {
    await AtClientImpl.createClient(
        '@bob🛠', 'me', TestUtil.getBobPreference());
    atClient = await AtClientImpl.getClient('@bob🛠');
    await atClient.getSyncManager().init( '@bob🛠', TestUtil.getBobPreference(),
        atClient.getRemoteSecondary(), atClient.getLocalSecondary());
    await atClient.startMonitor(
        'MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCxGGbUHy3bpdMQdvQn5F5dAMEbcDsaYDYsvqYAkjLKGPwgl5pk8gdxU6HnWLaXJDwZd4xRaUDHYToGD+k1xp2SEFjMsxD4PAA9k/hKtddEpaDHEGiC3kOf3VD12BJ3VyFsikZutZtgwF7o5cJCdU5Ppqno5ThChV5I3ZUelfoumqQF1iKnZ3z/NdtWAyFs7HNcuO+bL7ls28CNpVkrPxHbydLL/Y/qqR9xeJ5wm8WnQr5YRVFgYGNi03NlsW0UODkE3mufXAC8ALnQ3W9iQa/pW3QXwMKzuyebF29Jfsx/ELvfnzbgRdlKPNEI++phQyMrvZ67uhSewQnAUrW8+aTfAgMBAAECggEBAInMtf6qgDFgd7phBRyhWze85YXnL2YXpS/t7ReWqwSMqmrl7FJN7bKl494zLmiu3kDmv/19C9XYdqDO8qVQdb15EM+/Kh4t+fXwVIw1sFqPEmqy/s+OCUq0mFGjnsLTvoNJmQJ+N3fyWCea2CyEQLpDsgQxkDRauIG0QVs6UiC+EWaolgYtDvNrXgybjjQyvbdSV5jxuYHvt8uzjyUVDQy22mq9H2S3ztI7KqZYoikoAq+baP5RHqD0CBd7hlZPjEo8+aeQN1WeXKiNQGO6JTfWQRquiGpQkwaVXt7kYPwQ0tYrpOXOT9kCWot+aTMbgyIkUmP44IoxMcsyBzi+PVECgYEA5ErweSkb+DGBKSDOcWJDhsfS6jLTu8fe1Y7h9TtRR4436GzpEPFQPd4192e96oe/IjibWQiIqm4KIwXPw7clXMhOtFpMu5935cJfzWkSaa+m9lHRmn/ire52J13KZc7eYpYQiSXue2aKVLQhG1VDXePO+N6M9gR5Mz52IokFzukCgYEAxpbB6mEbk3//hLNknZGj/WTFQV3FNG43sIn9KZckdBV+9sczAetKNvjScuX4ceNG7XyCnVCl9qmz0+TAGmWfnGB/u4EHyRc5iNNo3q/DVRhUPHeOpSdQw+VOEMN47HELdqzOrK0q4BbSJlFdsHjL0P/oFDWVeY0sqghBb8/4SIcCgYB5gU1GH1QsoCSPgE+AV317QeWHEvBQlIuMfJTVEfIrtI0bHsRZaSZ9F0T/3e5d4kwfaaN9GqaqlxC8HT68e0DehholsZ3/ilulJPQaft728y9ZEKkPoxtB2ZZ3U1sDHryMGjTI2jB461WayZiJVLMbSMGDAehilHTxikAUF3vI6QKBgQCU7WInXwPLLeZ1ogMGl74fvX6gcq39j9p7rkAI/Kv90lEQyHpcKhPR/e/08rnKzuLWHtXlHCIaRVHyyk22fhegsk2YVD9+cshW8BRpS+501nX1ksOK310WS9SrhawdxPkP2rBzlrncq8CVs9dLDIvtBL0KytR5/4FLUj2gmJpd6QKBgGNLjdysAYCd0GVVe7kKTuBks12jrMWbJqYq35NRTnKt3qYPe8Xuzy5WETDMWtWleIfXpbb+NEIQJ7ifs3dAJZ6/s/jo/tRawS8Hpa6j2oeGFcvCiI9rukd0gXuUDD2d0//RHxyJXpraE+5wx7JhAFm2opZOez98BgRoo0hISwAj',
        _notificationCallBack);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}

Future<void> _notificationCallBack(var response) async {
  response = response.replaceFirst('notification:', '');
  var responseJson = jsonDecode(response);
  var notificationKey = responseJson['key'];
  var fromAtSign = responseJson['from'];
  var atKey = notificationKey.split(':')[1];
  atKey = atKey.replaceFirst(fromAtSign, '');
  atKey = atKey.trim();
  if (atKey == 'stream_id') {
    var valueObject = responseJson['value'];
    var streamId = valueObject.split(':')[0];
    var fileName = valueObject.split(':')[1];
    var fileLength = int.parse(valueObject.split(':')[2]);
    fileName = utf8.decode(base64.decode(fileName));
    var userResponse = true; //UI user response
    if (userResponse == true) {
      print('user accepted transfer.Sending ack back');
      await atClient.sendStreamAck(streamId, fileName, fileLength, fromAtSign,
          _streamCompletionCallBack, _streamReceiveCallBack);
    }
  } else {
    //TODO handle other notifications
    print('some other notification');
    print(response);
  }
}

void _streamReceiveCallBack(var bytesReceived) {
  print('Receive callback bytes received: ${bytesReceived}');
}

void _streamCompletionCallBack(var streamId) {
  print('Transfer done for stream: ${streamId}');
}
