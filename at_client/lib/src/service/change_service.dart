import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';

import 'change.dart';

abstract class ChangeService {
  /// Updates value of [AtKey.key] is if it is already present. Otherwise creates a new key.
  /// Set [AtKey.sharedWith] if the key has to be shared with another atSign.
  /// Set [AtKey.metadata.isBinary] if you are updating binary value e.g image,file.
  /// By default namespace that is used to create the [AtClient] instance will be appended to the key. phone@alice will be saved as
  /// phone.persona@alice where 'persona' is the namespace. If you want to save by ignoring the namespace set [AtKey.metadata.namespaceAware]
  /// to false.
  /// Additional metadata can be set using [AtKey.metadata]
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
  /// Throws [AtClientException] when binary data size exceeds the [AtClientPreference.maxDataSize].
  /// Throws [AtClientException] when keys to encrypt the data are not found.
  Future<Change> put(AtKey key, dynamic value);
  Future<Change> putMeta(AtKey key);
  Future<Change> delete(key);
  Future<void> sync({Function? onDone});
  bool isInSync();
  Future<AtClient> getClient();
}
