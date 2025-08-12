import 'package:at_client/at_client.dart';
import 'package:at_sync_ui_flutter/at_sync_ui.dart';
import 'package:at_sync_ui_flutter/at_sync_ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSyncService extends Mock implements SyncService {}

class MockAtCLientManager extends Mock implements AtClientManager {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GlobalKey<NavigatorState> _key = GlobalKey();
  MockSyncService mockSyncService = MockSyncService();

  group('sync service test', () {
    test('AtSyncUIService init', () {
      AtSyncUIService().syncService = mockSyncService;
      AtClientManager.getInstance().atClient.syncService = mockSyncService;

      AtSyncUIService().init(
        appNavigator: _key,
        atSyncUIOverlay: AtSyncUIOverlay.dialog,
        primaryColor: Colors.red,
        onSuccessCallback: () {},
        onErrorCallback: () {},
        syncProgressCallback: () {},
        onAtSignRemoved: () {},
        showRemoveAtsignOption: true,
      );

      expect(
        AtSyncUI.instance.appNavigatorKey,
        isA<GlobalKey<NavigatorState>>(),
      );

      expect(
        AtSyncUIService().atSyncUIOverlay,
        AtSyncUIOverlay.dialog,
      );

      expect(
        AtSyncUIService().onSuccessCallback,
        isA<Function>(),
      );

      expect(
        AtSyncUIService().onErrorCallback,
        isA<Function>(),
      );

      expect(
        AtSyncUIService().syncProgressCallback,
        isA<Function>(),
      );

      expect(
        AtSyncUIService().onAtSignRemoved,
        isA<Function>(),
      );

      expect(
        AtSyncUIService().showRemoveAtsignOption,
        true,
      );
    });

    test('AtSyncUIService sync', () {
      AtSyncUIService().syncService = mockSyncService;
      AtClientManager.getInstance().atClient.syncService = mockSyncService;

      AtSyncUIService().init(
          appNavigator: _key,
          primaryColor: Colors.red,
          onSuccessCallback: () {},
          onErrorCallback: () {},
          syncProgressCallback: () {},
          atSyncUIOverlay: AtSyncUIOverlay.snackbar);

      AtSyncUIService().atSyncUIListener.listen((AtSyncUIStatus status) {
        expect(
          status,
          AtSyncUIStatus.syncing,
        );
      });

      expect(
        AtSyncUIService().atSyncUIOverlay,
        AtSyncUIOverlay.snackbar,
      );
    });
  });
}
