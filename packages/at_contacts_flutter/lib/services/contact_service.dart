// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/models/contact_base_model.dart';
import 'package:at_contacts_flutter/utils/init_contacts_service.dart';
import 'package:at_contacts_flutter/utils/text_strings.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:flutter/material.dart';

/// A service to handle CRUD operation on contacts
class ContactService {
  /// Singleton instance declaration
  ContactService._();

  static final ContactService _instance = ContactService._();

  /// Factory pattern to get singleton instance
  factory ContactService() => _instance;

  /// Instance of at_contact dart library
  late AtContactsImpl atContactImpl;

  /// Root domain to access
  late String rootDomain;

  /// Root port to access
  late int rootPort;

  /// Current atsign's contact details
  AtContact? loggedInUserDetails;

  /// Instance of AtClientManager
  late AtClientManager atClientManager;

  /// Current atsign in use
  late String currentAtsign;

  /// Stream controller for contacts' list stream
  StreamController<List<BaseContact?>> contactStreamController =
      StreamController<List<BaseContact?>>.broadcast();

  /// Sink for the contacts' list stream
  Sink get contactSink => contactStreamController.sink;

  /// Stream of contacts' list
  Stream<List<BaseContact?>> get contactStream =>
      contactStreamController.stream;

  /// Stream controller for blocked contacts' list stream
  StreamController<List<BaseContact?>> blockedContactStreamController =
      StreamController<List<BaseContact?>>.broadcast();

  /// Sink for the blocked contacts' list stream
  Sink get blockedContactSink => blockedContactStreamController.sink;

  /// Stream of blocked contacts' list
  Stream<List<BaseContact?>> get blockedContactStream =>
      blockedContactStreamController.stream;

  /// Stream controller for selected contacts' list stream
  StreamController<List<AtContact?>> selectedContactStreamController =
      StreamController<List<AtContact?>>.broadcast();

  /// Sink for the selected contacts' list stream
  Sink get selectedContactSink => selectedContactStreamController.sink;

  /// Stream of selected contacts' list
  Stream<List<AtContact?>> get selectedContactStream =>
      selectedContactStreamController.stream;

  /// dispose function for all the stream controllers declared
  void disposeControllers() {
    contactStreamController.close();
    selectedContactStreamController.close();
    blockedContactStreamController.close();
  }

  /// used by desktop contact screen to manage contacts and the operations performed on them.
  List<BaseContact> baseContactList = [], baseBlockedList = [];

  /// List of contacts added by atsign
  List<AtContact> contactList = [],

      /// List of blocked contacts added by atsign
      blockContactList = [],

      /// List of selected contacts added by atsign
      selectedContacts = [],

      /// Cached list of contacts added by atsign
      cachedContactList = [];

  /// Boolean flag to indicate a contact's presence
  bool isContactPresent = false,

      /// Limit indicator for contact selection
      limitReached = false;

  /// Error thrown in fetching an atsign
  String getAtSignError = '';

  /// Boolean indicator for validating atsign
  bool? checkAtSign;

  /// List of all contacts added by atsign
  List<String> allContactsList = [];

  Future<void> initContactsService(
      String rootDomainFromApp, int rootPortFromApp,
      {bool fetchContacts = true}) async {
    loggedInUserDetails = null;
    rootDomain = rootDomainFromApp;
    rootPort = rootPortFromApp;
    atClientManager = AtClientManager.getInstance();
    currentAtsign = atClientManager.atClient.getCurrentAtSign()!;
    atContactImpl = await AtContactsImpl.getInstance(currentAtsign);
    loggedInUserDetails = await getAtSignDetails(currentAtsign);
    if (fetchContacts) {
      cachedContactList = await atContactImpl.listContacts();
      await fetchContactList();
      await fetchBlockContactList();
    }
  }

  void resetData() {
    getAtSignError = '';
    checkAtSign = false;
  }

  /// gives list of [AtContact].
  /// returns null if some error occurred.
  Future<List<AtContact>?> fetchContacts() async {
    try {
      /// if contact list is already present, data is not fetched again
      if (baseContactList.isNotEmpty) {
        List<AtContact?> baseContacts =
            baseContactList.map((e) => e.contact).toList();
        baseContacts.sort((a, b) {
          int? index = a?.atSign
              .toString()
              .substring(1)
              .compareTo((b?.atSign).toString().substring(1));
          return index ?? 0;
        });
        if (baseContacts == contactList) {
          WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
            contactSink.add(baseContacts);
          });
          return contactList;
        }
      }
      selectedContacts = [];
      contactList = [];
      allContactsList = [];
      contactList = await atContactImpl.listContacts();
      var tempContactList = <AtContact>[...contactList];
      var range = contactList.length;
      for (var i = 0; i < range; i++) {
        allContactsList.add(contactList[i].atSign!);
        if (contactList[i].blocked!) {
          tempContactList.remove(contactList[i]);
        }
      }
      contactList = tempContactList;
      contactList.sort((a, b) {
        int? index = a.atSign
            .toString()
            .substring(1)
            .compareTo(b.atSign!.toString().substring(1));
        return index;
      });

      compareContactListForUpdatedState();
      contactSink.add(baseContactList);
      return contactList;
    } catch (e) {
      print('error in fetchContacts => $e');
      return null;
    }
  }

  /// compares [contactList] with [baseContactList] and assigns [isBlocking], [isMarkingFav] and [isDeleting]
  /// for existing atsigns in [baseContactList].
  void compareContactListForUpdatedState() {
    for (var c in contactList) {
      var index =
          baseContactList.indexWhere((e) => e.contact!.atSign == c.atSign);
      if (index > -1) {
        baseContactList[index] = BaseContact(
          c,
          isBlocking: baseContactList[index].isBlocking,
          isMarkingFav: baseContactList[index].isMarkingFav,
          isDeleting: baseContactList[index].isDeleting,
        );
      } else {
        baseContactList.add(
          BaseContact(
            c,
            isBlocking: false,
            isMarkingFav: false,
            isDeleting: false,
          ),
        );
      }
    }

    // checking to remove deleted atsigns from baseContactList.
    var atsignsToRemove = <String>[];
    for (var baseContact in baseContactList) {
      var index = contactList.indexWhere(
        (e) => e.atSign == baseContact.contact!.atSign,
      );
      if (index == -1) {
        atsignsToRemove.add(baseContact.contact!.atSign!);
      }
    }
    for (var e in atsignsToRemove) {
      baseContactList.removeWhere((element) => element.contact!.atSign == e);
    }
  }

  /// assigns [isBlocking], [isMarkingFav] and [isDeleting]
  /// for contact [c].
  void compareContactListForUpdatedStateForOneContact(AtContact c) {
    var index =
        baseContactList.indexWhere((e) => e.contact!.atSign == c.atSign);
    if (index > -1) {
      baseContactList[index] = BaseContact(
        c,
        isBlocking: baseContactList[index].isBlocking,
        isMarkingFav: baseContactList[index].isMarkingFav,
        isDeleting: baseContactList[index].isDeleting,
      );
    } else {
      baseContactList.add(
        BaseContact(
          c,
          isBlocking: false,
          isMarkingFav: false,
          isDeleting: false,
        ),
      );
    }
  }

  /// blocks/unblocks [contact] based on boolean [blockAction]
  /// if [blockAction] is [true] , [atContact] will be blocked.
  Future<bool> blockUnblockContact(
      {required AtContact contact, required bool blockAction}) async {
    try {
      contact.blocked = blockAction;
      var res = await atContactImpl.update(contact);
      if (res) {
        await fetchBlockContactList();
        await fetchContacts();
        return res;
      } else {
        return false;
      }
    } catch (error) {
      print('error in unblock: $error');
      return false;
    }
  }

  /// add/remove [contact] from faviorite list.
  Future<bool> markFavContact(AtContact contact) async {
    try {
      contact.favourite = !contact.favourite!;
      var res = await atContactImpl.update(contact);
      if (res) {
        await fetchBlockContactList();
        await fetchContacts();
        return res;
      } else {
        return false;
      }
    } catch (error) {
      print('error in marking fav: $error');
      return false;
    }
  }

  Future<List<AtContact>?> fetchBlockContactList() async {
    try {
      blockContactList = [];
      blockContactList = await atContactImpl.listBlockedContacts();
      compareBlockedContactListForUpdatedState();
      blockedContactSink.add(baseBlockedList);
      return blockContactList;
    } catch (error) {
      print('error in fetching contact list:$error');
      return null;
    }
  }

  /// compares [blockContactList] with [baseBlockedList] and assigns [isBlocking], [isMarkingFav] and [isDeleting]
  /// for existing atsigns in [baseBlockedList].
  void compareBlockedContactListForUpdatedState() {
    for (var c in blockContactList) {
      var index =
          baseBlockedList.indexWhere((e) => e.contact!.atSign == c.atSign);
      if (index > -1) {
        baseBlockedList[index] = BaseContact(
          c,
          isBlocking: baseBlockedList[index].isBlocking,
          isMarkingFav: baseBlockedList[index].isMarkingFav,
          isDeleting: baseBlockedList[index].isDeleting,
        );
      } else {
        baseBlockedList.add(
          BaseContact(
            c,
            isBlocking: false,
            isMarkingFav: false,
            isDeleting: false,
          ),
        );
      }
    }

    // checking to remove unblocked atsigns from baseBlockedList.
    var atsignsToRemove = <String>[];
    for (var baseContact in baseBlockedList) {
      var index = blockContactList.indexWhere(
        (e) => e.atSign == baseContact.contact!.atSign,
      );
      if (index == -1) {
        atsignsToRemove.add(baseContact.contact!.atSign!);
      }
    }
    for (var e in atsignsToRemove) {
      baseBlockedList.removeWhere((element) => element.contact!.atSign == e);
    }
  }

  Future<bool> deleteAtSign({required String atSign}) async {
    try {
      var result = await atContactImpl.delete(atSign);
      print('delete result => $result');
      _removeContact(atSign);
      return result;
    } catch (error) {
      print('error in delete atsign:$error');
      return false;
    }
  }

  /// remove [atSign] from all lists
  _removeContact(String atSign) {
    try {
      baseContactList.removeWhere((element) {
        return compareAtSign(element.contact!.atSign!, atSign);
      });
      selectedContacts.removeWhere((element) {
        return compareAtSign(element.atSign!, atSign);
      });
      contactList.removeWhere((element) {
        return compareAtSign(element.atSign!, atSign);
      });
      allContactsList.removeWhere((element) {
        return compareAtSign(element, atSign);
      });

      contactSink.add(baseContactList);
    } catch (e) {
      print('error in _removeContact => $e');
    }
  }

  /// Function to validate, fetch details and save to current atsign's contact list
  Future<bool> addAtSign({
    String? atSign,
    String? nickName,
  }) async {
    if (atSign == null || atSign == '') {
      getAtSignError = TextStrings().emptyAtsign;

      return false;
    } else if (atSign[0] != '@') {
      atSign = '@$atSign';
    }
    atSign = atSign.toLowerCase().trim();

    if (atSign == atClientManager.atClient.getCurrentAtSign()) {
      getAtSignError = TextStrings().addingLoggedInUser;

      return false;
    }
    try {
      isContactPresent = false;

      getAtSignError = '';
      var contact = AtContact();

      checkAtSign = await checkAtsign(atSign);

      if (!checkAtSign!) {
        getAtSignError = TextStrings().unknownAtsign(atSign);
      } else {
        for (var element in contactList) {
          if (element.atSign == atSign) {
            getAtSignError = TextStrings().atsignExists(atSign);
            isContactPresent = true;
            break;
          }
        }
      }
      if (!isContactPresent && checkAtSign!) {
        var details = await getContactDetails(atSign, nickName);
        contact = AtContact(
          atSign: atSign,
          tags: details,
        );
        print('details==>${contact.atSign}');
        var result = await atContactImpl.add(contact).catchError((e) {
          print('error to add contact => $e');
          return false;
        });

        if (result) {
          if (!cachedContactList.contains(contact)) {
            cachedContactList.add(contact);
          }
        }

        print(result);
        allContactsList.add(contact.atSign!);
        contactList.add(contact);

        compareContactListForUpdatedStateForOneContact(contact);
        contactSink.add(baseContactList);
        return true;
      } else {
        return false;
      }
    } catch (e) {
      print(' error in adding atsign: $e');
      return false;
    }
  }

  void removeSelectedAtSign(AtContact? contact) {
    try {
      for (AtContact? atContact in selectedContacts) {
        if (atContact!.atSign == contact!.atSign) {
          var index = selectedContacts.indexOf(contact);
          selectedContacts.removeAt(index);
          break;
        }
      }
      if (selectedContacts.length <= 25) {
        limitReached = false;
      } else {
        limitReached = true;
      }
      selectedContactSink.add(selectedContacts);
    } catch (error) {
      print(error);
    }
  }

  void selectAtSign(AtContact? contact) {
    try {
      if (selectedContacts.length <= 25 &&
          !selectedContacts.contains(contact)) {
        selectedContacts.add(contact!);
      } else {
        limitReached = true;
      }
      selectedContactSink.add(selectedContacts);
    } catch (error) {
      print(error);
    }
  }

  void clearAtSigns() {
    try {
      selectedContacts = [];
      selectedContactSink.add(selectedContacts);
    } catch (error) {
      print(error);
    }
  }

  /// Function to validate atsign
  Future<bool> checkAtsign(String? atSign) async {
    if (atSign == null) {
      return false;
    } else if (!atSign.contains('@')) {
      atSign = '@$atSign';
    }
    try {
      var secondaryAddress =
          await CacheableSecondaryAddressFinder(rootDomain, rootPort)
              .findSecondary(atSign);
      return secondaryAddress.host != '';
    } catch (e) {
      return false;
    }
  }

  /// Function to get firstname, lastname and profile picture of an atsign
  Future<Map<String, dynamic>> getContactDetails(
      String? atSign, String? nickName) async {
    var contactDetails = <String, dynamic>{};

    if (atClientManager.atClient.getCurrentAtSign() == null || atSign == null) {
      return contactDetails;
    } else if (!atSign.contains('@')) {
      atSign = '@$atSign';
    }
    var metadata = Metadata();
    metadata.isPublic = true;
    metadata.namespaceAware = false;
    var key = AtKey();
    key.sharedBy = atSign;
    key.metadata = metadata;
    List contactFields = TextStrings().contactFields;

    String? firstname;
    String? lastname;

    try {
      // firstname
      key.key = contactFields[0];
      var result = await atClientManager.atClient.get(key);
      if (result.value != null) {
        firstname = result.value;
      }
    } catch (e) {
      print("error in getting firstname: $e");
    }

    try {
      // lastname
      metadata.isPublic = true;
      metadata.namespaceAware = false;
      key.sharedBy = atSign;
      key.metadata = metadata;
      // making isPublic true (as get method changes it to false)
      key.key = contactFields[1];
      var result = await atClientManager.atClient.get(key);
      if (result.value != null) {
        lastname = result.value;
      }
    } catch (e) {
      print("error in getting lastname: $e");
    }

    if (firstname == null && lastname == null) {
      contactDetails['name'] = null;
    } else {
      // construct name
      var name = ('${firstname ?? ''} ${lastname ?? ''}').trim();
      if (name.isEmpty) {
        name = atSign.substring(1);
      }
      contactDetails['name'] = name;
    }

    try {
      // profile picture
      metadata.isPublic = true;
      metadata.namespaceAware = false;
      key.sharedBy = atSign;
      key.metadata = metadata;
      // making isPublic true (as get method changes it to false)
      key.metadata.isBinary = true;
      key.key = contactFields[2];
      Uint8List? image;

      GetRequestOptions options = GetRequestOptions();
      options.bypassCache = true;
      var result =
          await atClientManager.atClient.get(key, getRequestOptions: options);

      if (result.value != null) {
        try {
          List<int> intList = result.value.cast<int>();
          image = Uint8List.fromList(intList);
        } catch (e) {
          print('invalid iamge data: $e');
        }
      }

      contactDetails['image'] = image;
    } catch (e) {
      print("error in getting image: $e");
      contactDetails['image'] = null;
    }
    contactDetails['nickname'] = nickName != '' ? nickName : null;

    return contactDetails;
  }

  Future<Map<String, dynamic>?> getProfilePicture(String atsign) async {
    var contactDetails = <String, dynamic>{};

    var metadata = Metadata();
    metadata.isPublic = true;
    metadata.namespaceAware = false;
    var key = AtKey();
    key.sharedBy = atsign;
    key.metadata = metadata;
    // making isPublic true (as get method changes it to false)
    key.metadata.isBinary = true;
    key.key = "image.wavi";

    GetRequestOptions options = GetRequestOptions();
    options.bypassCache = true;
    var result =
        await atClientManager.atClient.get(key, getRequestOptions: options);

    if (result.value != null) {
      try {
        List<int> intList = result.value.cast<int>();
        var image = Uint8List.fromList(intList);
        contactDetails['image'] = image;
        return contactDetails;
      } catch (e) {
        print('invalid iamge data: $e');
        contactDetails['image'] = null;
        return contactDetails;
      }
    } else {
      return null;
    }
  }

  Future<Metadata?> fetchProfilePictureMetaData(String atsign) async {
    var metadata = Metadata();
    metadata.isPublic = true;
    metadata.namespaceAware = false;
    var key = AtKey();
    key.sharedBy = atsign;
    key.metadata = metadata;
    // making isPublic true (as get method changes it to false)
    key.metadata.isBinary = true;
    key.key = "image.wavi";

    var result = await atClientManager.atClient.getMeta(key);
    return result;
  }

  /// updates status of contacts for [baseContactList] and [baseBlockedList]
  void updateState(STATE_UPDATE stateToUpdate, AtContact contact, bool state) {
    int indexToUpdate;
    if (stateToUpdate == STATE_UPDATE.unblock) {
      indexToUpdate = baseBlockedList
          .indexWhere((element) => element.contact!.atSign == contact.atSign);
    } else {
      indexToUpdate = baseContactList
          .indexWhere((element) => element.contact!.atSign == contact.atSign);
    }

    if (indexToUpdate == -1) {
      throw Exception('index range error: $indexToUpdate');
    }

    switch (stateToUpdate) {
      case STATE_UPDATE.block:
        baseContactList[indexToUpdate].isBlocking = state;
        break;
      case STATE_UPDATE.unblock:
        baseBlockedList[indexToUpdate].isBlocking = state;
        break;
      case STATE_UPDATE.delete:
        baseContactList[indexToUpdate].isDeleting = state;
        break;
      case STATE_UPDATE.markFav:
        baseContactList[indexToUpdate].isMarkingFav = state;
        break;
      default:
    }

    if (stateToUpdate == STATE_UPDATE.unblock) {
      blockedContactSink.add(baseBlockedList);
    } else {
      contactSink.add(baseContactList);
    }
  }

  /// returns true if [atsign1] & [atsign2] are same
  bool compareAtSign(String atsign1, String atsign2) {
    if (atsign1[0] != '@') {
      atsign1 = '@$atsign1';
    }
    if (atsign2[0] != '@') {
      atsign2 = '@$atsign2';
    }

    return atsign1.toLowerCase() == atsign2.toLowerCase() ? true : false;
  }
}
