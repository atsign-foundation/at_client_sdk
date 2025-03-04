import 'dart:async';
import 'dart:developer';

// ignore: import_of_legacy_library_into_null_safe
import 'package:at_client_mobile/at_client_mobile.dart';
// ignore: import_of_legacy_library_into_null_safe
// ignore_for_file: use_build_context_synchronously

import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/services/contact_service.dart';
import 'package:at_contacts_flutter/utils/exposed_service.dart';
import 'package:at_contacts_group_flutter/models/group_contacts_model.dart';
import 'package:at_contacts_group_flutter/utils/text_constants.dart';
import 'package:at_contacts_group_flutter/widgets/custom_toast.dart';
import 'package:at_contacts_group_flutter/widgets/yes_no_dialog.dart';
import 'package:at_utils/at_logger.dart';
import 'package:flutter/material.dart';

/// Service to handle CRUD operations on groups
class GroupService {
  /// Singleton instance of the service
  GroupService._();
  static final GroupService _instance = GroupService._();
  factory GroupService() => _instance;

  /// current atsign
  late String _atsign;

  /// selected contact list for the group
  List<AtContact?> selecteContactList = [];

  /// List of all the contacts for the atsign
  List<GroupContactsModel?> allContacts = [],

      /// List of contacts of the selected group
      selectedGroupContacts = [];

  /// Details of the selected group
  AtGroup? selectedGroup;

  /// Instance of AtClientManager
  late AtClientManager atClientManager;

  /// Instance of AtContactsImpl
  late AtContactsImpl atContactImpl;

  /// Root domain to use
  String? rootDomain;

  /// Root port to use
  int? rootPort;
  int length = 0;

  /// Boolean flag to control loader
  bool? showLoader;

  /// Controller for group list stream
  final _atGroupStreamController = StreamController<List<AtGroup>>.broadcast();

  /// Group list stream
  Stream<List<AtGroup>> get atGroupStream => _atGroupStreamController.stream;

  /// Sink for group list stream
  StreamSink<List<AtGroup>> get atGroupSink => _atGroupStreamController.sink;

  /// Controller for group view stream
  final _groupViewStreamController = StreamController<AtGroup>.broadcast();

  /// Group view stream
  Stream<AtGroup> get groupViewStream => _groupViewStreamController.stream;

  /// Sink for group view stream
  StreamSink<AtGroup> get groupViewSink => _groupViewStreamController.sink;

  /// Controller for all contacts stream
  final StreamController<List<GroupContactsModel?>> _allContactsStreamController =
      StreamController<List<GroupContactsModel?>>.broadcast();

  /// all contacts stream
  Stream<List<GroupContactsModel?>> get allContactsStream => _allContactsStreamController.stream;

  /// Sink for all contacts stream
  StreamSink<List<GroupContactsModel?>> get allContactsSink => _allContactsStreamController.sink;

  /// Controller for selected group contact stream
  final _selectedContactsStreamController = StreamController<List<GroupContactsModel?>>.broadcast();

  /// Selected group contact stream
  Stream<List<GroupContactsModel?>> get selectedContactsStream => _selectedContactsStreamController.stream;

  /// Sink for selected group contact stream
  StreamSink<List<GroupContactsModel?>> get selectedContactsSink => _selectedContactsStreamController.sink;

  /// get list contact
  List<AtContact> listContact = [];

  // show loader stream
  final _showLoaderStreamController = StreamController<bool>.broadcast();
  Stream<bool> get showLoaderStream => _showLoaderStreamController.stream;
  StreamSink<bool> get showLoaderSink => _showLoaderStreamController.sink;

  String? get currentAtsign => _atsign;

  AtGroup? get currentSelectedGroup => selectedGroup;

  int? expandIndex = 0;

  AtSignLogger atSignLogger = AtSignLogger('GroupService');
  // ignore: always_declare_return_types
  setSelectedContacts(List<AtContact?>? list) {
    selecteContactList = list ?? [];
  }

  List<AtContact?>? get selectedContactList => selecteContactList;

  // keeps track of how group screens will be shown for desktop.
  GroupPreference groupPreferece = GroupPreference();

  /// initialise the service with details from app
  void init(String rootDomainFromApp, int rootPortFromApp) async {
    atClientManager = AtClientManager.getInstance();
    _atsign = atClientManager.atClient.getCurrentAtSign()!;
    rootDomain = rootDomainFromApp;
    rootPort = rootPortFromApp;
    allContacts = [];
    atContactImpl = await AtContactsImpl.getInstance(_atsign);
    await fetchGroupsAndContacts();
  }

  /// Will show a dialog box, if yes is pressed, will clear the selectedGroupContacts
  void clearSelectedGroupContacts({required BuildContext context, Function? onYesTap}) {
    if (selectedGroupContacts.isNotEmpty) {
      shownConfirmationDialog(context, 'Selected contacts will not be added , confirm?', () {
        selectedGroupContacts = [];
        selectedContactsSink.add(selectedGroupContacts); // to update the UI

        if (onYesTap != null) {
          onYesTap();
        }
      });
    } else {
      if (onYesTap != null) {
        onYesTap();
      }
    }
  }

  /// Function to create a group
  Future<dynamic> createGroup(AtGroup atGroup) async {
    atGroup = removeImageFromAtGroupMembers(atGroup);

    try {
      var group = await atContactImpl.createGroup(atGroup);
      if (group is AtGroup) {
        await updateGroupStreams(group, expandGroup: true);
        return group;
      }
    } catch (e) {
      atSignLogger.severe('error in creating group: $e');
      return;
    }
  }

  // ignore: always_declare_return_types
  getAllGroupsDetails({
    int? expandIndex,
    AtGroup? expandGroup,
    bool addToGroupSink = true,
  }) async {
    try {
      var groupIds = await atContactImpl.listGroupIds();
      // TODO: Delete log
      log(groupIds.join(',').toString());
      var groupList = <AtGroup>[];

      for (var i = 0; i < groupIds.length; i++) {
        try {
          var groupDetail = await (getGroupDetail(groupIds[i]!));
          // TODO : delete log
          log('Details: ${groupDetail?.displayName}');
          if (groupDetail != null) groupList.add(groupDetail);
        } catch (e) {
          log(e.toString());
        }
      }

      for (AtGroup group in groupList) {
        var index =
            allContacts.indexWhere((element) => element!.group != null && element.group!.groupId == group.groupId);

        if (index == -1) {
          allContacts.add(GroupContactsModel(group: group, contactType: ContactsType.GROUP));
        }
      }

      if (expandIndex != null) {
        this.expandIndex = expandIndex;
      } else {
        if (expandGroup != null) {
          this.expandIndex = groupList.indexWhere((element) => element.groupId == expandGroup.groupId);
        } else {
          this.expandIndex = 0;
        }
      }

      if (addToGroupSink) {
        atGroupSink.add(groupList);
      }
    } catch (e) {
      log(e.toString());
      atGroupSink.add([]);
    }
  }

  // ignore: always_declare_return_types
  listAllGroupNames() async {
    try {
      var groupNames = await atContactImpl.listGroupNames();
      return groupNames;
    } catch (e) {
      return e;
    }
  }

  /// Function to get group details for a group ID
  Future<AtGroup?> getGroupDetail(String groupId) async {
    try {
      var group = await atContactImpl.getGroup(groupId);
      return group;
    } catch (e) {
      atSignLogger.severe('error in getting group details : $e');
      return null;
    }
  }

  /// Function to delete members of a group
  Future<dynamic> deletGroupMembers(List<AtContact> contacts, AtGroup group) async {
    try {
      var result = await atContactImpl.deleteMembers(Set.from(contacts), group);
      await updateGroupStreams(group, expandGroup: true);
      return result;
    } catch (e) {
      atSignLogger.severe('error in deleting group members:$e');
      return e;
    }
  }

  /// Function to add members to a group
  Future<dynamic> addGroupMembers(List<AtContact?> contacts, AtGroup group) async {
    for (var i = 0; i < contacts.length; i++) {
      if (contacts[i]!.tags != null && contacts[i]!.tags!['image'] != null) {
        contacts[i]!.tags!['image'] = null;
      }
    }

    try {
      var result = await atContactImpl.addMembers(Set.from(contacts), group);
      await updateGroupStreams(group, expandGroup: true);
      return result;
    } catch (e) {
      atSignLogger.severe('error in adding members: $e');
      return e;
    }
  }

  /// Function to update group details
  Future<dynamic> updateGroup(AtGroup group, {int? expandIndex}) async {
    group = removeImageFromAtGroupMembers(group);
    try {
      var updatedGroup = await atContactImpl.updateGroup(group);
      if (updatedGroup is AtGroup) {
        updateGroupStreams(updatedGroup, expandIndex: expandIndex);
        return updatedGroup;
      } else {
        return 'something went wrong';
      }
    } catch (e) {
      atSignLogger.severe('error in updating group: $e');
      return e;
    }
  }

  // ignore: always_declare_return_types
  updateGroupStreams(AtGroup group, {int? expandIndex, bool expandGroup = false}) async {
    var groupDetail = await (getGroupDetail(group.groupId!));
    if (groupDetail is AtGroup) groupViewSink.add(groupDetail);
    await getAllGroupsDetails(expandIndex: expandIndex, expandGroup: expandGroup ? group : null);
  }

  /// Function to delete a group
  Future<bool?> deleteGroup(AtGroup group) async {
    try {
      var result = await atContactImpl.deleteGroup(group);
      await getAllGroupsDetails(); //updating group list sink
      return result;
    } on Exception catch (e) {
      atSignLogger.severe('error in deleting group: $e');
      return null;
    }
  }

  Future<dynamic> updateGroupData(AtGroup group, BuildContext context,
      {bool isDesktop = false, int? expandIndex}) async {
    group = removeImageFromAtGroupMembers(group);
    try {
      var result = await updateGroup(group, expandIndex: expandIndex);
      if (isDesktop) {
        return result;
      } else {
        if (result is AtGroup) {
          Navigator.of(context).pop();
        } else if (result == null) {
          CustomToast().show(TextConstants().SERVICE_ERROR, context);
        } else {
          CustomToast().show(result.toString(), context);
        }
      }
    } catch (e) {
      return e;
    }
  }

  // fetches contacts using the contacts library and groups from itself
  // ignore: always_declare_return_types
  fetchGroupsAndContacts({bool isDesktop = false}) async {
    try {
      /// contacts list is already present, we do not fetch it again.
      if (allContacts.isNotEmpty) {
        listContact.sort((a, b) {
          int? index = a.atSign.toString().substring(1).compareTo((b.atSign).toString().substring(1));
          return index;
        });

        /// If both contacts list are same, no chanbges have been made by the user.
        if (listContact == ContactService().contactList) {
          WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
            _allContactsStreamController.add(allContacts);
          });
          return;
        }
      }
      allContacts = [];
      listContact = [];
      var contactList = await fetchContacts();
      if (contactList != null) {
        for (AtContact? contact in contactList) {
          var index = -1;
          if (contact != null) {
            index = allContacts
                .indexWhere((element) => element!.contact != null && element.contact!.atSign == contact.atSign);
          }

          if (index == -1) {
            listContact.add(contact!);
            allContacts.add(GroupContactsModel(contact: contact, contactType: ContactsType.CONTACT));
          }
        }
        await getAllGroupsDetails(addToGroupSink: !isDesktop);
        _allContactsStreamController.add(allContacts);
      }
    } catch (e) {
      _allContactsStreamController.add([]);
    }
  }

  /// adds [atSign] to [allContacts]
  appendNewContact(String atSign) {
    try {
      var _indexOfContact = ContactService().contactList.indexWhere((element) {
        return ContactService().compareAtSign(element.atSign!, atSign);
      });

      if (_indexOfContact != -1) {
        var _indexOfContactInGroup =
            allContacts.indexWhere((element) => element!.contact != null && element.contact!.atSign == atSign);

        if (_indexOfContactInGroup == -1) {
          allContacts.add(GroupContactsModel(
              contact: ContactService().contactList[_indexOfContact], contactType: ContactsType.CONTACT));
        }
      }
      _allContactsStreamController.add(allContacts);
    } catch (e) {
      _allContactsStreamController.add([]);
    }
  }

  /// removes [atSign] to [allContacts]
  removeContact(String atSign) {
    try {
      allContacts.removeWhere((element) {
        if (element!.contact == null) {
          return false;
        }
        return ContactService().compareAtSign(element.contact!.atSign!, atSign);
      });

      _allContactsStreamController.add(allContacts);
    } catch (e) {
      _allContactsStreamController.add([]);
    }
  }

  // ignore: always_declare_return_types
  removeGroupContact(GroupContactsModel? item) async {
    try {
      length = 0;
      if (selectedGroupContacts.isNotEmpty) {
        for (var groupContact in selectedGroupContacts) {
          if (groupContact!.contactType == ContactsType.CONTACT) {
            length++;
          } else if (groupContact.contactType == ContactsType.GROUP) {
            length = length + groupContact.group!.members!.length;
          }
        }
      }

      // ignore: omit_local_variable_types
      for (GroupContactsModel? groupContact in selectedGroupContacts) {
        if (groupContact!.contact != null &&
            item!.contact != null &&
            groupContact.contact!.atSign == item.contact!.atSign) {
          var index = selectedGroupContacts.indexOf(groupContact);
          selectedGroupContacts.removeAt(index);
          break;
        } else if (groupContact.group != null &&
            item!.group != null &&
            groupContact.group!.groupId == item.group!.groupId) {
          var index = selectedGroupContacts.indexOf(groupContact);
          selectedGroupContacts.removeAt(index);
          break;
        }
      }

      if (item!.contactType == ContactsType.CONTACT) {
        length--;
      } else if (item.contactType == ContactsType.GROUP) {
        length -= item.group!.members!.length;
      }

      selectedContactsSink.add(selectedGroupContacts);
    } catch (e) {
      atSignLogger.severe('Error in removeGroupContact $e');
    }
  }

  // ignore: always_declare_return_types
  addGroupContact(GroupContactsModel? item) {
    try {
      var isSelected = false;
      length = 0;
      if (selectedGroupContacts.isNotEmpty) {
        for (var groupContact in selectedGroupContacts) {
          if (groupContact!.contactType == ContactsType.CONTACT) {
            length++;
          } else if (groupContact.contactType == ContactsType.GROUP) {
            length = length + groupContact.group!.members!.length;
          }
        }
      }

      // ignore: omit_local_variable_types
      for (GroupContactsModel? groupContact in selectedGroupContacts) {
        if ((item.toString() == groupContact.toString())) {
          isSelected = true;
          break;
        } else {
          isSelected = false;
        }
      }

      if (length <= 25 && !isSelected) {
        selectedGroupContacts.add(item);
      }

      if (item!.contactType == ContactsType.CONTACT) {
        length++;
      } else if (item.contactType == ContactsType.GROUP) {
        length += item.group!.members!.length;
      }

      selectedContactsSink.add(selectedGroupContacts);
    } catch (e) {
      selectedContactsSink.add([]);
    }
  }

  AtGroup removeImageFromAtGroupMembers(AtGroup atGroup) {
    for (var i = 0; i < atGroup.members!.length; i++) {
      if (atGroup.members!.elementAt(i).tags != null && atGroup.members!.elementAt(i).tags!['image'] != null) {
        atGroup.members!.elementAt(i).tags!['image'] = null;
      }
    }

    return atGroup;
  }

  /// Function to reset all data related to groups
  void resetData() {
    allContacts = [];
    selectedGroupContacts = [];
    selectedContactsSink.add(selectedGroupContacts);
    atGroupSink.add([]);
    allContactsSink.add([]);
    showLoaderSink.add(false);
  }

  /// Function to dispose all declared stream controllers
  void dispose() {
    _atGroupStreamController.close();
    _groupViewStreamController.close();
    _allContactsStreamController.close();
    _selectedContactsStreamController.close();
    _showLoaderStreamController.close();
  }
}
