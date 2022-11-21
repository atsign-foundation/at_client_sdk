import 'dart:io';

import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/manager/sync_manager.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/response/response.dart';
import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/stream/at_stream_response.dart';
import 'package:at_client/src/stream/file_transfer_object.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_chops/at_chops.dart';

/// Interface for a client application that can communicate with a secondary server.
abstract class AtClient {
  /// Returns a singleton instance of [SyncManager] that is responsible for syncing data between
  /// local secondary server and remote secondary server.
  /// [Deprecated] Use [AtClientManager.syncService]
  @Deprecated("Use SyncManager.sync")
  SyncManager? getSyncManager();

  /// Returns a [RemoteSecondary] to communicate with user's cloud secondary server.
  RemoteSecondary? getRemoteSecondary();

  LocalSecondary? getLocalSecondary();

  void setAtChops(AtChops atChops);

  /// Sets the preferences such as sync strategy, storage path etc., for the client.
  void setPreferences(AtClientPreference preference);

  AtClientPreference? getPreferences();

  /// Updates value of [AtKey.key] is if it is already present. Otherwise creates a new key. Set [AtKey.sharedWith] if the key
  /// has to be shared with another atSign. Set [AtKey.metadata.isBinary] if you are updating binary value e.g image,file.
  /// By default namespace that is used to create the [AtClient] instance will be appended to the key. phone@alice will be saved as
  /// phone.persona@alice where 'persona' is the namespace. If you want to save by ignoring the namespace set [AtKey.metadata.namespaceAware]
  /// to false.
  /// Additional metadata can be set using [AtKey.metadata]
  ///
  /// [isDedicated] is currently ignored and will be removed in next major version
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
  /// Starting version 3.0.0 [isDedicated] is deprecated
  /// Throws [AtValueException] if invalid value type is found
  ///
  /// Throws [AtKeyException] if invalid key or metadata is found
  ///
  /// Throws [AtEncryptionException] if encryption process fails
  ///
  /// Throws [SelfKeyNotFoundException] if self encryption key is not found
  ///
  /// Throws [AtPrivateKeyNotFoundException] if encryption private key is not found
  ///
  /// Throws [AtPublicKeyNotFoundException] if encryption public key is not found
  Future<bool> put(AtKey key, dynamic value, {bool isDedicated = false});

  /// Used to store the textual data into the keystore.
  /// Updates value of [AtKey.key] is if it is already present. Otherwise creates a new key. Set [AtKey.sharedWith] if the key
  /// has to be shared with another atSign.
  /// By default namespace that is used to create the [AtClient] instance will be appended to the key. phone@alice will be saved as
  /// phone.persona@alice where 'persona' is the namespace.
  /// ```
  /// update:phone@alice +1 999 9999
  ///   var key = AtKey.self('phone', namespace: 'wavi').build();
  ///   putText(key,'+1 999 9999');
  /// update:public:phone@alice +1 999 9999
  ///   var key = AtKey.public('location', namespace: 'wavi').build();
  ///   put(key,'+1 999 9999');
  /// update:@bob:phone@alice +1 999 9999
  ///    var key = (AtKey.shared('phone', namespace: 'wavi')
  ///             ..sharedWith('@bob'))
  ///           .build();
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
  Future<AtResponse> putText(AtKey atKey, String value);

  /// Used to store the binary data into the keystore. For example: images, files etc.
  Future<AtResponse> putBinary(AtKey atKey, List<int> value);

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
  ///
  /// [isDedicated] is currently ignored and will be removed in next major version
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
  /// plookup public phone number of @bob
  /// plookup:phone@bob
  /// var metadata = Metadata()..isPublic=true;
  /// var publicPhoneKey = AtKey()..key = 'phone'
  ///                             ..sharedBy = '@bob'
  ///                             ..metadata = metadata;
  ///  get(publicPhoneKey);
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
  /// Throws [AtKeyException] for the invalid key formed
  ///
  /// Throws [AtDecryptionException] if fails to decrypt the value
  ///
  /// Throws [AtPrivateKeyNotFoundException] if the encryption private key is not found to decrypt the value
  ///
  /// Throws [AtPublicKeyChangeException] if the encryption public key used encrypt the value
  /// is different from the current encryption public key(at the time of decryption)
  ///
  /// Throws [SharedKeyNotFoundException] if the shared key to decrypt the value is not found
  ///
  /// Throws [SelfKeyNotFoundException] if the self encryption key is not found.
  ///
  /// Throws [AtClientException] if the cloud secondary is invalid or not reachable
  ///
  Future<AtValue> get(AtKey key,
      {bool isDedicated = false, GetRequestOptions? getRequestOptions});

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
  ///
  /// [isDedicated] is currently ignored and will be removed in next major version
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
      {String? regex,
      String? sharedBy,
      String? sharedWith,
      bool showHiddenKeys = false});

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
      {String? regex,
      String? sharedBy,
      String? sharedWith,
      bool showHiddenKeys = false});

  /// Notifies the [AtKey] with the [sharedWith] user of the atsign. Optionally, operation, value and metadata can be set along with key to notify.
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
  ///
  /// var atKey = AtKey()..key = 'phone@alice'
  ///                    ..sharedWith = '@bob'
  ///                    ..sharedBy = ‘@alice’
  /// Sending Notification with Notification Strategy ‘ALL’ and priority low
  /// await atClient.notify(atKey, ‘+1 987 986 2233’, OperationEnum.update,
  ///                       priority: PriorityEnum.low,
  ///                      strategy: StrategyEnum.all);
  ///
  /// Sending Notification with Notification Strategy ‘Latest N’ and priority high
  /// await atClient.notify(atKey, ‘+1 987 986 2233’, OperationEnum.update,
  ///                       priority: PriorityEnum.high,
  ///                       strategy: StrategyEnum.latest,
  ///                       latestN:3,
  ///                       Notifier: ‘wavi’);
  ///```
  ///[Deprecated] Use [AtClientManager.notificationService]
  @Deprecated("Use NotificationService")
  Future<bool> notify(AtKey key, String value, OperationEnum operation,
      {MessageTypeEnum? messageType,
      PriorityEnum? priority,
      StrategyEnum? strategy,
      int? latestN,
      String? notifier,
      bool isDedicated = false});

  /// Notifies the [NotificationParams.atKey] to [notificationParams.atKey.sharedWith] user
  /// of the atSign. Optionally, operation, value and metadata can be set along with key to
  /// notify.
  ///
  ///* Throws [LateInitializationError] when [NotificationParams.atKey] is not initialized
  ///* Throws [AtKeyException] when invalid [NotificationParams.atKey.key] is formed or when
  ///invalid metadata is provided.
  ///* Throws [InvalidAtSignException] on invalid [NotificationParams.atKey.sharedWith] or [NotificationParams.atKey.sharedBy]
  ///* Throws [AtClientException] when keys to encrypt the data are not found.
  ///* Throws [AtClientException] when [notificationParams.notifier] is null when [notificationParams.strategy] is set to latest.
  ///* Throws [AtClientException] when fails to connect to cloud secondary server.
  ///
  ///e.g alice is the current atsign
  ///
  /// 1. To notify a update of key to @bob
  /// ```dart
  ///   var key = AtKey()..key='phone'
  ///                    ..sharedWith='@bob'
  ///   var notificationParams = NotificationParams().._atKey = key
  ///                                                .._operation = OperationEnum.update
  ///                                                .._messageType = MessageTypeEnum.key;
  ///   notifyChange(notificationParams);
  /// ```
  /// 2. To notify and cache a key - value in @bob
  /// ```dart
  ///   var metaData = Metadata()..ttr='6000000';
  ///   var key = AtKey()..key='phone'
  ///                    ..sharedWith='@bob'
  ///                    ..metadata=metaData
  ///   var value='+1 999 9999'
  ///   var notificationParams = NotificationParams().._atKey = key
  ///                                                .._operation = OperationEnum.update
  ///                                                .._value = value
  ///                                                .._messageType = MessageTypeEnum.key;
  ///   notifyChange(notificationParams);
  ///```
  ///3. To notify a text message
  ///```dart
  ///   var key = AtKey()..key='phone'
  ///                    ..sharedWith='@bob'
  ///   var notificationParams = NotificationParams().._atKey = key
  ///                                                .._operation = OperationEnum.update
  ///                                                .._messageType = MessageTypeEnum.text;
  ///   notifyChange(notificationParams);
  ///```
  ///4. To notify a deletion of a key to @bob.
  ///```dart
  ///   var key = AtKey()..key='phone'
  ///                    ..sharedWith='@bob'
  ///   var notificationParams = NotificationParams().._atKey = key
  ///                                                .._operation = OperationEnum.delete
  ///                                                .._messageType = MessageTypeEnum.key;
  ///   notifyChange(notificationParams);
  ///```
  Future<String?> notifyChange(NotificationParams notificationParams);

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
  @Deprecated('Use NotificationService')
  Future<String> notifyAll(AtKey atKey, String value, OperationEnum operation);

  ///Returns the status of the notification
  ///```
  ///notify:status:75037ac4-6a15-43cc-ba66-e621bb2a6366
  ///
  /// var atKey = AtKey()..key = 'phone@bob'
  ///                    ..sharedWith = '@alice'
  ///                    ..sharedBy = ‘@bob’
  /// Execute the notify verb
  /// var notiticationId = await atClient.notify(atKey, ‘+1 987 986 2233’, OperationEnum.update);
  ///  Get the status for notificationId
  ///   notifyStatus(notiticationId);
  ///
  ///```
  Future<String> notifyStatus(String notificationId);

  ///Returns the list of received notifications of an atsign, Optionally, notifications can be filtered on from date, to date and regular expression
  ///```
  ///e.g alice is the current atsign
  ///  Get all the notifications
  ///  notify:list
  ///    notifyList();
  ///
  ///  Get notification starting from 2021-01-28 to 2021-01-29
  ///  notify:list:2021-01-28:2021-01-29
  ///     notifyList(fromDate: 2021-01-28, toDate: 2021-01-29);
  ///
  ///  Get notifications list which matches with the regex 'phone'
  ///  notify:list:phone
  ///     notifyList(regex: phone);
  ///
  ///  Get notification starting from 2021-01-28 to 2021-01-29 and
  ///         matches with the regex 'phone'
  ///  notify:list:2021-01-28:2021-01-29:phone
  ///     notifyList(fromDate: 2021-01-28, toDate: 2021-01-29, regex: phone);
  ///```
  Future<String> notifyList({String? fromDate, String? toDate, String? regex});

  /// Creates a monitor connection to atSign's cloud secondary server.Whenever a notification is created on the server, monitor receives
  /// the notification on the client.
  /// Optionally a regular expression and be passed to filter the notifications
  /// [deprecated] Use [NotificationService.subscribe]
  @Deprecated("Use Monitor Service")
  Future<void> startMonitor(String privateKey, Function acceptStream,
      {String? regex});

  /// Streams the file in [filePath] to [sharedWith] atSign.
  Future<AtStreamResponse> stream(String sharedWith, String filePath,
      {String namespace});

  /// Sends stream acknowledgement
  Future<void> sendStreamAck(
      String streamId,
      String fileName,
      int fileLength,
      String senderAtSign,
      Function streamCompletionCallBack,
      Function streamReceiveCallBack);

  /// Uploads list of [files] to filebin and shares the file download url with [sharedWithAtSigns]
  /// returns map containing key of each sharedWithAtSign and value of [FileTransferObject]
  @Deprecated(
      'Method will be removed from SDK since method is moved to app layer')
  Future<Map<String, FileTransferObject>> uploadFile(
      List<File> files, List<String> sharedWithAtSigns);

  /// Downloads the list of files for a given [transferId] shared by [sharedByAtSign]
  /// Optionally you can pass [downloadPath] to download the files.
  @Deprecated(
      'Method will be removed from SDK since method is moved to app layer')
  Future<List<File>> downloadFile(String transferId, String sharedByAtSign,
      {String? downloadPath});

  /// re uploads file in [fileTransferObject.fileUrl]
  /// returns list of [FileStatus] which contains upload status of each file.
  @Deprecated(
      'Method will be removed from SDK since method is moved to app layer')
  Future<List<FileStatus>> reuploadFiles(
      List<File> files, FileTransferObject fileTransferObject);

  /// re sends file notifications to [sharedWithAtSigns]
  /// returns [Map<String, FileTransferObject>] which contains transfer status for each atsign.
  @Deprecated(
      'Method will be removed from SDK since method is moved to app layer')
  Future<Map<String, FileTransferObject>> shareFiles(
      List<String> sharedWithAtSigns,
      String key,
      String fileUrl,
      String encryptionKey,
      List<FileStatus> fileStatus,
      {DateTime? date});

  String? getCurrentAtSign();

  EncryptionService? get encryptionService;
}
