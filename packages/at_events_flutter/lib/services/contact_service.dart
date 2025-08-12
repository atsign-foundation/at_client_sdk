// ignore_for_file: unnecessary_null_comparison

import 'package:at_commons/at_commons.dart';
import 'package:at_contact/at_contact.dart';

import 'event_key_stream_service.dart';
import 'package:at_utils/at_logger.dart';

/// returns [atSign]'s AtContact details
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

/// returns [atsign]'s AtContact details from cached list, if present
AtContact? getCachedContactDetail(String? atsign) {
  if (atsign ==
      EventKeyStreamService().atContactImpl?.atClient?.getCurrentAtSign()) {
    return EventKeyStreamService().loggedInUserDetails;
  }
  if (EventKeyStreamService().contactList.isNotEmpty) {
    var index = EventKeyStreamService()
        .contactList
        .indexWhere((element) => element.atSign == atsign);
    if (index > -1) return EventKeyStreamService().contactList[index];
  }
  return null;
}

/// returns [atSign]'s AtContact details from server
Future<Map<String, dynamic>> getContactDetails(atSign) async {
  final _logger = AtSignLogger('getContactDetails');

  var contactDetails = <String, dynamic>{};

  if (EventKeyStreamService().atClientManager == null || atSign == null) {
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
  var contactFields = [
    'firstname.persona',
    'lastname.persona',
    'image.persona',
  ];

  try {
    // firstname
    key.key = contactFields[0];
    var result = await EventKeyStreamService()
        .atClientManager
        .atClient
        .get(key)
        .catchError(
            // ignore: return_of_invalid_type_from_catch_error
            (e) => _logger
                .severe('error in get ${e.errorCode} ${e.errorMessage}'));
    var firstname = result.value;

    // lastname
    key.key = contactFields[1];
    result = await EventKeyStreamService().atClientManager.atClient.get(key);
    var lastname = result.value;

    // construct name
    var name = ((firstname ?? '') + ' ' + (lastname ?? '')).trim();
    if (name.length == 0) {
      name = atSign.substring(1);
    }

    // profile picture
    key.metadata.isBinary = true;
    key.key = contactFields[2];
    result = await EventKeyStreamService().atClientManager.atClient.get(key);
    var image = result.value;
    contactDetails['name'] = name;
    contactDetails['image'] = image;
  } catch (e) {
    contactDetails['name'] = null;
    contactDetails['image'] = null;
  }
  return contactDetails;
}
