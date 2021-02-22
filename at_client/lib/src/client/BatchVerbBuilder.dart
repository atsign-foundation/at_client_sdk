import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_commons/src/keystore/at_key.dart';
import 'package:at_utils/at_utils.dart';

class BatchVerbBuilder {
  List<BatchRequest> _batchRequests = [];
  var _batchId;
  var currentAtSign;
  EncryptionService encryptionService;

  BatchVerbBuilder(double batchId) {
    currentAtSign = AtUtils.formatAtSign(currentAtSign);
    this._batchId = batchId;
  }

  @override
  Future<void> delete(AtKey atKey) async {
    var isPublic = atKey.metadata != null ? atKey.metadata.isPublic : false;
    var isNamespaceAware =
        atKey.metadata != null ? atKey.metadata.namespaceAware : true;
    AtClientImpl atClient = await AtClientImpl.getClient(currentAtSign);
    var namespace = atClient.preference.namespace;
    var keyWithNamespace;
    if (isNamespaceAware) {
      keyWithNamespace = _getKeyWithNamespace(atKey.key, namespace);
    } else {
      keyWithNamespace = atKey.key;
    }
    var builder = DeleteVerbBuilder()
      ..isPublic = isPublic
      ..sharedWith = atKey.sharedWith
      ..atKey = keyWithNamespace
      ..sharedBy = currentAtSign;
    _addToList(builder);
  }

  String _getKeyWithNamespace(String key, String namespace) {
    var keyWithNamespace = key;
    if (namespace != null && namespace.isNotEmpty) {
      keyWithNamespace += '.${namespace}';
    }
    return keyWithNamespace;
  }

  void get(AtKey atKey) async {
    var builder;
    var keyWithNamespace;
    var isPublic = atKey.metadata != null ? atKey.metadata.isPublic : false;
    var namespaceAware =
        atKey.metadata != null ? atKey.metadata.namespaceAware : true;
    var isCached = atKey.metadata != null ? atKey.metadata.isCached : false;
    AtClientImpl atClient = await AtClientImpl.getClient(currentAtSign);
    var namespace = atClient.preference.namespace;
    var key = atKey.key;
    var sharedBy = atKey.sharedBy;
    var sharedWith = atKey.sharedWith;
    if (namespaceAware) {
      keyWithNamespace = _getKeyWithNamespace(key, namespace);
    } else {
      keyWithNamespace = key;
    }
    if (sharedBy != null && isCached) {
      builder = LLookupVerbBuilder()
        ..atKey = keyWithNamespace
        ..sharedBy = sharedBy
        ..isCached = isCached
        ..sharedWith = currentAtSign
        ..operation = UPDATE_ALL;
    } else if (sharedBy != null && sharedBy != currentAtSign) {
      if (isPublic) {
        builder = PLookupVerbBuilder()
          ..atKey = keyWithNamespace
          ..sharedBy = sharedBy
          ..operation = UPDATE_ALL;
      } else {
        builder = LookupVerbBuilder()
          ..atKey = keyWithNamespace
          ..sharedBy = sharedBy
          ..auth = true
          ..operation = UPDATE_ALL;
      }
      // plookup and lookup can be executed only on remote
    } else if (sharedWith != null) {
      sharedWith = AtUtils.formatAtSign(sharedWith);
      builder = LLookupVerbBuilder()
        ..isCached = isCached
        ..isPublic = isPublic
        ..sharedWith = sharedWith
        ..atKey = keyWithNamespace
        ..sharedBy = currentAtSign
        ..operation = UPDATE_ALL;
    } else if (isPublic) {
      builder = LLookupVerbBuilder()
        ..atKey = 'public:' + keyWithNamespace
        ..sharedBy = currentAtSign;
    } else {
      builder = LLookupVerbBuilder()..atKey = keyWithNamespace;
      if (keyWithNamespace.startsWith(AT_PKAM_PRIVATE_KEY) ||
          keyWithNamespace.startsWith(AT_PKAM_PUBLIC_KEY)) {
        builder.sharedBy = null;
      } else {
        builder.sharedBy = currentAtSign;
      }
    }
    _addToList(builder);
  }

  void put(AtKey atKey, dynamic value,
      {String sharedWith, Metadata metadata}) async {
    AtClientImpl atClient = await AtClientImpl.getClient(currentAtSign);
    var builder = await atClient.prepareUpdateBuilder(atKey.key, value,
        sharedWith: atKey.sharedWith, metadata: atKey.metadata);
    _addToList(builder);
  }

  void _addToList(VerbBuilder builder) {
    var command = builder.buildCommand();
    var batchRequest = BatchRequest(_batchId, command);
    _batchRequests.add(batchRequest);
    _batchId++;
  }

  dynamic batch() {
    return this._batchRequests;
  }
}
