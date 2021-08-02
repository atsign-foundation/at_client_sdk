import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';

import 'change.dart';

abstract class ChangeService {
  /// * Updates value of [AtKey.key] is if it is already present. Otherwise creates a new key.
  /// * The put method updates the [AtKey] only to the local storage.
  /// * To sync [AtKey] to cloud remote secondary call [Change.sync] method.
  /// * Set [AtKey.sharedWith] if the key has to be shared with another atSign.
  /// * Set [AtKey.metadata.isBinary] if you are updating binary value e.g image,file.
  /// * By default namespace that is used to create the [AtClient] instance will be appended to the key. phone@alice will be saved as
  /// phone.persona@alice where 'persona' is the namespace. If you want to save by ignoring the namespace set [AtKey.metadata.namespaceAware]
  /// to false.
  /// * Optionally metadata can be set using [AtKey.metadata]
  ///
  /// @returns
  /// * Returns a [Change] object.
  ///
  /// @throws
  /// Throws [KeyNotFoundException] when keys to encrypt the data are not found.
  /// Throws [AtKeyException] for invalid key formed.
  ///     Following key's are not allowed:
  ///     * A key cannot have a white spaces
  ///     * A key cannot have @
  /// Throws [AtKeyException] when an invalid atSign is used.
  ///     Following atSign's are invalid:
  ///     * An atSign cannot have whitespaces
  ///     * An atSign cannot have more than one @
  ///     * An atSign cannot have following characters - [, !, *, ',`, (, ),;,:,&,=,+,$,,/,\,?,#,[,,],{,},],
  ///     * An atSign cannot have ASCII control characters and UNICODE Control character.
  /// Throws [AtClientException] if value of the key exceeds [AtClientPreference.maxDataSize]
  /// @usage
  /// ```dart
  /// var CurrentAtSign = @alice
  /// ```
  /// 1. Update a private key and value.
  /// ```dart
  ///   var key = AtKey()..key='phone'
  ///   var changeServiceImpl = ChangeServiceImpl(_atClient);
  ///   changeServiceImpl.put(key,'+1 999 9999');
  ///```
  /// 2. Update a public key and value.
  /// ```dart
  ///   var metaData = Metadata()..isPublic=true;
  ///   var key = AtKey()..key='phone'
  ///             ..metadata=metaData
  ///   var changeServiceImpl = ChangeServiceImpl(_atClient);
  ///   changeServiceImpl.put(key,'+1 999 9999');
  ///```
  /// 3. Update a key for @bob atSign.
  ///```dart
  ///    var key = AtKey()..key='phone'
  ///                     ..sharedWith='@bob';
  ///    var changeServiceImpl = ChangeServiceImpl(_atClient);
  ///    changeServiceImpl.put(key,'+1 999 9999');
  ///```
  /// 4. Setting namespace to false.
  ///```dart
  ///    var metaData = Metadata()..namespaceAware=false
  ///    var key = AtKey()..key='phone'
  ///                    ..sharedWith='@alice'
  ///                    ..metadata = metaData;
  ///    var changeServiceImpl = ChangeServiceImpl(_atClient);
  ///    changeServiceImpl.put(key, '+1 999 9999');
  ///```
  /// 5. Setting metadata to key - TTL and TTB
  ///```dart
  ///    var metaData = Metadata()..ttl = 60000
  ///                            ..ttb = 60000;
  ///    var key = AtKey()..key = 'phone'
  ///                    ..sharedWith = '@bob'
  ///                    ..metadata = metaData;
  ///    var changeServiceImpl = ChangeServiceImpl(_atClient);
  ///    changeServiceImpl.put(key, '+1 999 9999');
  ///```
  /// 6. Enable another atSign(here @bob) to cache a key and value
  ///```dart
  ///    var metaData = Metadata()..ttr = -1
  ///    var key = AtKey()..key = 'phone'
  ///                    ..sharedWith = '@bob'
  ///                    ..metadata = metaData;
  ///    var changeServiceImpl = ChangeServiceImpl(_atClient);
  ///    changeServiceImpl.put(key, '+1 999 9999');
  /// ```
  /// 7. To upload a binary data e.g. images, text files, documents etc.
  /// ```dart
  ///     var metaData = Metadata()..isBinary = true;
  ///     var key = AtKey()..key = 'photo'
  ///                      ..sharedWith = '@bob'
  ///                      ..metadata = metaData;
  ///     var value = <path-to-image-file>
  ///    var changeServiceImpl = ChangeServiceImpl(_atClient);
  ///    changeServiceImpl.put(key, value);
  /// ```
  Future<Change> put(AtKey key, dynamic value);

  /// Updates the metadata of the [AtKey] if key is already present. Else creates a new key
  /// with metadata and value as null.
  /// * The put method updates the [AtKey] only to the local storage.
  /// * To sync [AtKey] to cloud remote secondary call [Change.sync] method.
  /// @returns
  /// Returns a [Change] object.
  ///
  /// @throws
  /// Throws [AtKeyException] for invalid key formed.
  ///     Following are not allowed in the key
  ///     * A key cannot have a white spaces
  ///     * A key cannot have @
  /// Throws [AtKeyException] when an invalid atSign is used.
  ///     Following atSign's are invalid:
  ///     * An atSign cannot have whitespaces
  ///     * An atSign cannot have more than one @
  ///     * An atSign cannot have following characters - [, !, *, ',`, (, ),;,:,&,=,+,$,,/,\,?,#,[,,],{,},],
  ///     * An atSign cannot have ASCII control characters and UNICODE Control character.
  /// @usage
  /// ```dart
  /// var currentAtSign = '@alice'
  /// ```
  /// 1. Update TTL and TTB of a key.
  ///     TTL (Time to Live): When set the value of the key expires after the specified duration. Once the key is expired null is returned.
  ///     TTB (Time to birth): When set the value of key is returned after the specified duration. Before the duration, null is returned.
  /// ```dart
  ///     var metaData = Metadata()..ttl = 600000
  ///                              ..ttb = 60000;
  ///     var atKey = AtKey()..key = 'phone'
  ///                        ..sharedWith = '@bob';
  ///     var changeServiceImpl = ChangeServiceImpl(_atClient);
  ///     changeServiceImpl.putMeta(atKey);
  /// ```
  /// 2. Enable caching of key
  ///     TTR (Time to refresh): Determines the frequency at which the cached key should be refreshed.
  ///                            When set to -1, the cached key does not get refreshed.
  ///     CCD (Cascade delete): Represents if the cached key should be deleted when owner of the key deletes the orginal key.
  ///          When set to true, the cached key is delete when original key is deleted by the owner of the key.
  ///          When set to false, the cached key is remain when orginal key is deleted by the owner of the key.
  ///```dart
  ///     var metaData = Metadata()..ttr = 60000
  ///                              ..ccd = true;
  ///     var atKey = AtKey()..key = 'phone'
  ///                        ..sharedWith = '@bob';
  ///     var changeServiceImpl = ChangeServiceImpl(_atClient);
  ///     changeServiceImpl.putMeta(atKey);
  ///```
  Future<Change> putMeta(AtKey key);

  /// Deletes the [AtKey] from the local storage.
  /// * To remove the [AtKey] from the cloud remote secondary, call [Change.sync] method.
  /// @returns
  /// Returns a [Change] object.
  ///
  /// @throws
  /// Throws [DataStoreException] is local storage is not initialized.
  ///
  /// @usage
  ///
  /// 1. Delete a private key.
  /// ```dart
  ///     var atKey = AtKey()..key = 'phone';
  ///     var changeServiceImpl = ChangeServiceImpl(_atClient);
  ///     changeServiceImpl.delete(atKey);
  /// ```
  /// 2. Delete a key shared to another atSign user.
  /// ```dart
  ///    var atKey = AtKey()..key = 'phone'
  ///                       ..sharedWith = '@bob';
  ///    var changeServiceImpl = ChangeServiceImpl(_atClient);
  ///    changeServiceImpl.delete(atKey);
  /// ```
  /// 3. Delete a cached key.
  ///    Here currentAtSign is @bob
  ///```dart
  ///     var metaData = Metadata()..isCached = true
  ///     var atKey = AtKey()..key = 'phone'
  ///                        ..sharedWith = '@alice'
  ///    var changeServiceImpl = ChangeServiceImpl(_atClient);
  ///    changeServiceImpl.delete(atKey);
  ///```
  Future<Change> delete(AtKey key);

  /// Keeps the local storage and cloud secondary storage in sync.
  /// Pushes uncommitted local changes to remote secondary storage and vice versa.
  /// Refer [SyncService.sync] for usage details, callback usage and exceptions thrown
  Future<void> sync({Function? onDone, Function? onError, String? regex});

  /// Checks whether commit id on local storage and on cloud secondary server are the same.
  /// If the commit ids are equal then returns true. otherwise returns false.
  Future<bool> isInSync();

  AtClient getClient();
}
