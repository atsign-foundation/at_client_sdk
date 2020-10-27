import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/sync_manager.dart';

/// Class to hold attributes for client preferences.
/// Set the preferences for your application and pass it to [AtClientImpl.getClient].
class AtClientPreference {
  /// Local device path of hive storage
  String hiveStoragePath;

  /// Local device path of commit log
  String commitLogPath;

  /// Syncing strategy of the client [SyncStrategy]
  SyncStrategy syncStrategy;

  /// Specify whether local store is required
  bool isLocalStoreRequired = false;

  /// Shared secret of the atSign
  String cramSecret;

  /// Private key of the atSign
  String privateKey;

  /// Secret key to encrypt keystore data
  List<int> keyStoreSecret;

  /// Domain of the root server. Defaults to root.atsign.wtf
  String rootDomain = 'root.atsign.org';

  /// Port of the root server. Defaults to 64
  int rootPort = 64;

  /// Frequency of sync task to run in minutes. Defaults to 10 minutes.
  int syncIntervalMins = 10;

  /// Idle time in milliseconds of connection to secondary server. Default to 10 minutes.
  int outboundConnectionTimeout = 600000;

  /// Maximum data size a secondary can store. Temporary solution. Have to fetch this from
  /// server using stats verb.
  int maxDataSize = 512000;

  /// Default path to download stream files
  String downloadPath;
}

enum SyncStrategy {
  /// Sync local keys immediately to secondary server for update and delete commands.
  IMMEDIATE,

  /// Sync only when [SyncManager.sync] is invoked.
  ONDEMAND,

  /// Sync periodically once every time interval specified by [AtClientPreference.syncIntervalMins].
  SCHEDULED
}
