import 'package:flutter/material.dart';
import 'package:at_invitation_flutter/services/invitation_service.dart';

/// Initialize the invitation service
void initializeInvitationService(
    {@required GlobalKey<NavigatorState>? navkey,
    @required String? webPage,
    rootDomain = 'root.atsign.wtf',
    rootPort = 64}) {
  InvitationService()
      .initInvitationService(navkey, webPage, rootDomain, rootPort);
}

/// call shareAndInvite method from the invitaion service
void shareAndInvite(BuildContext context, String jsonData) {
  InvitationService().shareAndinvite(context, jsonData);
}

/// call fetchInviteData method from the invitaion service
fetchInviteData(BuildContext context, String data, String atsign) {
  InvitationService().fetchInviteData(context, data, atsign);
}
