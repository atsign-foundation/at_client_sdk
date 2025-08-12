import 'package:at_contacts_group_flutter/services/group_service.dart';

/// [initializeGroupService] has to be called before using groups package
void initializeGroupService({rootDomain = 'root.atsign.wtf', rootPort = 64}) {
  GroupService().resetData();
  GroupService().init(rootDomain, rootPort);
}
