import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/service/change.dart';
import 'package:at_client/src/service/change_impl.dart';
import 'package:at_client/src/service/change_service.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_commons/src/keystore/at_key.dart';

class ChangeServiceImpl implements ChangeService {
  final AtClient _atClient;

  ChangeServiceImpl(this._atClient);

  @override
  Future<Change> delete(key) {
    // TODO: implement delete
    throw UnimplementedError();
  }

  @override
  Future<AtClient> getClient() {
    // TODO: implement getClient
    throw UnimplementedError();
  }

  @override
  bool isInSync() {
    // TODO: implement isInSync
    throw UnimplementedError();
  }

  @override
  Future<Change> put(AtKey key, value) async {
    var changeImpl = ChangeImpl(_atClient);
    // The changeStatus defaults to failure.
    changeImpl.statusEnum = StatusEnum.failure;
    var isSuccess;
    try {
      isSuccess = await _atClient.put(key, value);
    } on AtClientException {
      rethrow;
    }
    // If put the result is successful, build the change object.
    if (isSuccess) {
      changeImpl.statusEnum = StatusEnum.success;
      changeImpl.atKey = key;
      changeImpl.operationEnum = OperationEnum.update;
      changeImpl.atValue = AtValue();
      changeImpl.atValue?.value = value;
      changeImpl.atValue?.metadata = key.metadata;
    }
    return changeImpl;
  }

  @override
  Future<Change> putMeta(AtKey key) {
    // TODO: implement putMeta
    throw UnimplementedError();
  }

  @override
  Future<void> sync({Function? onDone}) {
    // TODO: implement sync
    throw UnimplementedError();
  }
}
