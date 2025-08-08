import 'package:at_commons/at_commons.dart';

class UpdateParams {
  String? atKey;
  dynamic value;
  String? sharedBy;
  String? sharedWith;
  Metadata? metadata;

  Map toJson() {
    var map = {};
    map['atKey'] = atKey;
    map['value'] = value;
    map['metadata'] = metadata;
    return map;
  }

  static UpdateParams fromJson(Map dataMap) {
    var updateParams = UpdateParams();
    updateParams.atKey = dataMap[AtConstants.atKey];
    updateParams.value = dataMap[AtConstants.atValue];
    updateParams.sharedBy = dataMap['sharedBy'];
    updateParams.sharedWith = dataMap['sharedWith'];
    updateParams.metadata = Metadata.fromJson(dataMap['metadata']);
    return updateParams;
  }
}
