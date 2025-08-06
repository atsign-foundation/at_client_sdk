// TODO: Put public facing types in this file.

import 'package:at_server_status/src/model/at_status.dart';

abstract class AtServerStatus {
  Future<AtStatus> get(String atSign);
  Future<int> httpStatus(String atSign);
}
