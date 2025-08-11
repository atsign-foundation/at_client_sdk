// import 'dart:convert';
// import 'dart:io';
// import 'package:at_client_mobile/at_client_mobile.dart';
// import 'package:at_login_flutter/domain/at_login_model.dart';
// import 'package:at_login_flutter/domain/at_login_provider.dart';
// import 'package:at_login_flutter/services/login_service.dart';
// import 'package:at_login_flutter/services/sdk_service.dart';
// import 'package:flutter_test/flutter_test.dart';
// import 'package:at_demo_data/at_demo_data.dart' as demo_data;
// import 'package:at_commons/at_commons.dart';
//
// SDKService _sdkService = SDKService();
// LoginService _loginService = LoginService();
//
// void main() {
//   String senderAtLogin = '@alice🛠';
//
//   setUp(() async {
//     _sdkService.setClientService = await setUpFunc(senderAtLogin);
//     _loginService.init();
//     AtLoginProvider().init();
//     await _sdkService.startMonitor(monitorCallBack);
//   });
//
//   group('test follow functionality', () {
//     test('with valid @sign', () async {
//       String receiverAtLogin = '@bob🛠';
//
//       var receiverAtClientService = await setUpFunc(receiverAtLogin);
//       await receiverAtClientService.atClient.startMonitor(
//           receiverAtClientService.atClient.preference.privateKey,
//           monitorCallBack);
//       AtLogin atLogin = await _loginService.allowLogin(receiverAtLogin);
//       expect(atLogin.requestorUrl, receiverAtLogin);
//       expect(
//           _loginService.allowedLoginList.list.contains(receiverAtLogin), isTrue);
//     });
//
//     test('with same @sign', () async {
//       AtLogin atLogin = await _loginService.allowLogin(senderAtLogin);
//       expect(atLogin, null);
//       expect(
//           _loginService.allowedLoginList.list.contains(senderAtLogin), isFalse);
//     });
//
//     test('with existing @sign', () async {
//       String receiverAtLogin = '@bob🛠';
//       AtLogin atLogin = await _loginService.allowLogin(receiverAtLogin);
//       expect(atLogin.requestorUrl, receiverAtLogin);
//       expect(
//           _loginService.allowedLoginList.list.contains(receiverAtLogin), isTrue);
//       AtLogin atLogin1 = await _loginService.allowLogin(receiverAtLogin);
//       expect(atLogin1, null);
//       expect(
//           _loginService.allowedLoginList.list.contains(receiverAtLogin), isFalse);
//     });
//
//     test('to support wavi and persona namespace', () async {
//       var firstAtSign = '@bob🛠';
//       var bobClientService = await setUpFunc(firstAtSign);
//       var metadata = Metadata()
//         ..isPublic = true
//         ..namespaceAware = false;
//       var bobFirstname = AtKey()
//         ..key = 'firstname.wavi'
//         ..metadata = metadata;
//       var bobLastname = AtKey()
//         ..key = 'lastname.wavi'
//         ..metadata = metadata;
//
//       await bobClientService.atClient.put(bobFirstname, 'Bob');
//       await bobClientService.atClient.put(bobLastname, 'Geller');
//
//       var secondAtSign = '@colin🛠';
//       var colinClientService = await setUpFunc(secondAtSign);
//       var metadata1 = Metadata()..isPublic = true;
//       var colinFirstname = AtKey()
//         ..key = 'firstname'
//         ..metadata = metadata1;
//       var colinLastname = AtKey()
//         ..key = 'lastname'
//         ..metadata = metadata1;
//
//       await colinClientService.atClient.put(colinFirstname, 'Colin');
//       await colinClientService.atClient.put(colinLastname, 'Felton');
//
//       AtLogin atLogin = await _loginService.allowLogin(firstAtSign);
//       expect(atLogin.requestorUrl, 'Bob Geller');
//       expect(_loginService.allowedLoginList.list.contains(firstAtSign), isTrue);
//
//       AtLogin atLogin1 = await _loginService.allowLogin(secondAtSign);
//       expect(atLogin1.requestorUrl, 'Colin Felton');
//       expect(_loginService.allowedLoginList.list.contains(secondAtSign), isTrue);
//     });
//   });
//
//   group('test unfollow functionality', () {
//     test('with existing @sign', () async {
//       String receiverAtLogin = '@bob🛠';
//       _loginService.allowedLoginList.add(receiverAtLogin);
//       var receiverAtClientService = await setUpFunc(receiverAtLogin);
//       await receiverAtClientService.atClient.startMonitor(
//           receiverAtClientService.atClient.preference.privateKey,
//           monitorCallBack);
//       bool result = await _loginService.disallowLogin(receiverAtLogin);
//       expect(result, true);
//       expect(
//           _loginService.allowedLoginList.list.contains(receiverAtLogin), isFalse);
//     });
//
//     test('with same @sign', () async {
//       bool result = await _loginService.disallowLogin(senderAtLogin);
//       expect(result, false);
//       expect(
//           _loginService.allowedLoginList.list.contains(senderAtLogin), isFalse);
//     });
//
//     test('with non existing @sign', () async {
//       String receiverAtLogin = '@bob🛠';
//       bool result = await _loginService.disallowLogin(receiverAtLogin);
//       expect(result, false);
//       expect(
//           _loginService.allowedLoginList.list.contains(receiverAtLogin), isFalse);
//     });
//   });
// }
//
// Future<void> tearDownFunc() async {
//   var isExists = await Directory('test/hive').exists();
//   if (isExists) {
//     Directory('test/hive').deleteSync(recursive: true);
//   }
// }
//
// Future<AtClientService> setUpFunc(String atLogin) async {
//   var preference = getAtSignPreference(atLogin);
//
//   AtClientService atClientService = AtClientService();
//
//   await AtClientImpl.createClient(atLogin, 'persona', preference);
//   var atClient = await AtClientImpl.getClient(atLogin);
//   atClientService.atClient = atClient;
//   atClient.getSyncManager().init(atLogin, preference,
//       atClient.getRemoteSecondary(), atClient.getLocalSecondary());
//   await atClient.getSyncManager().sync();
//   await setEncryptionKeys(atClient, atLogin);
//   return atClientService;
// }
//
// monitorCallBack(var response) {
//   if (response == null) {
//     return;
//   }
//   response = response.toString().replaceAll('notification:', '').trim();
//   var notification = AtLoginNotification.fromJson(jsonDecode(response));
//   print(
//       'Received notification:: id:${notification.id} key:${notification.key} operation:${notification.operation} from:${notification.requestorUrl} to:${notification.challenge}');
// }
//
// AtClientPreference getAtSignPreference(String atLogin) {
//   var preference = AtClientPreference();
//   preference.hiveStoragePath = 'test/hive/client';
//   preference.commitLogPath = 'test/hive/client/commit';
//   preference.isLocalStoreRequired = true;
//   preference.syncStrategy = SyncStrategy.IMMEDIATE;
//   preference.privateKey = demo_data.pkamPrivateKeyMap[atLogin];
//   preference.rootDomain = 'vip.ve.atLogin.zone';
//   return preference;
// }
//
// setEncryptionKeys(AtClientImpl atClient, String atLogin) async {
//   try {
//     var metadata = Metadata();
//     metadata.namespaceAware = false;
//     var result;
//     // set pkam private key
//     result = await atClient.getLocalSecondary().putValue(AT_PKAM_PRIVATE_KEY,
//         demo_data.pkamPrivateKeyMap[atLogin]); // set pkam public key
//     result = await atClient
//         .getLocalSecondary()
//         .putValue(AT_PKAM_PUBLIC_KEY, demo_data.pkamPublicKeyMap[atLogin]);
//     // set encryption private key
//     result = await atClient.getLocalSecondary().putValue(
//         AT_ENCRYPTION_PRIVATE_KEY, demo_data.encryptionPrivateKeyMap[atLogin]);
//     //set aesKey
//     result = await atClient
//         .getLocalSecondary()
//         .putValue(AT_ENCRYPTION_SELF_KEY, demo_data.aesKeyMap[atLogin]);
//
//     // set encryption public key. should be synced
//     metadata.isPublic = true;
//     var atKey = AtKey()
//       ..key = 'publickey'
//       ..metadata = metadata;
//     result =
//         await atClient.put(atKey, demo_data.encryptionPublicKeyMap[atLogin]);
//     print(result);
//   } catch (e) {
//     print('setting localKeys throws $e');
//   }
// }
