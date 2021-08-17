import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/change.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_commons/src/keystore/at_key.dart';
import 'package:at_commons/src/verb/operation_enum.dart';
import 'package:pedantic/pedantic.dart';

class ChangeImpl implements Change {
  final AtClient _atClient;
  late AtKey atKey;
  late OperationEnum operationEnum;
  AtValue? atValue;

  ChangeImpl(this._atClient);

  @override
  AtKey getKey() {
    return atKey;
  }

  @override
  OperationEnum getOperation() {
    return operationEnum;
  }

  @override
  String getStatus() {
    // TODO: implement getStatus
    throw UnimplementedError();
  }

  @override
  AtValue getValue() {
    // TODO: implement getValue
    throw UnimplementedError();
  }

  @override
  Future<bool> isInSync() async {
//    return await _atClient.getSyncService()!.isInSync();
  return true;
  }

  @override
  void notify({Function? onSuccess, Function? onError}) {
    _atClient.notify(getKey(), getValue().toString(), getOperation());
  }

  @override
  Future<void> sync(
      {Function? onDone, Function? onError, String? regex}) async {
    if (onDone != null && onError != null) {
//      unawaited(_atClient
//          .getSyncService()!
//          .sync(onDone: onDone, onError: onError, regex: regex));
    } else {
//      await _atClient.getSyncService()!.sync(regex: regex);
    }
  }

  /// Returns a [Change] object
  static Change from(
      AtClient atClient, AtKey atKey, OperationEnum operationEnum,
      {String? value}) {
    var changeImpl = ChangeImpl(atClient)
      ..atKey = atKey
      ..operationEnum = OperationEnum.update;
    // If value is not null, set value.
    if (value != null) {
      changeImpl.atValue = AtValue();
      changeImpl.atValue!.value = value;
      changeImpl.atValue!.metadata = atKey.metadata;
    }
    return changeImpl;
  }
}