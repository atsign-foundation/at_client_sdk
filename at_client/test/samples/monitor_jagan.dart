import 'dart:convert';
import 'dart:io';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'test_util.dart';
AtClient atClient;
void main() async {
//  try {
//    var atClient =
//        await AtClientImpl.createClient('@jagan', 'me', TestUtil.getJaganPreference());
//  } on Exception catch (e, trace) {
//    print(e.toString());
//    print(trace);
//  }
}

void monitorCallBack(var response) async {
  print(response);
  response = response.replaceFirst('notification:', '');
  var responseJson = jsonDecode(response);
  var notificationKey = responseJson['key'];
  var atKey = notificationKey.split(':')[1];
  var fromAtSign = responseJson['from'];
  atKey = atKey.replaceFirst(fromAtSign,'');
  print(atKey);
}

