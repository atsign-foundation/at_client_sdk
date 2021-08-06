import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/service/change.dart';
import 'package:at_client/src/service/change_impl.dart';
import 'package:at_client/src/service/change_service.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_commons/src/keystore/at_key.dart';
import 'package:at_utils/at_utils.dart';
import 'package:pedantic/pedantic.dart';

class ChangeServiceImpl implements ChangeService {
  final AtClient _atClient;

  ChangeServiceImpl(this._atClient) {
    // Setting the syncStrategy to 'ONDEMAND' to write only to local secondary.
    _atClient.setPreferences(
        AtClientPreference()..syncStrategy = SyncStrategy.ONDEMAND);
  }

  @override
  Future<Change> delete(AtKey atKey) async {
    await _atClient.delete(atKey);
    // If delete is successful, return a change object.
    return ChangeImpl.from(_atClient, atKey, OperationEnum.delete);
  }

  @override
  AtClient getClient() {
    return _atClient;
  }

  @override
  Future<bool> isInSync() async {
    return await _atClient.getSyncService()!.isInSync();
  }

  @override
  Future<Change> put(AtKey atKey, value) async {
    // Validates the atKey's
    await _validateAtKey(atKey);
    await _atClient.put(atKey, value);
    // If put is successful, return change object.
    return ChangeImpl.from(_atClient, atKey, OperationEnum.update,
        value: value);
  }

  @override
  Future<Change> putMeta(AtKey atKey) async {
    // validates the atKey
    await _validateAtKey(atKey);
    await _atClient.putMeta(atKey);
    // If put is successful, return change object.
    return ChangeImpl.from(_atClient, atKey, OperationEnum.update);
  }

  @override
  Future<void> sync(
      {Function? onDone, Function? onError, String? regex}) async {
    // Murali - is _atClient
    //          .getSyncService() required or should we call ChangeService.sync() ?
    if (onDone != null && onError != null) {
      unawaited(_atClient
          .getSyncService()!
          .sync(onDone: onDone, onError: onError, regex: regex));
    } else {
      await _atClient.getSyncService()!.sync(regex: regex);
    }
  }

  /// Validates the atKey
  Future<void> _validateAtKey(AtKey atKey) async {
    // 1. Verify if the key is well formed.
    _validateKey(atKey.key!);
    // 2. Verify if the key belong to the proper namespace.
    _validateNamespace(atKey.namespace);
    // 3. Verify if the put is allowed. cached key's cannot be updated.
    if ((atKey.metadata != null && atKey.metadata!.isCached) ||
        atKey.key!.startsWith('cached:')) {
      throw PermissionDeniedException('Cannot update a cached key.');
    }
    //4. Verify if metadata is valid.
    _validateMetadata(atKey.metadata);
    // 5. Check if the sharedWith @Sign is a valid @Sign.
    if (atKey.sharedWith != null) {
      atKey.sharedWith = AtUtils.fixAtSign(atKey.sharedWith!);
      // 5.1 verify only if network is available. validate if the sharedWith @sign exists.
      if (await NetworkUtil.isNetworkAvailable()) {
        _validateAtSign(atKey.sharedWith!);
      }
    }
  }

  /// Validates the key
  /// Throws [AtKeyException] if key is invalid.
  void _validateKey(String key) {
    if (key.isEmpty) {
      throw AtKeyException('Key cannot be empty');
    }
    // Key cannot contain @
    if (key.contains('@')) {
      throw AtKeyException('Key cannot contain @');
    }
    // Key cannot contain whitespaces
    if (key.contains(' ')) {
      throw AtKeyException('Key cannot contain whitespaces');
    }
  }

  // TODO _validateNamespace is a place holder, should be implemented.
  bool _validateNamespace(String? namespace) {
    return true;
  }

  /// Validates the metadata of the key.
  /// Throws [AtKeyException] if metadata has invalid values.
  void _validateMetadata(Metadata? metadata) {
    if (metadata == null) {
      return;
    }
    // validate TTL
    if (metadata.ttl != null && metadata.ttl! < 0) {
      throw AtKeyException(
          'Invalid TTL value: ${metadata.ttl}. TTL value cannot be less than 0');
    }

    // validate TTB
    if (metadata.ttb != null && metadata.ttb! < 0) {
      throw AtKeyException(
          'Invalid TTB value: ${metadata.ttb}. TTB value cannot be less than 0');
    }

    //validate TTR
    if (metadata.ttr != null && metadata.ttr! < -1) {
      throw AtKeyException(
          'Invalid TTR value: ${metadata.ttr}. valid values for TTR are -1 and greater than or equal to 1');
    }
  }

  /// Verify if the atSign exists.
  /// Throws [InvalidAtSignException] if atSign does not exist.
  void _validateAtSign(String atSign) async {
    if (atSign.isEmpty) {
      throw AtKeyException('@sign cannot be empty');
    }
    try {
      await AtClientUtil.findSecondary(
          atSign,
          _atClient.getAtClientPreferences().rootDomain,
          _atClient.getAtClientPreferences().rootPort);
    } on SecondaryNotFoundException {
      throw AtKeyException('$atSign does not exist');
    }
  }
}
