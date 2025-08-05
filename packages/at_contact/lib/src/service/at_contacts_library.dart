import 'package:at_contact/src/model/at_contact.dart';
import 'package:at_contact/src/model/at_group.dart';

abstract class AtContactsLibrary {
  // Create a new contact in secondary
  Future<bool> add(AtContact contact);

// Updates contact
  Future<bool> update(AtContact contact);

  // delete contact
  Future<bool> deleteContact(AtContact contact);

  // delete contact by atSign
  Future<bool> delete(String atSign);

  //fetch all contacts
  Future<List<AtContact>> listContacts();

  //get contact by atSign
  Future<AtContact?> get(String atSign);

  // fetch all active contacts
  Future<List<AtContact>> listActiveContacts();

  // fetch all blocked contacts
  Future<List<AtContact>> listBlockedContacts();

  // fetch favorite contacts
  Future<List<AtContact>> listFavoriteContacts();

  // creates Group
  Future<AtGroup?> createGroup(AtGroup atGroup);

  // creates Group
  Future<AtGroup?> updateGroup(AtGroup atGroup);

  // deletes Group
  Future<bool> deleteGroup(AtGroup atGroup);

  // fetches all the group names
  Future<List<String?>> listGroupNames();

  // fetches all the group Ids
  Future<List<String?>> listGroupIds();

  // fetches group from groupName
  Future<AtGroup?> getGroup(String groupName);

  Future<bool> addMembers(Set<AtContact> atContacts, AtGroup atGroup);

  Future<bool> deleteMembers(Set<AtContact> atContacts, AtGroup atGroup);

  bool isMember(AtContact atContact, AtGroup atGroup);
}
