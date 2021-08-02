import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_commons/at_commons.dart';

import 'change.dart';

abstract class ChangeService {
  /// Updates value of [AtKey.key] is if it is already present. Otherwise creates a new key.
  /// The put method updates the [AtKey] only to the local storage.
  /// To sync [AtKey] to cloud remote secondary call [Change.sync] method.
  /// Set [AtKey.sharedWith] if the key has to be shared with another atSign.
  /// Set [AtKey.metadata.isBinary] if you are updating binary value e.g image,file.
  /// By default namespace that is used to create the [AtClient] instance will be appended to the key. phone@alice will be saved as
  /// phone.persona@alice where 'persona' is the namespace. If you want to save by ignoring the namespace set [AtKey.metadata.namespaceAware]
  /// to false.
  /// Optionally metadata can be set using [AtKey.metadata]
  ///
  /// @returns
  ///  Returns a [Change] object.
  ///
  /// @ throws
  /// Throws [KeyNotFoundException] when keys to encrypt the data are not found.
  /// Throws [AtKeyException] for invalid key formed.
  /// ```
  /// @usage
  /// CurrentAtSign = @alice
  ///
  /// 1. Update a private key and value.
  ///   var key = AtKey()..key='phone'
  ///   var changeServiceImpl = ChangeServiceImpl(_atClient);
  ///   changeServiceImpl.put(key,'+1 999 9999');
  ///
  /// 2. Update a public key and value.
  ///   var metaData = Metadata()..isPublic=true;
  ///   var key = AtKey()..key='phone'
  ///             ..metadata=metaData
  ///   var changeServiceImpl = ChangeServiceImpl(_atClient);
  ///   changeServiceImpl.put(key,'+1 999 9999');
  ///
  /// 3. Update a key for @bob atSign.
  ///    var key = AtKey()..key='phone'
  ///                     ..sharedWith='@bob';
  ///    var changeServiceImpl = ChangeServiceImpl(_atClient);
  ///    changeServiceImpl.put(key,'+1 999 9999');
  ///
  /// 4. Setting namespace to false.
  ///    var metaData = Metadata()..namespaceAware=false
  ///    var key = AtKey()..key='phone'
  ///                    ..sharedWith='@alice'
  ///                    ..metadata = metaData;
  ///    var changeServiceImpl = ChangeServiceImpl(_atClient);
  ///    changeServiceImpl.put(key, '+1 999 9999');
  ///
  /// 5. Setting metadata to key - TTL and TTB
  ///    var metaData = Metadata()..ttl = 60000
  ///                            ..ttb = 60000;
  ///    var key = AtKey()..key = 'phone'
  ///                    ..sharedWith = '@bob'
  ///                    ..metadata = metaData;
  ///    var changeServiceImpl = ChangeServiceImpl(_atClient);
  ///    changeServiceImpl.put(key, '+1 999 9999')
  ///
  /// 6. Enable another atSign(here @bob) to cache a key and value
  ///    var metaData = Metadata()..ttr = -1
  ///
  ///    var key = AtKey()..key = 'phone'
  ///                    ..sharedWith = '@bob'
  ///                    ..metadata = metaData;
  ///    var changeServiceImpl = ChangeServiceImpl(_atClient);
  ///    changeServiceImpl.put(key, '+1 999 9999')
  /// ```
  Future<Change> put(AtKey key, dynamic value);

  Future<Change> putMeta(AtKey key);

  Future<Change> delete(key);

  /// Keeps the local storage and cloud secondary storage in sync.
  /// Pushes uncommitted local changes to remote secondary storage and vice versa.
  /// Refer [SyncService.sync] for usage details, callback usage and exceptions thrown
  Future<void> sync({Function? onDone, Function? onError, String? regex});

  /// Checks whether commit id on local storage and on cloud secondary server are the same.
  /// If the commit ids are equal then returns true. otherwise returns false.
  Future<bool> isInSync();

  AtClient getClient();
}
