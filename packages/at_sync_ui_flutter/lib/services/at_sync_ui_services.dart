// ignore_for_file: implementation_imports, prefer_typing_uninitialized_variables

import 'dart:async';
import 'package:at_client/at_client.dart';
import 'package:at_sync_ui_flutter/at_sync_ui.dart';
import 'package:flutter/material.dart';

class AtSyncUIService extends SyncProgressListener {
  static final AtSyncUIService _singleton = AtSyncUIService._internal();

  AtSyncUIService._internal();

  factory AtSyncUIService() {
    return _singleton;
  }

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    if (AtSyncUIService().syncProgressCallback != null) {
      AtSyncUIService().syncProgressCallback!(syncProgress);
    }

    if (syncProgress.syncStatus == SyncStatus.success) {
      _hide();
      _atSyncUIListenerSink.add(AtSyncUIStatus.completed);
    }

    if (syncProgress.syncStatus == SyncStatus.failure) {
      _atSyncUIListenerSink.add(AtSyncUIStatus.failed);
    }
  }

  Function? onSuccessCallback,
      onErrorCallback,
      syncProgressCallback,
      onAtSignRemoved;
  SyncService? syncService;
  AtSyncUIStyle atSyncUIStyle = AtSyncUIStyle.cupertino;
  AtSyncUIOverlay atSyncUIOverlay = AtSyncUIOverlay.none;
  bool showTextWhileSyncing = true, showRemoveAtsignOption = false;
  Timer? _removeAtsignTimer;
  final int _removeAtsignSeconds = 60;

  final StreamController _atSyncUIListenerController =
      StreamController<AtSyncUIStatus>.broadcast();

  /// [atSyncUIListener] can be used to listen to sync status changes
  Stream<AtSyncUIStatus> get atSyncUIListener =>
      _atSyncUIListenerController.stream as Stream<AtSyncUIStatus>;

  StreamSink<AtSyncUIStatus> get _atSyncUIListenerSink =>
      _atSyncUIListenerController.sink as StreamSink<AtSyncUIStatus>;

  /// [appNavigator] is used for navigation purpose
  /// [atSyncUIOverlay] decides whether dialog or snackbar to be shown while syncing
  /// [style] if material or cupertino style to be applied
  /// [showTextWhileSyncing] should text be shown while syncing
  /// [onSuccessCallback] called after successful sync
  /// [onErrorCallback] called after failure in sync
  /// [syncProgressCallback] Notifies the registered listener for the [SyncProgress]
  /// [primaryColor],[backgroundColor], [labelColor] will be used while displaying overlay/snackbar.
  /// if [showRemoveAtsignOption] is true, [onAtSignRemoved] will be called if atSign is removed successfully from device
  void init({
    required GlobalKey<NavigatorState> appNavigator,
    AtSyncUIOverlay? atSyncUIOverlay = AtSyncUIOverlay.dialog,
    AtSyncUIStyle? style,
    bool? showTextWhileSyncing,
    Function? onSuccessCallback,
    Function? onErrorCallback,
    Function? syncProgressCallback,
    Function? onAtSignRemoved,
    Color? primaryColor,
    Color? backgroundColor,
    Color? labelColor,
    bool showRemoveAtsignOption = false,
    bool startTimer = true,
  }) {
    this.onSuccessCallback = onSuccessCallback;
    this.onErrorCallback = onErrorCallback;
    this.syncProgressCallback = syncProgressCallback;
    this.onAtSignRemoved = onAtSignRemoved;
    AtSyncUI.instance.setAppNavigatorKey(appNavigator);

    /// change status to notStarted
    _atSyncUIListenerSink.add(AtSyncUIStatus.notStarted);

    if (style != null) {
      atSyncUIStyle = style;
    }
    if (atSyncUIOverlay != null) {
      this.atSyncUIOverlay = atSyncUIOverlay;
    }
    this.showTextWhileSyncing = showTextWhileSyncing ?? true;
    this.showRemoveAtsignOption = showRemoveAtsignOption;

    AtSyncUI.instance.configTheme(
      primaryColor: primaryColor,
      backgroundColor: backgroundColor,
      labelColor: labelColor,
      style: style,
    );

    var _atSyncUIController = AtSyncUIController();
    AtSyncUI.instance.setupController(controller: _atSyncUIController);
    syncService = AtClientManager.getInstance().atClient.syncService;
    syncService!.addProgressListener(this);
    // ignore: deprecated_member_use
    syncService!.setOnDone(_onSuccessCallback);

    // ignore: deprecated_member_use_from_same_package
    sync(atSyncUIOverlay: atSyncUIOverlay!, startTimer: startTimer);
  }

  /// calls sync and shows selected UI
  /// [atSyncUIOverlay] decides whether dialog or snackbar to be shown while syncing
  @Deprecated("Only init should be called.")
  void sync({
    AtSyncUIOverlay atSyncUIOverlay = AtSyncUIOverlay.none,
    bool startTimer = true,
  }) {
    cancelTimer();
    this.atSyncUIOverlay = this.atSyncUIOverlay == AtSyncUIOverlay.none
        ? atSyncUIOverlay
        : this.atSyncUIOverlay;

    /// change status to syncing
    _atSyncUIListenerSink.add(AtSyncUIStatus.syncing);

    if (startTimer) {
      _removeAtsignTimer = Timer(Duration(seconds: _removeAtsignSeconds), () {
        _hide();
        cancelTimer();
        _show(
          atSyncUIOverlay: atSyncUIOverlay,
          showRemoveAtsignOption: true,
        );
      });
    }

    /// show showRemoveAtsignOption if we are not starting a timer
    _show(
      atSyncUIOverlay: atSyncUIOverlay,
      showRemoveAtsignOption: !startTimer,
    );
  }

  void _onSuccessCallback(SyncResult syncStatus) {
    cancelTimer();

    if ((syncStatus.syncStatus == SyncStatus.failure) &&
        (onErrorCallback != null)) {
      onErrorCallback!(syncStatus);
    }

    if (onSuccessCallback != null) {
      onSuccessCallback!(syncStatus);
    }
  }

  void _show(
      {AtSyncUIOverlay? atSyncUIOverlay, bool showRemoveAtsignOption = false}) {
    if ((atSyncUIOverlay ?? this.atSyncUIOverlay) == AtSyncUIOverlay.none) {
      return;
    }

    if ((atSyncUIOverlay ?? this.atSyncUIOverlay) == AtSyncUIOverlay.dialog) {
      AtSyncUI.instance.showDialog(
        message: showTextWhileSyncing ? 'Sync in progress' : null,
        showRemoveAtsignOption: showRemoveAtsignOption,
      );
      return;
    }

    AtSyncUI.instance.showSnackBar(
      message: showTextWhileSyncing ? 'Sync in progress' : null,
    );
  }

  void _hide() {
    if (atSyncUIOverlay == AtSyncUIOverlay.none) {
      return;
    }

    if (atSyncUIOverlay == AtSyncUIOverlay.dialog) {
      AtSyncUI.instance.hideDialog();
      return;
    }

    AtSyncUI.instance.hideSnackBar();
  }

  cancelTimer() {
    _removeAtsignTimer?.cancel();
  }
}

///Enum to represent the sync status for AtSyncUIFlutter
enum AtSyncUIStatus { syncing, completed, failed, notStarted }
