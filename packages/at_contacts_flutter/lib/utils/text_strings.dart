/// All the strings used in the package
class TextStrings {
  String unknownAtsign(String? atSign) =>
      '$atSign is not found. Please check and try again.';
  String atsignExists(String? atSign) => '$atSign already exists';
  String contacts = 'Contacts';
  String emptyAtsign = 'Please type in an atsign';
  String addingLoggedInUser = 'Cannot add yourself';
  String searchContact = 'Search Contact';
  String buttonCancel = 'Cancel';
  String addtoContact = 'Add to Contacts';
  String addContact = 'Add Contact';
  String noContacts = 'No contacts added';
  String noContactsFound = 'No results';
  String deleteContact = 'Delete Contact';
  String delete = 'Delete';
  String block = 'Block';
  String unblock = 'Unblock';
  String emptyBlockedList = 'No blocked atSigns';
  String blockContact = 'Block Contact';
  String unblockContact = 'Unblock Contact';
  String blockedContacts = 'Blocked atSigns';
  String addContactHeading =
      'Are you sure you want to add the user to your contact list?';
  String yes = 'Yes';
  String no = 'No';
  List<String> contactFields = [
    'firstname.wavi',
    'lastname.wavi',
    'image.wavi',
  ];
  List<String> contactFieldsPersona = [
    'firstname.persona',
    'lastname.persona',
    'image.persona',
  ];
}
