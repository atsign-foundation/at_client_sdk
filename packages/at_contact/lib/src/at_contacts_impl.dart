import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_contact/src/config/app_constants.dart';
import 'package:at_contact/src/model/at_contact.dart';
import 'package:at_contact/src/model/at_group.dart';
import 'package:at_contact/src/service/at_contacts_library.dart';
import 'package:at_utils/at_utils.dart';
import 'package:uuid/uuid.dart';

enum RegexType { all, appSpecific }

class AtContactsImpl implements AtContactsLibrary {
  AtClient? atClient;
  late String atSign;
  late AtSignLogger logger;
  late RegexType _regexType;

  AtContactsImpl(this.atClient, this.atSign, {RegexType? regexType}) {
    _regexType = regexType ?? RegexType.appSpecific;
    logger = AtSignLogger(runtimeType.toString());
  }

  static Future<AtContactsImpl> getInstance(String atSign,
      {RegexType? regexType}) async {
    try {
      atSign = AtUtils.fixAtSign(atSign);
    } on Exception {
      rethrow;
    }
    var atClient = AtClientManager.getInstance().atClient;
    return AtContactsImpl(atClient, atSign, regexType: regexType);
  }

  /// returns  true on success otherwise false.
  /// has to pass the [AtContact] to add new contact into the contact_list
  /// if atSign value is 'null' then returns false
  @override
  Future<bool> add(AtContact contact) async {
    var atSign = contact.atSign;
    //check if atSign is 'null'
    if (atSign == null) return false;
    var atKey = _formKey(KeyType.contact, key: atSign);
    var json = contact.toJson();
    var value = jsonEncode(json);
    return await atClient!.put(atKey, value);
  }

  ///update the existing contact
  @override
  Future<bool> update(AtContact contact) async {
    contact.updatedOn = DateTime.now();
    return await add(contact);
  }

  ///returns the [AtContact].has to pass the 'atSign'
  /// Throws [FormatException] on invalid json
  /// Throws class extending [AtException] on invalid atsign.
  @override
  Future<AtContact?> get(String atSign, {AtKey? getAtKey}) async {
    AtContact? contact;
    var atKey = getAtKey ?? _formKey(KeyType.contact, key: atSign, isGet: true);
    if (_regexType == RegexType.all) {
      List<AtKey>? scanList;
      try {
        scanList = await atClient!.getAtKeys(regex: atKey.key);
      } on KeyNotFoundException {
        logger.info('${atKey.key} on not found in the keystore');
      } on AtClientException {
        logger.info('${atKey.key} on not found in the keystore');
      }
      atKey = (scanList != null && scanList.isNotEmpty)
          ? _formAtKeyFromScanKeys(scanList[0])
          : atKey;
    }
    AtValue? atValue;
    atValue = await _get(atKey);

    //check for old key if new key data is not present.
    if (atValue?.value == null) {
      atKey = _formKey(KeyType.contact, key: atSign, isOld: true);
      atValue = await _get(atKey);
    }
    //migrate key to new key format if atKey is old.
    if (atValue?.value != null && _isOldKey(atKey)) {
      var newAtKey = _formKey(KeyType.contact, key: atSign);
      await atClient!.put(newAtKey, atValue?.value);
      AtValue? getValue;
      getValue = await _get(newAtKey);
      if (getValue?.value != null) await atClient!.delete(atKey);
    }
    if (atValue?.value != null) {
      var value = atValue?.value;
      value = value?.replaceFirst(RegExp(r'^data:'), '');
      if (value != null && value != 'null') {
        dynamic json;
        try {
          json = jsonDecode(value);
        } on FormatException catch (e) {
          logger.severe('Invalid JSON. ${e.message} found in JSON : $value');
          throw InvalidSyntaxException('Invalid JSON found');
        }
        if (json != null) {
          contact = AtContact.fromJson(json);
        }
      }
    }
    return contact;
  }

  /// takes atSign of the contact as an input and
  /// delete the contacts from the contact_list
  /// on success return true otherwise false
  @override
  Future<bool> delete(String atSign) async {
    var newAtKey = _formKey(KeyType.contact, key: atSign);
    return await atClient!.delete(newAtKey);
  }

  /// takes   [AtContact]  as an input and
  /// delete the contacts from the contact_list
  /// on success return true otherwise false
  @override
  Future<bool> deleteContact(AtContact contact) async {
    var atSign = contact.atSign;
    //check if atSign is 'null'
    if (atSign == null) return false;
    return await delete(atSign);
  }

  /// fetch all contacts in the list
  ///returns the list of [AtContact]
  @override
  Future<List<AtContact>> listContacts() async {
    var preference = atClient!.getPreferences();
    Set contactSet = <String>{};
    var contactList = <AtContact>[];
    var atSign = this.atSign.replaceFirst('@', '');
    var appNamespace =
        preference!.namespace == null ? '' : '.${preference.namespace}';
    var subRegex = _regexType == RegexType.appSpecific
        ? '$atSign.${AppConstants.LIBRARY_NAMESPACE}$appNamespace'
        : '$atSign.${AppConstants.LIBRARY_NAMESPACE}.*';
    var regex =
        '${AppConstants.CONTACT_KEY_PREFIX}.*.(${AppConstants.CONTACT_KEY_SUFFIX}.$atSign|$subRegex)@$atSign'
            .toLowerCase();
    var scanList = await atClient!.getAtKeys(regex: regex);
    scanList.retainWhere((scanKeys) =>
        !scanKeys.key.contains(AppConstants.GROUPS_LIST_KEY_PREFIX));
    if (scanList.isEmpty) {
      return contactList;
    }
    for (final key in scanList) {
      var atsign = reduceKey(key.key);
      var atKey = _formAtKeyFromScanKeys(key);
      AtContact? contact;
      try {
        contact = await get(atsign, getAtKey: atKey);
      } on Exception catch (e) {
        logger.severe('Invalid atsign contact found @$key : $e');
      }
      if (contact != null) {
        var isUnique = contactSet.add(contact.atSign);
        if (isUnique) {
          contactList.add(contact);
        }
      }
    }
    contactSet.clear();
    return contactList;
  }

  /// fetch all active contacts in the list
  ///returns the list of [AtContact]
  @override
  Future<List<AtContact>> listActiveContacts() async {
    var contactList = await listContacts();
    return contactList.where((element) => !element.blocked!).toList();
  }

  /// fetch all blocked contacts in the list
  ///returns the list of [AtContact]
  @override
  Future<List<AtContact>> listBlockedContacts() async {
    var contactList = await listContacts();
    return contactList.where((element) => element.blocked!).toList();
  }

  /// fetch all Favorite contacts in the list
  ///returns the list of [AtContact]
  @override
  Future<List<AtContact>> listFavoriteContacts() async {
    var contactList = await listContacts();
    return contactList.where((element) => element.favourite!).toList();
  }

  /// takes AtGroup as an input and creates the group
  /// on success return AtGroup otherwise null
  @override
  Future<AtGroup?> createGroup(AtGroup? atGroup) async {
    if (atGroup == null || atGroup.groupName == null) {
      throw Exception('Group name is null or empty String');
    }
    var id = atGroup.groupId;
    if (id != null) {
      var group = await getGroup(id);
      if (group != null) {
        throw AlreadyExistsException('Group is already exists with id $id');
      }
    }
    //create groupID
    var groupId = Uuid().v1();
    atGroup.groupId = groupId;
    var groupName = atGroup.groupName;
    var atKey = _formKey(KeyType.group, key: groupId);

    //update atGroup
    atGroup.createdBy = AtUtils.fixAtSign(atSign);
    atGroup.updatedBy = AtUtils.fixAtSign(atSign);
    atGroup.createdOn = DateTime.now();
    atGroup.updatedOn = DateTime.now();

    var json = atGroup.toJson();
    var value = jsonEncode(json);
    var result = await atClient!.put(atKey, value);
    if (result) {
      print('Group creation successful. Adding to group list');
      var atGroupBasicInfo = AtGroupBasicInfo(groupId, groupName);
      // add AtGroupBasicInfo object to list of groupNames
      var success = await _addToGroupList(atGroupBasicInfo);
      print('Add to group list result : $success');
      return atGroup;
    }
    return null;
  }

  /// takes AtGroup as an input and updates the group
  /// on success return AtGroup otherwise null
  @override
  Future<AtGroup?> updateGroup(AtGroup atGroup) async {
    if (atGroup.groupName == null) {
      throw Exception('Group name is null or empty String');
    }
    var groupId = atGroup.groupId;
    var group = await getGroup(groupId);
    if (group == null) {
      throw GroupNotExistsException('No Group exists with Id $groupId');
    }
    var atKey = _formKey(KeyType.group, key: atGroup.groupId!);
    //update atGroup
    atGroup.updatedOn = DateTime.now();

    var json = atGroup.toJson();
    var value = jsonEncode(json);
    var success = await atClient!.put(atKey, value);
    var result = success ? atGroup : null;
    return result;
  }

  /// takes AtGroup as an input and creates the group
  /// on success return AtGroup otherwise null
  @override
  Future<bool> deleteGroup(AtGroup atGroup) async {
    if (atGroup.groupName == null) {
      throw Exception('Group name is null or empty String');
    }
    var groupId = atGroup.groupId;
    var groupName = atGroup.groupName;
    var atKey = _formKey(KeyType.group, key: groupId!);
    var result = await atClient!.delete(atKey);
    if (result) {
      var atGroupBasicInfo = AtGroupBasicInfo(groupId, groupName);
      return await _deleteFromGroupList(atGroupBasicInfo);
    }
    return result;
  }

  /// fetches all the group names as a list
  /// on success return List of Group names otherwise []
  @override
  Future<List<String?>> listGroupNames() async {
    var atKey = _formKey(KeyType.groupList, isGet: true);
    if (_regexType == RegexType.all) {
      var scanList = await atClient!.getAtKeys(regex: atKey.key);
      atKey = scanList.isNotEmpty ? _formAtKeyFromScanKeys(scanList[0]) : atKey;
    }
    AtValue? result;
    result = await _get(atKey);
    //check for old key if new key data is not present.
    if (result?.value == null) {
      atKey = _formKey(KeyType.groupList, isOld: true);
      result = await _get(atKey);
    }
    //migrate key to new key format.
    if (result?.value != null && _isOldKey(atKey)) {
      var newAtKey = _formKey(
        KeyType.groupList,
      );
      await atClient!.put(newAtKey, result?.value);
      AtValue? getValue;
      getValue = await _get(newAtKey);
      // If new key is stored successfully, remove the old key.
      if (getValue?.value != null) await atClient!.delete(atKey);
    }
    // get name from AtGroupBasicInfo for all the groups.
    List<dynamic>? list = [];
    list = (result?.value != null) ? jsonDecode(result?.value) : [];
    list = List<String>.from(list!);
    var groupNames = <String?>[];
    for (final group in list) {
      var groupInfo = AtGroupBasicInfo.fromJson(jsonDecode(group));
      groupNames.add(groupInfo.atGroupName);
    }
    return groupNames;
  }

  /// fetches all the group Ids as a list
  /// on success return List of Group Ids otherwise []
  @override
  Future<List<String?>> listGroupIds() async {
    var atKey = _formKey(KeyType.groupList, isGet: true);
    if (_regexType == RegexType.all) {
      var scanList = await atClient!.getAtKeys(regex: atKey.key);
      atKey = scanList.isNotEmpty ? _formAtKeyFromScanKeys(scanList[0]) : atKey;
    }
    AtValue? result;
    result = await _get(atKey);
    //check for old key if new key data is not present.
    if (result?.value == null) {
      atKey = _formKey(KeyType.groupList, isOld: true);
      result = await _get(atKey);
    }
    //migrate key to new key format.
    if (result?.value != null && _isOldKey(atKey)) {
      var newAtKey = _formKey(KeyType.groupList);
      await atClient!.put(newAtKey, result?.value);
      AtValue? getValue;
      getValue = await _get(newAtKey);
      // If old is migrated to new successfully, remove the old key
      if (getValue?.value != null) await atClient!.delete(atKey);
    }

    // get name from AtGroupBasicInfo for all the groups.
    List<dynamic>? list = [];
    list = (result?.value != null) ? jsonDecode(result?.value) : [];
    list = List<String>.from(list!);
    var groupIds = <String?>[];
    for (final group in list) {
      var groupInfo = AtGroupBasicInfo.fromJson(jsonDecode(group));
      groupIds.add(groupInfo.atGroupId);
    }
    return groupIds;
  }

  /// takes groupName as an input and
  /// get the group details
  /// on success return AtGroup otherwise null
  @override
  Future<AtGroup?> getGroup(String? groupId) async {
    if (groupId == null || groupId.isEmpty) {
      return null;
    }
    var atKey = _formKey(KeyType.group, key: groupId, isGet: true);
    if (_regexType == RegexType.all) {
      List<AtKey>? scanList;
      try {
        scanList = await atClient!.getAtKeys(regex: atKey.key);
      } on KeyNotFoundException {
        logger.info('${atKey.key} does not exist in keystore');
      } on AtClientException {
        logger.info('${atKey.key} does not exist in keystore');
      }
      atKey = (scanList != null && scanList.isNotEmpty)
          ? _formAtKeyFromScanKeys(scanList[0])
          : atKey;
    }
    AtValue? atValue;
    atValue = await _get(atKey);
    //check for old key if new key data is not present.
    if (atValue?.value == null) {
      atKey = _formKey(KeyType.group, key: groupId, isOld: true);
      atValue = await _get(atKey);
    }
    //migrate key to new key format.
    if (atValue?.value != null && _isOldKey(atKey)) {
      var newAtKey = _formKey(KeyType.group, key: groupId);
      await atClient!.put(newAtKey, atValue?.value);
      atValue = await _get(newAtKey);
      if (atValue?.value != null) await atClient!.delete(atKey);
    }
    AtGroup? group;
    if (atValue?.value != null) {
      var value = atValue?.value;
      value = value?.replaceFirst(RegExp(r'^data:'), '');
      if (value != null && value != 'null') {
        var json = jsonDecode(value);
        if (json != null) {
          group = AtGroup.fromJson(json);
        }
      }
    }
    return group;
  }

  /// takes Set of AtContacts as an input and
  /// Adds the contacts to the group members
  /// on success return true otherwise false
  @override
  Future<bool> addMembers(Set<AtContact> atContacts, AtGroup? atGroup) async {
    if (atContacts.isEmpty || atGroup == null) {
      return false;
    }
    if (atGroup.groupId == null) {
      throw GroupNotExistsException('Group ID is null');
    }
    var atKey = _formKey(KeyType.group, key: atGroup.groupId!);
    // Add all contacts in atContacts from atGroup
    for (final contact in atContacts) {
      if (!isMember(contact, atGroup)) {
        atGroup.members!.add(contact);
      }
    }
    atGroup.updatedBy = AtUtils.fixAtSign(atSign);
    atGroup.updatedOn = DateTime.now();
    var json = atGroup.toJson();
    var value = jsonEncode(json);
    return await atClient!.put(atKey, value);
  }

  /// takes Set of AtContacts as an input and
  /// deletes the contacts to the group members
  /// on success return true otherwise false
  @override
  Future<bool> deleteMembers(
      Set<AtContact> atContacts, AtGroup? atGroup) async {
    if (atContacts.isEmpty || atGroup == null) {
      return false;
    }
    if (atGroup.groupId == null) {
      throw GroupNotExistsException('Group ID is null');
    }
    var atKey = _formKey(KeyType.group, key: atGroup.groupId!);
    var members = atGroup.members;
    for (final atContact in atContacts) {
      var contactName = atContact.atSign;
      members!.removeWhere((contact) => (contact.atSign == contactName));
    }
    atGroup.members = members;
    atGroup.updatedBy = AtUtils.fixAtSign(atSign);
    atGroup.updatedOn = DateTime.now();
    var json = atGroup.toJson();
    var value = jsonEncode(json);
    return await atClient!.put(atKey, value);
  }

  /// Throw Exceptions on Invalid AtSigns.
  /// Returns 'AtKey' for [key].
  AtKey _formKey(KeyType keyType,
      {bool isGet = false, String? key, bool isOld = false}) {
    var preference = atClient!.getPreferences();

    if (key != null) {
      try {
        key = AtUtils.fixAtSign(key);
      } on Exception {
        rethrow;
      }
      key = key.replaceFirst('@', '');
    }
    var appNamespace = isGet && _regexType == RegexType.all
        ? '.*'
        : preference!.namespace != null
            ? '.${preference.namespace}'
            : '';
    // ignore: prefer_typing_uninitialized_variables
    var modifiedKey;
    switch (keyType) {
      case KeyType.contact:
        modifiedKey = isOld
            ? '${AppConstants.CONTACT_KEY_PREFIX}.$key.${AppConstants.CONTACT_KEY_SUFFIX}.${atSign.replaceFirst('@', '')}'
            : '${AppConstants.CONTACT_KEY_PREFIX}.$key.${atSign.replaceFirst('@', '')}.${AppConstants.LIBRARY_NAMESPACE}$appNamespace';
        break;
      case KeyType.groupList:
        modifiedKey = isOld
            ? '${AppConstants.CONTACT_KEY_PREFIX}.${AppConstants.GROUPS_LIST_KEY_PREFIX}.${atSign.replaceFirst('@', '')}'
            : '${AppConstants.CONTACT_KEY_PREFIX}.${AppConstants.GROUPS_LIST_KEY_PREFIX}.${atSign.replaceFirst('@', '')}.${AppConstants.LIBRARY_NAMESPACE}$appNamespace';
        break;
      case KeyType.group:
        modifiedKey =
            isOld ? key : '$key.${AppConstants.LIBRARY_NAMESPACE}$appNamespace';
        break;
      default:
        break;
    }
    var atKey = _formAtKey(modifiedKey, isOld: isOld);
    return atKey;
  }

  AtKey _formAtKey(String key, {bool isOld = false}) {
    var metadata = Metadata()
      ..isPublic = false
      ..namespaceAware = false;
    var atKey = AtKey()
      ..key = key
      ..metadata = metadata;
    return atKey;
  }

  ///Returns `true` if key doesn't contain library namespace.
  bool _isOldKey(AtKey atKey) {
    return !atKey.key.contains(AppConstants.LIBRARY_NAMESPACE);
  }

  String reduceKey(String key) {
    var modifiedKey = key.split('.').where((element) {
      return element != AppConstants.CONTACT_KEY_PREFIX.toLowerCase() &&
          element != AppConstants.CONTACT_KEY_SUFFIX.toLowerCase() &&
          element != AppConstants.LIBRARY_NAMESPACE.toLowerCase() &&
          element != atClient!.getPreferences()!.namespace &&
          !atSign.contains(element);
    }).join('');
    return modifiedKey;
  }

  /// Created group key from the group name provided
  String formGroupKey(String groupName) {
    var key = AtUtils.fixAtSign(groupName);
    key = key.replaceFirst('@', '');
    var modifiedKey =
        '${AppConstants.CONTACT_KEY_PREFIX}.${AppConstants.GROUP_KEY_PREFIX}.$key.${atSign.replaceFirst('@', '')}';
    return modifiedKey;
  }

  ///Adds a group to group list
  Future<bool> _addToGroupList(AtGroupBasicInfo atGroupBasicInfo) async {
    var atKey = _formKey(KeyType.groupList, isGet: true);
    if (_regexType == RegexType.all) {
      List<AtKey>? scanList;
      try {
        scanList = await atClient!.getAtKeys(regex: atKey.key);
      } on KeyNotFoundException {
        logger.info('${atKey.key} does not exist in the keystore');
      } on AtClientException {
        logger.info('${atKey.key} does not exist in the keystore');
      }
      atKey = (scanList != null && scanList.isNotEmpty)
          ? _formAtKeyFromScanKeys(scanList[0])
          : atKey;
    }
    AtValue? result;
    result = await _get(atKey);
    //check for old key if new key data is not present.
    if (result?.value == null) {
      var oldAtKey = _formKey(KeyType.groupList, isOld: true);
      result = await _get(oldAtKey);
    }
    //migrate key to new key format.
    if (result?.value != null && _isOldKey(atKey)) {
      var newAtKey = _formKey(KeyType.groupList);
      await atClient!.put(newAtKey, result?.value);
      AtValue? getValue;
      getValue = await _get(newAtKey);
      if (getValue?.value.toString() != 'null') await atClient!.delete(atKey);
    }
    var list = [];
    if (result?.value != null) {
      list = (result?.value != null) ? jsonDecode(result?.value) : [];
    }
    list.add(jsonEncode(atGroupBasicInfo));
    return await atClient!.put(atKey, jsonEncode(list));
  }

  ///Adds a group to group list
  Future<bool> _deleteFromGroupList(AtGroupBasicInfo atGroupBasicInfo) async {
    // gkc commented out the next line as it is an empty statement
    // if (atGroupBasicInfo.atGroupId == null) ;
    var groupId = atGroupBasicInfo.atGroupId;
    var atKey = _formKey(KeyType.groupList, isGet: true);
    if (_regexType == RegexType.all) {
      var scanList = await atClient!.getAtKeys(regex: atKey.key);
      atKey = scanList.isNotEmpty ? _formAtKeyFromScanKeys(scanList[0]) : atKey;
    }
    AtValue? result;
    result = await _get(atKey);
    // get name from AtGroupBasicInfo for all the groups.
    List<dynamic>? list = [];
    list = (result?.value != null) ? jsonDecode(result?.value) : [];
    list = List<String>.from(list!);
    list.removeWhere((group) =>
        (AtGroupBasicInfo.fromJson(jsonDecode(group)).atGroupId == groupId));
    return await atClient!.put(atKey, jsonEncode(list));
  }

  String getGroupsListKey() {
    var groupsListKey =
        '${AppConstants.CONTACT_KEY_PREFIX}.${AppConstants.GROUPS_LIST_KEY_PREFIX}.${atSign.replaceFirst('@', '')}';
    return groupsListKey;
  }

  ///appends namespace for new format keys from scan key
  AtKey _formAtKeyFromScanKeys(AtKey key) {
    var atKey = key;
    atKey.key = key.key + '.' + key.namespace!;
    atKey.metadata.namespaceAware = false;
    return atKey;
  }

  @override
  bool isMember(AtContact atContact, AtGroup atGroup) {
    var result = false;
    var members = atGroup.members!;
    for (final contact in members) {
      if (contact.atSign.toString() == atContact.atSign.toString()) {
        return true;
      }
    }
    return result;
  }

  /// Returns the [AtValue] of the [AtKey]
  Future<AtValue?> _get(AtKey atKey) async {
    // ignore:prefer_typing_uninitialized_variables
    var atValue;
    try {
      atValue = await atClient!.get(atKey);
    } on KeyNotFoundException {
      logger.info('${atKey.key} does not exist in keystore');
    } on AtClientException {
      logger.info('${atKey.key} does not exist in keystore');
    }
    return atValue;
  }
}

enum KeyType { contact, group, groupList }
