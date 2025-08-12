import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/services/contact_service.dart';

Future<List<AtContact?>?> fetchContacts() async {
  var contactList = await ContactService().fetchContacts();
  return contactList;
}
