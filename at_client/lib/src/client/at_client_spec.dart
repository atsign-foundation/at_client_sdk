import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/manager/sync_manager.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/stream/at_stream.dart';
import 'package:at_commons/at_commons.dart';

/// Interface for a client application that can communicate with a secondary server.
abstract class AtClient {
  /// Returns a singleton instance of [SyncManager] that is responsible for syncing data between
  /// local secondary server and remote secondary server.
  SyncManager? getSyncManager();

  /// Returns a singleton instance of [RemoteSecondary] to communicate with user's secondary server.
  RemoteSecondary? getRemoteSecondary();

  LocalSecondary? getLocalSecondary();

  /// Sets the preferences such as sync strategy, storage path etc., for the client.
  void setPreferences(AtClientPreference preference);

  /// Updates value of [AtKey.key] is if it is already present. Otherwise creates a new key. Set [AtKey.sharedWith] if the key
  /// has to be shared with another atSign. Set [AtKey.metadata.isBinary] if you are updating binary value e.g image,file.
  /// By default namespace that is used to create the [AtClient] instance will be appended to the key. phone@alice will be saved as
  /// phone.persona@alice where 'persona' is the namespace. If you want to save by ignoring the namespace set [AtKey.metadata.namespaceAware]
  /// to false.
  /// Additional metadata can be set using [AtKey.metadata]
  /// [isDedicated] need to be set to true to create a dedicated connection
  /// ```
  /// update:phone@alice +1 999 9999
  ///   var key = AtKey()..key='phone'
  ///   put(key,'+1 999 9999');
  /// update:public:phone@alice +1 999 9999
  ///   var metaData = Metadata()..isPublic=true;
  ///   var key = AtKey()..key='phone'
  ///             ..metadata=metaData
  ///   put(key,'+1 999 9999');
  /// update:@bob:phone@alice +1 999 9999
  ///   var metaData = Metadata()..sharedWith='@bob';
  ///    var key = AtKey()..key='phone'
  ///                   ..metadata=metaData
  ///   put(key,'+1 999 9999');
  /// update:@alice:phone.persona@alice +1 999 9999
  ///   var key = AtKey()..key='phone'
  ///             ..sharedWith='@alice'
  ///   put(key, '+1 999 9999');
  /// update:@alice:phone@alice +1 999 9999
  ///   var metaData = Metadata()..namespaceAware=false
  ///   var key = AtKey()..key='phone'
  ///            sharedWith='@alice'
  ///   put(key, '+1 999 9999');
  /// update:@bob:phone.persona@alice +1 999 9999
  ///   var key = AtKey()..key='phone'
  ///             sharedWith='@bob'
  ///    put(key, '+1 999 9999');
  /// ```
  Future<bool> put(AtKey key, dynamic value, {bool isDedicated = false});

  /// Updates the metadata of [AtKey.key] if it is already present. Otherwise creates a new key without a value.
  /// By default namespace that is used to create the [AtClient] instance will be appended to the key. phone@alice will be saved as
  /// phone.persona@alice where 'persona' is the namespace. If you want to save by ignoring the namespace set [AtKey.metadata.namespaceAware]
  /// to false.
  /// ```
  /// update:meta:phone@alice:ttl:60000
  ///   var metaData = Metadata()..ttl = 60000
  ///   var key = AtKey()..key='phone'
  ///             ..metadata=metaData
  ///   putMeta(key);
  /// update:meta:phone@alice:ttr:120000:ccd:true
  ///   var metaData = Metadata()..ttr = '120000'
  ///                            ..ccd = true
  ///   var key = AtKey()..key='phone'
  ///             ..metadata=metaData
  ///   putMeta(key);
  /// ```
  /// If you want to set both value and metadata please use [put]
  Future<bool> putMeta(AtKey key);

  /// Get the value of [AtKey.key] from user's cloud secondary if [AtKey.sharedBy] is set. Otherwise looks up the key from local secondary.
  /// If the key was stored with public access, set [AtKey.metadata.isPublic] to true. If the key was shared with another atSign set [AtKey.sharedWith]
  /// [isDedicated] need to be set to true to create a dedicated connection
  /// ```
  /// e.g alice is current atsign
  /// llookup:phone@alice
  ///   var atKey = AtKey()..key='phone'
  ///   get(atKey);
  /// llookup:public:phone@alice
  ///   var metaData = Metadata()..isPublic=true;
  ///   var atKey = AtKey()..key='phone'
  ///             ..metadata=metaData
  ///   get(atKey);
  /// lookup:phone@bob
  ///   var metaData = Metadata()..sharedWith='@bob';
  ///   var key = AtKey()..key='phone'
  ///                   ..metadata=metaData
  ///   get(key);
  /// llookup:@alice:phone.persona@alice
  ///   var key = AtKey()..key='phone'
  ///             ..sharedWith='@alice'
  ///   get(key);
  /// llookup:@alice:phone@alice
  ///   var metaData = Metadata()..namespaceAware=false
  ///   var key = AtKey()..key='phone'
  ///             ..sharedWith='@alice'
  ///   get(key);
  ///
  /// @alice : update:@bob:phone.personal@alice
  /// @bob   : lookup:phone.persona@alice
  ///   var key = AtKey()..key='phone'
  ///             ..sharedBy='@bob';
  ///   get(key);
  ///
  /// lookup:public:phone@alice
  ///   var metaData = Metadata()..isPublic=true
  ///                   ..namespaceAware='false'
  ///   var key = AtKey()..key='phone'
  ///             ..metadata=metaData
  ///   get(key);
  /// ```
  Future<AtValue> get(AtKey key, {bool isDedicated = false});

  /// Gets the metadata of [AtKey.key]
  /// ```
  /// e.g alice is current atsign
  /// llookup:phone@alice
  ///   var atKey = AtKey()..key='phone'
  ///   getMeta(atKey);
  /// llookup:public:phone@alice
  ///   var metaData = Metadata()..isPublic=true;
  ///   var atKey = AtKey()..key='phone'
  ///             ..metadata=metaData
  ///   getMeta(atKey);
  /// lookup:phone@bob
  ///   var metaData = Metadata()..sharedWith='@bob';
  ///    var atKey = AtKey()..key='phone'
  ///                   ..metadata=metaData
  ///   getMeta(atKey);
  ///
  /// ```
  Future<Metadata?> getMeta(AtKey key);

  /// Delete the [key] from user's local secondary and syncs the delete to cloud secondary if client's sync preference is immediate.
  /// By default namespace that is used to create the [AtClient] instance will be appended to the key. phone@alice translates to
  /// phone.persona@alice where 'persona' is the namespace. If you want to ignoring the namespace set [AtKey.metadata.namespaceAware]
  /// to false.
  /// [isDedicated] need to be set to true to create a dedicated connection
  /// ```
  /// e.g alice is current atsign
  /// delete:phone@alice
  ///   var metaData = Metadata()..namespaceAware=false
  ///   var key = AtKey()..key='phone'
  ///             ..metadata=metaData
  ///   delete(key);
  /// delete:@bob:phone@alice
  ///   var metaData = Metadata()..namespaceAware=false
  ///   var key = AtKey()..key='phone'
  ///             ..sharedWith='@bob'
  ///             ..metadata=metaData
  ///   delete(key);
  /// delete:public:phone.persona@alice
  ///   var metaData = Metadata()..isPublic=true
  ///                   ..namespaceAware=true
  ///   var key = AtKey()..key='phone'
  ///              ..metadata=metaData
  /// delete:@alice:phone.persona@alice
  ///   var key = AtKey()..key='phone'
  ///             ..sharedWith='@alice'
  ///   delete(key);
  /// delete:@alice:phone@alice
  ///   var metaData = Metadata()..namespaceAware=false
  ///   var key = AtKey()..key = 'phone'
  ///             ..sharedWith='@alice'
  ///             ..metadata=metaData
  ///   delete(key);
  /// delete:@bob:phone.persona@alice
  ///   var key = AtKey()..key = 'phone'
  ///             ..sharedWith='@bob'
  ///   delete(key);
  ///
  /// delete:public:phone@alice
  ///   var metaData = Metadata()..namespaceAware=false
  ///                  ..isPublic=true
  ///   var key = AtKey()..key = 'phone'
  ///             ..metadata = metaData
  ///   delete(key);
  ///```
  Future<bool> delete(AtKey key, {bool isDedicated = false});

  /// Get all the keys stored in user's secondary in [AtKey] format. If [regex] is specified only matching keys are returned.
  /// If [sharedBy] is specified, then gets the keys from [sharedBy] user shared with current atClient user.
  /// If [sharedWith] is specified, then gets the keys shared to [sharedWith] user from the current atClient user.
  /// ```
  /// e.g alice is the current atsign
  ///  scan
  ///   getKeys();
  ///  scan .persona
  ///   getKeys(regex:'.persona');
  ///  scan:@bob
  ///   getKeys(sharedBy:'@bob');
  ///```
  Future<List<AtKey>> getAtKeys(
      {String? regex, String? sharedBy, String? sharedWith});

  /// Get all the keys stored in user's secondary in string format. If [regex] is specified only matching keys are returned.
  /// If [sharedBy] is specified, then gets the keys from [sharedBy] user shared with current atClient user.
  /// If [sharedWith] is specified, then gets the keys shared to [sharedWith] user from the current atClient user.
  /// ```
  /// e.g alice is the current atsign
  ///  scan
  ///   getKeys();
  ///  scan .persona
  ///   getKeys(regex:'.persona');
  ///  scan:@bob
  ///   getKeys(sharedBy:'@bob');
  ///```
  Future<List<String>> getKeys(
      {String? regex, String? sharedBy, String? sharedWith});

  /// Notifies the [AtKey] with the [sharedWith] user of the atsign. Optionally, operation, value and metadata can be set along with key to notify.
  /// [isDedicated] need to be set to true to create a dedicated connection
  ///```
  ///e.g alice is the current atsign
  /// notify:update:@bob:phone@alice:+1 999 9999
  ///   var key = AtKey()..key='phone'
  ///             ..sharedWith='@bob'
  ///   var value='+1 999 9999'
  ///   var operation=OperationEnum.update
  ///   notify(key, value, operation);
  /// notify:update:ttl:60000:ttb:30000:@bob:phone@alice:+1 999 9999
  ///   var metaData = Metadata()..ttl='60000'
  ///                  ..ttb='30000'
  ///   var key = AtKey()..key='phone'
  ///             ..sharedWith='@bob'
  ///             ..metadata=metaData
  ///   var value='+1 999 9999'
  ///   var operation=OperationEnum.update
  ///   notify(key, value, operation);
  ///```
  Future<void> notify(AtKey key, String value, OperationEnum operation,
      Function onDone, Function onError,
      {MessageTypeEnum? messageType,
      PriorityEnum? priority,
      StrategyEnum? strategy,
      int? latestN,
      String? notifier,
      bool isDedicated = false});

  /// Notifies the [AtKey] with the list of [sharedWith] user's of the atsign. Optionally, operation, value and metadata can be set along with the key to notify.
  /// ```
  /// e.g alice is the current atsign
  /// notify:all:update:@bob,@colin:phone@alice:+1 999 9999
  ///   var key = AtKey()..key='phone'
  ///             ..sharedWith= json.encode(['@bob',@colin])
  ///   var value='+1 999 9999'
  ///   var operation=OperationEnum.update
  ///   notify(key, value, operation);
  /// notify:update:ttl:60000:ttb:30000:@bob,@colin:phone@alice:+1 999 9999
  ///   var metaData = Metadata()..ttl='60000'
  ///                  ..ttb='30000'
  ///   var key = AtKey()..key='phone'
  ///             ..sharedWith= json.encode(['@bob',@colin])
  ///             ..metadata=metaData
  ///   var value='+1 999 9999'
  ///   var operation=OperationEnum.update
  ///   notify(key, value, operation);
  /// ```
  Future<String> notifyAll(AtKey atKey, String value, OperationEnum operation);

  ///Returns the status of the notification
  ///```
  ///notify:status:75037ac4-6a15-43cc-ba66-e621bb2a6366
  ///
  ///   notifyStatus('75037ac4-6a15-43cc-ba66-e621bb2a6366');
  ///```
  Future<void> notifyStatus(
      String notificationId, Function onDone, Function onError);

  ///Returns the list of received notifications of an atsign, Optionally, notifications can be filtered on from date, to date and regular expression
  ///```
  ///e.g alice is the current atsign
  ///  notify:list
  ///    notifyList();
  ///  notify:list:2021-01-28:2021-01-29
  ///     notifyList(fromDate: 2021-01-28, toDate: 2021-01-29);
  ///  notify:list:phone
  ///     notifyList(regex: phone);
  ///  notify:list:2021-01-28:2021-01-29:phone
  ///     notifyList(fromDate: 2021-01-28, toDate: 2021-01-29, regex: phone);
  ///```
  Future<String> notifyList({String? fromDate, String? toDate, String? regex});

  Future<void> startMonitor(Function notificationCallback,
      Function errorCallback, MonitorPreference monitorPreference);

  /// Transfers a file specified by [filePath] to the [sharedWith] atSign through a stream verb
  /// Optionally specify a unique [namespace] for all stream transfers from your app
  /// [Deprecated] use [createStream]
  Future<void> stream(String sharedWith, String filePath, {String namespace});

  AtClientPreference getPreference();

  String getCurrentAtSign();

  /// Create a stream for a given [streamType]. If your app is sending a file through stream
  /// then pass [StreamType.SEND]. If your app is receiving a file pass [StreamType.RECEIVE].
  /// Optionally pass [streamId] if you want to create a stream for a known stream transfer.
  AtStream createStream(StreamType streamType, {String? streamId});
}
