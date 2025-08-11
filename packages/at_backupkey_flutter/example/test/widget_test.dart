//import 'dart:io';
//
//import 'package:at_backupkey_flutter_example/main.dart';
//import 'package:at_client_mobile/at_client_mobile.dart';
//import 'package:at_commons/at_commons.dart';
//import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
//import 'package:at_onboarding_flutter/services/size_config.dart';
//import 'package:flutter/material.dart';
//import 'package:flutter_test/flutter_test.dart';
//
//import '../../test/at_demo_credentials.dart' as demo_data;
//import 'test_material_app.dart';
//
//void main() {
//  Widget _homeWidget({@required Widget home}) {
//    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
//      SizeConfig().init(context);
//      return home;
//    }));
//  }
//
//  AtClientService atClientService = AtClientService();
//  String atsign = '@alice🛠';
//  setUp(() async => await setUpFunc(atsign));
//  testWidgets('Verify Platform version', (WidgetTester tester) async {
//    // Build our app and trigger a frame.
//    await tester.pumpWidget(MyApp());
//
//    // Verify that platform version is retrieved.
//    expect(
//      find.byWidgetPredicate(
//        (Widget widget) =>
//            widget is Text && widget.data.startsWith('Running on:'),
//      ),
//      findsOneWidget,
//    );
//  });
//
//  group('test backupkey widget', () {
//    testWidgets('valid @sign', (WidgetTester tester) async {
//      tester.pumpWidget(_homeWidget(
//          home: BackupKeyWidget(
//              atsign: atsign, atClientService: atClientService)));
//    });
//  });
//
//  try {
//    tearDown(() async => await tearDownFunc());
//  } on Exception catch (e) {
//    print('error in tear down:${e.toString()}');
//  }
//}
//
//Future<void> tearDownFunc() async {
//  var isExists = await Directory('test/hive').exists();
//  if (isExists) {
//    Directory('test/hive').deleteSync(recursive: true);
//  }
//}
//
//Future<void> setUpFunc(String atsign) async {
//  var preference = getAtSignPreference(atsign);
//
//  await AtClientImpl.createClient(atsign, 'persona', preference);
//  var atClient = await AtClientImpl.getClient(atsign);
//  atClient.getSyncManager().init(atsign, preference,
//      atClient.getRemoteSecondary(), atClient.getLocalSecondary());
//  await atClient.getSyncManager().sync();
//  // To setup encryption keys
//  await atClient.getLocalSecondary().putValue(
//      AT_ENCRYPTION_PRIVATE_KEY, demo_data.encryptionPrivateKeyMap[atsign]);
//}
//
//AtClientPreference getAtSignPreference(String atsign) {
//  var preference = AtClientPreference();
//  preference.hiveStoragePath = 'test/hive/client';
//  preference.commitLogPath = 'test/hive/client/commit';
//  preference.isLocalStoreRequired = true;
//  preference.syncStrategy = SyncStrategy.IMMEDIATE;
//  preference.privateKey = demo_data.pkamPrivateKeyMap[atsign];
//  preference.rootDomain = 'vip.ve.atsign.zone';
//  return preference;
//}
