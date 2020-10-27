//import 'dart:io';
//import 'dart:isolate';
//import 'package:at_client/at_client.dart';
//import 'package:at_client/src/client/at_client_impl.dart';
//import 'package:at_client/src/manager/sync_manager.dart';
//import 'test_util.dart';

void main() async {
  // limitation due to hive.
//  try {
//    var preference = TestUtil.getPreference();
//    preference.syncStrategy = SyncStrategy.ONDEMAND;
//    var atClient = await AtClientImpl.getClient('@jagan','me', preference);
//    atClient.getRemoteSecondary().init('@jagan', preference);
//    var syncManager = SyncManager.getInstance();
//    syncManager.syncWithIsolate();
////    syncManager.syncOnDemandIsolate('@jagan', preference);
//
//  } on Exception catch (e, trace) {
//    print(e.toString());
//    print(trace);
//  }
}
