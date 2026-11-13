import 'dart:async';
import 'package:at_client/src/client/at_reachability.dart';

import 'package:at_auth/at_auth.dart' show AtKeysIo;
import 'package:at_client/src/client/data_event.dart';
import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/lifecycle/at_connection.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/service/enrollment_service.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_client/src/collections/collections.dart';
import 'package:at_client/src/response/response.dart';
import 'package:at_client/src/service/encryption_service.dart';

/// Interface for a client application that can communicate with a secondary server.
abstract class AtClient {
  /// The connection this client sends verbs to its atServer on.
  ///
  /// You should not use this. If you have to, because nothing else does what
  /// you need, please file a feature request at
  /// https://github.com/atsign-foundation/at_client_sdk/issues so that there
  /// is an alternative.
  RemoteSecondary? getRemoteSecondary();

  /// The local store this client reads and writes first.
  ///
  /// You should not use this. If you have to, because nothing else does what
  /// you need, please file a feature request at
  /// https://github.com/atsign-foundation/at_client_sdk/issues so that there
  /// is an alternative.
  LocalSecondary? getLocalSecondary();

  /// Stream of [DataEvent]s — `DataUpdated` for every successful local
  /// keystore mutation that passes through the update path,
  /// `DataDeleted` for every successful one that passes through the
  /// delete path. Subscribers see local app writes AND sync-applied
  /// remote changes via a single uniform stream. Internal-bookkeeping
  /// writes (e.g. `putValue`) intentionally do NOT emit — see the
  /// [DataEvent] dartdoc.
  ///
  /// Async (microtask-scheduled) by default; pair with
  /// [pendingEmissions] when caller-side semantics need "all events
  /// for my write have been delivered to listeners".
  Stream<DataEvent> get dataEvents;

  /// Resolves once every event currently in-flight on [dataEvents]
  /// has been delivered to all listeners. Useful for callers that
  /// just performed a write and want to observe the resulting event
  /// before continuing — `await atClient.pendingEmissions` gives
  /// "watch streams up-to-date" semantics without sync-emission's
  /// re-entrancy / listener-stalls-writer hazards.
  ///
  /// Returns `Future.value()` immediately when there are no in-flight
  /// emits.
  Future<void> get pendingEmissions;

  /// Waits until other atSigns can seal data to [namespace] for this atSign,
  /// doing whatever is missing, and reports what happened.
  ///
  /// Sending and receiving are not symmetric: sending needs the recipient's
  /// published key, while receiving needs this atSign's own key published by a
  /// startup step that is not awaited, so a process can finish its work and
  /// exit while peers still see no published key for it. This is for the
  /// caller that must not exit until it is reachable; nothing calls it for
  /// you, and it is idempotent and cheap when there is nothing to do.
  ///
  /// A concurrent call in this process, or this client's own PQ startup,
  /// waits for a mint already in flight and adopts what it published. Another
  /// process that is minting, of this enrollment or another, holds the mint
  /// lock: a call that meets it mints nothing and answers
  /// [AtReachability.failed] while nothing is published, and a process that
  /// stopped before publishing leaves the lock held until its ttl runs out.
  ///
  /// Answers rather than throws for the three cases that are configuration and
  /// not failure — a posture that does not seed, a namespace this enrollment
  /// cannot hold a key for, and an enrollment carrying no key package. Read
  /// [AtReachabilityResult.isReachable] rather than comparing the outcome, and
  /// [AtReachabilityResult.holdsPrivate] for whether this client can also open
  /// what peers seal there.
  ///
  /// Nothing is left in flight when this returns [AtReachability.published]:
  /// the private half is conveyed to this atSign's other enrollments before the
  /// advertisement is written, and the advertisement is an awaited remote write
  /// rather than a local-first put, so a peer's `plookup` finds it on return.
  /// An enrollment the conveyance cannot reach is logged rather than fatal; it
  /// asks for the private at its next start, or at the first read that misses
  /// it.
  ///
  /// [timeout] bounds the whole operation, which may take several round
  /// trips. On [AtReachability.timedOut] nothing is known about whether the
  /// work eventually lands.
  Future<AtReachabilityResult> ensureReachable(String namespace,
      {Duration timeout = const Duration(seconds: 30)});

  /// The client's key source (`package:at_auth`), given at construction
  /// through `AtClientImpl.create(atKeysIo:)`, which requires one.
  /// `CryptoRuntime` threads it to providers as `CryptoContext.io`.
  AtKeysIo? get atKeysIo;

  /// Enrollment id for apkam enrolled clients
  set enrollmentId(String? enrollmentId);

  String? get enrollmentId;

  set syncService(SyncService syncService);

  SyncService get syncService;

  set notificationService(NotificationService notificationService);

  NotificationService get notificationService;

  set enrollmentService(EnrollmentService? enrollmentService);

  EnrollmentService? get enrollmentService;

  /// Sets the preferences this client reads, such as its namespace and its
  /// post-quantum posture. A client below its posture floor is raised to it
  /// again, on its own copy of [preference].
  void setPreferences(AtClientPreference preference);

  /// The preferences this client runs on. A client raised to its posture
  /// floor runs on its own copy of the preference it was given, so a setting
  /// changes through this or [setPreferences], not through that object.
  AtClientPreference? getPreferences();

  /// Whether [stop] has run.
  ///
  /// Once true, this instance's background services — the keystore-event
  /// timers, the data-event stream, the sync and notification services and
  /// the connection — are torn down, it holds no storage, and it cannot be
  /// restarted: the atSign is opened again with `Atsign.open`, which builds
  /// a new client.
  bool get isStopped;

  /// Whether this client has reached its atServer: online, offline or
  /// refused, as a current value and a stream of changes, with a way to try
  /// again now.
  AtConnection get connection;

  /// Stops everything this client runs: the keystore-event timers, the
  /// data-event stream, the sync and notification services and the
  /// connection, whose state ends as `offline(stopped)`. Every connection the
  /// client opened is closed by the time this returns, the monitor's and
  /// sync's included, and so is one it was handed. The client's claim on its
  /// storage is released; storage built with `closedByClient: true` is
  /// closed, while storage the caller supplied otherwise stays open for the
  /// caller to close.
  ///
  /// Does not drain: work in flight is not awaited, and fails with
  /// [StoppedException] where the stop cut it off. A sync round is abandoned
  /// at its next step, and what it had not pushed stays queued for the next
  /// client on this store. An app that wants its writes on the atServer first
  /// waits until `syncService.isInSync()` answers true.
  ///
  /// After this, a read or write of local storage throws [StoppedException],
  /// and the services are gone: reading one throws [StoppedException] too.
  ///
  /// A stopped client cannot be restarted, and the atSign can be opened
  /// again at once: the refusal of a second live client for the same
  /// principal or storage ends with this call.
  Future<void> stop();

  /// Updates value of [AtKey.key] is if it is already present. Otherwise creates a new key. Set [AtKey.sharedWith] if the key
  /// has to be shared with another atSign. Set [AtKey.metadata.isBinary] if you are updating binary value e.g image,file.
  /// By default namespace that is used to create the [AtClient] instance will be appended to the key. phone@alice will be saved as
  /// phone.persona@alice where 'persona' is the namespace. If you want to save by ignoring the namespace set [AtKey.metadata.namespaceAware]
  /// to false.
  /// Additional metadata can be set using [AtKey.metadata]
  ///
  /// [putRequestOptions] allows additional options to be provided. See [PutRequestOptions]
  ///
  /// From at_client v3.0.55 lowercase will be enforced on all AtKey types
  /// AtKeys will now be actively converted to lowercase in at_client
  /// The values(AtValue) will however continue to be case-sensitive
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
  ///
  /// At `PqPosture.pqActive`, a put made right after the client opens, before
  /// its start-up has published the namespace key the value is sealed to,
  /// waits for that key, at most 30 seconds, and then throws
  /// `NamespaceKeyUnavailableException` naming it if it is still not
  /// published. Start-up publishes that key only after its earlier steps
  /// finish, so the 30 seconds cover those too. Stopping the client ends the
  /// wait with [StoppedException].
  Future<bool> put(AtKey key, dynamic value,
      {PutRequestOptions? putRequestOptions});

  /// Used to store the textual data into the keystore.
  /// Updates value of [AtKey.key] is if it is already present. Otherwise creates a new key. Set [AtKey.sharedWith] if the key
  /// has to be shared with another atSign.
  /// By default namespace that is used to create the [AtClient] instance will be appended to the key. phone@alice will be saved as
  /// phone.persona@alice where 'persona' is the namespace.
  ///
  /// [putRequestOptions] allows additional options to be provided. See [PutRequestOptions]
  ///
  /// From at_client v3.0.55 lowercase will be enforced on all AtKey types
  /// The values(AtValue) will however continue to be case-sensitive
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
  Future<AtResponse> putText(AtKey atKey, String value,
      {PutRequestOptions? putRequestOptions});

  /// Used when storing binary data - e.g. images, files etc.
  /// See also [AtClient.put] and [AtClient.putText]
  Future<AtResponse> putBinary(AtKey atKey, List<int> value,
      {PutRequestOptions? putRequestOptions});

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
  Future<bool> putMeta(AtKey key, {PutRequestOptions? putRequestOptions});

  /// Get the value of [AtKey.key] from user's cloud secondary if [AtKey.sharedBy] is set. Otherwise looks up the key from local secondary.
  /// If the key was stored with public access, set [AtKey.metadata.isPublic] to true. If the key was shared with another atSign set [AtKey.sharedWith]
  ///
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
  Future<AtValue> get(AtKey key, {GetRequestOptions? getRequestOptions});

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

  /// Deletes [key] from local storage, and sync later pushes the removal to
  /// the atServer; [DeleteRequestOptions.useRemoteAtServer] sends it to the
  /// atServer directly.
  /// By default namespace that is used to create the [AtClient] instance will be appended to the key. phone@alice translates to
  /// phone.persona@alice where 'persona' is the namespace. If you want to ignoring the namespace set [AtKey.metadata.namespaceAware]
  /// to false.
  ///
  /// [deleteRequestOptions] allows additional options to be provided. See [DeleteRequestOptions]
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
  Future<bool> delete(AtKey key, {DeleteRequestOptions? deleteRequestOptions});

  /// Does a key exist
  Future<bool> keyExists(AtKey key, bool? useRemoteAtServer);

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
  Future<List<AtKey>> getAtKeys({
    String? regex,
    String? sharedBy,
    String? sharedWith,
    bool showHiddenKeys = false,
    bool useRemoteAtServer = false,
  });

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
  Future<List<String>> getKeys({
    String? regex,
    String? sharedBy,
    String? sharedWith,
    bool showHiddenKeys = false,
    bool useRemoteAtServer = false,
  });

  ///Returns the status of the notification
  ///```
  ///notify:status:75037ac4-6a15-43cc-ba66-e621bb2a6366
  ///
  /// var atKey = AtKey()..key = 'phone'
  ///                    ..sharedWith = '@alice'
  ///                    ..sharedBy = '@bob';
  /// Send the notification
  /// var result = await atClient.notificationService.notify(
  ///     NotificationParams.forUpdate(atKey, value: '+1 987 986 2233'));
  ///  Get the status for its id
  ///   notifyStatus(result.notificationID);
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

  static const defaultSppExpiry = Duration(minutes: 5);

  /// Sets a Semi Permanent Passcode (SPP) in the secondary server
  /// key-store. An SPP is a 6-character alphanumeric code used when
  /// submitting an enrollment request. Only connections with access
  /// to the "__manage" namespace are allowed to set an SPP.
  ///
  /// [expiry] caps how long the SPP is valid; defaults to
  /// [defaultSppExpiry] (5 minutes) when omitted, with a warning
  /// logged. Pass an explicit duration to opt into a different TTL.
  ///
  /// Returns an [AtResponse] whose `response` field is "ok" on
  /// success.
  ///
  /// Throws [InvalidPinException] when [otp] is not 6 alphanumeric
  /// characters.
  ///
  /// Throws [AtClientException] when the enrollmentId does not exist
  /// or does not have access to the "__manage" namespace.
  ///
  /// ```dart
  /// AtResponse sppResponse = await atClient.setSPP('ABC123');
  /// ```
  Future<AtResponse> setSPP(String otp, {Duration? expiry});

  /// Returns an OTP (One-Time Password) from the secondary server.
  ///
  ///
  /// Example usage:
  /// ```dart
  /// AtResponse otpResponse = await atClient.getOTP();
  /// ```
  ///
  Future<AtResponse> getOTP();

  /// Note - this method name is misleading as 'current' implies the atSign
  /// could change - but an AtClient should only ever have one atSign.
  String? getCurrentAtSign();

  Atsign get atSign;

  EncryptionService? get encryptionService;

  /// Returns an [AtCollection] of [CItem]s for the given [namespace].
  ///
  /// [namespace] **MUST be fully qualified**. For example:
  /// - if your application namespace is "app_1.my_apps"
  /// - and the collection name is "tasks"
  /// - then the fully qualified namespace is `"tasks.app_1.my_apps"`.
  ///
  /// The application namespace configured on [AtClientPreference] is
  /// **NOT** appended automatically — the caller must pass the complete
  /// namespace. Throws [ArgumentError] if [namespace] contains no dot.
  ///
  /// [defaultExpiration] is the ttl (time-to-live) for items in an
  /// AtCollection. In `draft()` and `create()`, if you do not set an
  /// `expiresAt`, the default ttl will be `now + defaultExpiration`.
  /// Once the time elapses and the item expires, the atServer hard
  /// deletes it, just like how AtKey ttls function.
  ///
  /// If [fromJson] is supplied it is registered as the factory for items
  /// of type [T] under [typeTag] (the wire-format identifier), via
  /// [AtCollection.registerFactory]. [fromJson] and [typeTag] travel
  /// together — supplying one without the other throws [ArgumentError].
  /// For polymorphic collections, omit both here and call
  /// `AtCollection.registerFactory<ConcreteType>(fromJson, typeTag: ...)`
  /// per concrete type.
  ///
  /// [typeTag] is required (whenever [fromJson] is supplied) because
  /// deriving the tag from `T.toString()` is unsafe under Dart's
  /// minifier / tree-shaker — see [AtCollection.registerFactory] for
  /// the full rationale.
  ///
  /// [writeTypeTag] stamps items this collection creates with that tag when
  /// no factory is registered for their type, without registering a
  /// [fromJson]. When [typeTag] is also set, the two must match.
  ///
  /// The collection's type tag is kept in its collection record, the self
  /// key `__collection.<namespace>@<atSign>`, synced like the items, so every
  /// app, session and device of this atSign opens it with the same tag. Its
  /// value is JSON, `{"v": 1, "writeTypeTag": "Todo"}`; a reader ignores the
  /// fields it does not know. Each call reads the record:
  /// - a record holding a tag other than [writeTypeTag], or [typeTag] when
  ///   [writeTypeTag] is null, throws [CollectionTypeTagMismatchException];
  /// - otherwise the collection stamps the record's tag, even when this call
  ///   asked for none, and so does every collection this client already
  ///   handed out for [namespace];
  /// - with no record, [writeTypeTag] is written as the record, after asking
  ///   the atServer for one that has not synced here yet. A call without
  ///   [writeTypeTag] writes nothing, so a collection with no record opens
  ///   as before.
  ///
  /// A record that cannot be read as that JSON throws [FormatException].
  /// The id `__collection` is reserved for the record.
  ///
  /// When [cleanupOrphansOnCreation] is true, the returned collection runs
  /// a one-shot `cleanupOrphans()` sweep before the `Future` completes.
  /// Idempotent: the sweep runs at most once per collection instance
  /// regardless of how many times [collection] is invoked with the flag.
  /// Useful at app-startup to reclaim descendants whose parent was
  /// deleted on another atSign while this app was offline.
  ///
  /// [eventSource] selects which underlying source(s) feed the
  /// collection's update / delete event streams. Defaults to
  /// [EventSource.both]. See the [EventSource] enum dartdoc for the
  /// per-value semantics.
  ///
  /// - [EventSource.data] subscribes to [AtClient.dataEvents] only.
  ///   Sees ALL local keystore mutations — including locally-driven
  ///   writes (which never generate notifications) and TTL expiry
  ///   deletions. Recommended when a real `SyncService` is running.
  /// - [EventSource.notifs] subscribes to `NotificationService` only.
  ///   Locally-driven writes that don't generate notifications are
  ///   NOT visible on the watch streams.
  /// - [EventSource.both] subscribes to both and emits events from
  ///   each as they arrive — no de-duplication.
  ///
  /// Throws [StoppedException] after [stop].
  Future<AtCollection<T>> collection<T>(
    String namespace,
    Duration defaultExpiration, {
    EventSource eventSource = EventSource.both,
    T Function(Map<String, dynamic>)? fromJson,
    String? typeTag,
    String? writeTypeTag,
    bool cleanupOrphansOnCreation = false,
  });
}
