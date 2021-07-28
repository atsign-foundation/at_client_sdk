import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/service/change.dart';
import 'package:at_client/src/service/change_service.dart';
import 'package:at_commons/src/keystore/at_key.dart';

class ChangeServiceImpl implements ChangeService {
  AtClient _atClient;

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
  Future<Change> put(AtKey key, value) {
    // TODO: implement put
    throw UnimplementedError();
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
