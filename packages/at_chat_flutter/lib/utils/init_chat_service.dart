// ignore: import_of_legacy_library_into_null_safe
import 'package:at_chat_flutter/services/chat_service.dart';
import 'package:at_client_mobile/at_client_mobile.dart';

/// function exposed to calling app to set certain parameters
void initializeChatService(
    AtClientManager atClientManager, String currentAtSign,
    {rootDomain = 'root.atsign.wtf', rootPort = 64}) {
  ChatService()
      .initChatService(atClientManager, currentAtSign, rootDomain, rootPort);
}

void setChatWithAtSign(String? atsign,
    {bool isGroup = false, String? groupId, List<String>? groupMembers}) {
  ChatService().setAtsignToChatWith(atsign, isGroup, groupId, groupMembers);
}

void disposeContactsControllers() {
  ChatService().disposeControllers();
}

/// function to delete all messages from the calling app.
Future<bool> deleteMessages() async {
  return await ChatService().deleteMessages();
}
