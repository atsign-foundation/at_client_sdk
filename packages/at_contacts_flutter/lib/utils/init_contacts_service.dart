import 'dart:async';

import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/services/contact_service.dart';

/// Function to initialise contacts Service
Future<void> initializeContactsService(
    {rootDomain = 'root.atsign.org',
    rootPort = 64,
    bool fetchContacts = true}) async {
  await ContactService()
      .initContactsService(rootDomain, rootPort, fetchContacts: fetchContacts);
}

/// Function call from app to dispose stream controllers used in the package
void disposeContactsControllers() {
  ContactService().disposeControllers();
}

/// Function to fetch the contact details of an atsign
Future<AtContact> getAtSignDetails(String atSign) async {
  // ignore: omit_local_variable_types
  AtContact? atContact = getCachedContactDetail(atSign);
  if (atContact == null) {
    var contactDetails = await ContactService().getContactDetails(atSign, null);
    atContact = AtContact(
      atSign: atSign,
      tags: contactDetails,
    );
    // ignore: unnecessary_null_comparison
    if (contactDetails != null) {
      ContactService().cachedContactList.add(atContact);
    }
  }
  return atContact;
}

// this function is used to get contact from cached array only
AtContact checkForCachedContactDetail(String atSign) {
  // ignore: omit_local_variable_types
  AtContact? atContact = getCachedContactDetail(atSign);
  return atContact ?? AtContact(atSign: atSign);
}

/// Function to fetch the contact details of an atsign from cached list
AtContact? getCachedContactDetail(String atsign) {
  if (atsign == ContactService().atContactImpl.atClient?.getCurrentAtSign() &&
      ContactService().loggedInUserDetails != null) {
    return ContactService().loggedInUserDetails;
  }
  if (ContactService().cachedContactList.isNotEmpty) {
    var index = ContactService()
        .cachedContactList
        .indexWhere((element) => element.atSign == atsign);
    if (index > -1) return ContactService().cachedContactList[index];
  }
  return null;
}

/// Adds [atsign] in contact list.
/// If [nickName] is not null , it wll be set as nick name of the [atsign].
Future<bool> addContact(String atsign, {String? nickName}) async {
  return await ContactService().addAtSign(atSign: atsign, nickName: nickName);
}

/// deletes the given [atsign]
Future<bool> deleteContact(String atsign) async {
  return await ContactService().deleteAtSign(atSign: atsign);
}

/// blocks/unblocks [atContact] based on boolean [blockAction]
/// if [blockAction] is [true] , [atContact] will be blocked.
Future<bool> blockOrUnblockAtContact(
    AtContact atContact, bool blockAction) async {
  return await ContactService()
      .blockUnblockContact(contact: atContact, blockAction: blockAction);
}

/// marks [atContact] as favourite.
Future<bool> markFavContact(AtContact atContact) async {
  return await ContactService().markFavContact(atContact);
}

/// gives list of [AtContact]
Future<List<AtContact>?> fetchContactList() async {
  return await ContactService().fetchContacts();
}
