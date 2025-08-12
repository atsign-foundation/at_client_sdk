// ignore_for_file: avoid_print, prefer_interpolation_to_compose_strings

import 'package:at_commons/at_commons.dart';
import 'package:at_contact/at_contact.dart';

import 'key_stream_service.dart';

/// Retrieves the details of an @sign
Future<AtContact> getAtSignDetails(String? atSign) async {
  var atContact = getCachedContactDetail(atSign);
  if (atContact == null) {
    var contactDetails = await getContactDetails(atSign);
    atContact = AtContact(
      atSign: atSign,
      tags: contactDetails,
    );
  }
  return atContact;
}

/// Retrieves the cached contact details for an @sign
AtContact? getCachedContactDetail(String? atsign) {
  if (atsign ==
      KeyStreamService().atContactImpl?.atClient?.getCurrentAtSign()) {
    return KeyStreamService().loggedInUserDetails;
  }
  if (KeyStreamService().contactList.isNotEmpty) {
    var index = KeyStreamService()
        .contactList
        .indexWhere((element) => element.atSign == atsign);
    if (index > -1) return KeyStreamService().contactList[index];
  }
  return null;
}

/// Retrieves the contact details for an @sign
Future<Map<String, dynamic>> getContactDetails(atSign) async {
  var contactDetails = <String, dynamic>{};

  if (KeyStreamService().atClientInstance == null || atSign == null) {
    return contactDetails;
  } else if (!atSign.contains('@')) {
    atSign = '@' + atSign;
  }
  var metadata = Metadata();
  metadata.isPublic = true;
  metadata.namespaceAware = false;
  var key = AtKey();
  key.sharedBy = atSign;
  key.metadata = metadata;
  var contactFields = [
    'firstname.persona',
    'lastname.persona',
    'image.persona',
  ];

  try {
    // firstname
    key.key = contactFields[0];
    var result = await KeyStreamService().atClientInstance!.get(key).catchError(
        // ignore: return_of_invalid_type_from_catch_error
        (e) => print('error in get ${e.errorCode} ${e.errorMessage}'));
    var firstname = result.value;

    // lastname
    key.key = contactFields[1];
    result = await KeyStreamService().atClientInstance!.get(key);
    var lastname = result.value;

    // construct name
    var name = ((firstname ?? '') + ' ' + (lastname ?? '')).trim();
    if (name.length == 0) {
      name = atSign.substring(1);
    }

    // profile picture
    key.metadata.isBinary = true;
    key.key = contactFields[2];
    result = await KeyStreamService().atClientInstance!.get(key);
    var image = result.value;
    contactDetails['name'] = name;
    contactDetails['image'] = image;
  } catch (e) {
    contactDetails['name'] = null;
    contactDetails['image'] = null;
  }
  return contactDetails;
}
