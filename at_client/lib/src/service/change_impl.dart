import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/change.dart';
import 'package:at_commons/src/keystore/at_key.dart';
import 'package:at_commons/src/verb/operation_enum.dart';

class ChangeImpl implements Change {
  final AtClient _atClient;
  StatusEnum? statusEnum;
  AtKey? atKey;
  OperationEnum? operationEnum;
  AtValue? atValue;

  ChangeImpl(this._atClient);

  @override
  AtKey getKey() {
    // TODO: implement getKey
    throw UnimplementedError();
  }

  @override
  OperationEnum getOperation() {
    // TODO: implement getOperation
    throw UnimplementedError();
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
  bool isInSync() {
    // TODO: implement isInSync
    throw UnimplementedError();
  }

  @override
  void notify({Function? onSuccess, Function? onError}) {
    // TODO: implement notify
  }

  @override
  void sync({Function? onDone}) {
    // TODO: implement sync
  }
}

enum StatusEnum { success, failure }
