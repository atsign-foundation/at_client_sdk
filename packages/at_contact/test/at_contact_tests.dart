import 'package:at_client/at_client.dart';
import 'package:at_contact/at_contact.dart';
import 'package:test/test.dart';

import 'test_util.dart';

Future<void> main() async {
  late AtContactsImpl atContact;
  late AtContact contact;
  var atSign = '@vinod';
  try {
    await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'me', TestUtil.getPreferenceLocal());
    atContact = await AtContactsImpl.getInstance('@colin');
    // set contact details
    contact = AtContact(
      atSign: atSign,
      personas: ['persona1', 'persona22', 'persona33'],
    );
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  group('A group of at_contact  tests', () {
    //test create contact
    test(' test create a contact ', () async {
      var result = await atContact.add(contact);
      print('create result : $result');
      expect(result, true);
    });

    //test update contact
    test(' test update contact', () async {
      // update the contact type
      contact.type = ContactType.Institute;
      var result = await atContact.update(contact);
      print('update result : $result');
      expect(result, true);
    });

    // test get contact
    test(' test get contact by atSign', () async {
      var result = await (atContact.get(atSign));
      print('get result : $result');
      expect(result is AtContact, true);
      expect(result!.atSign, atSign);
    });

    // test active contact
    test(' test check active contact ', () async {
      // update the contact type
      contact.type = ContactType.Institute;
      contact.blocked = false;
      var updateResult = await atContact.update(contact);
      print('update result : $updateResult');
      expect(updateResult, true);

      var result = await (atContact.get(atSign));
      expect(result is AtContact, true);
      expect(result!.blocked, false);
    });

    // test get all active contacts
    test(' test get all active contacts', () async {
      var result = await atContact.listActiveContacts();
      print('result : $result');
      expect(result.length, greaterThan(0));
    });

    // test blocked contact
    test(' test check blocked  contact', () async {
      // update the contact type
      contact.type = ContactType.Institute;
      contact.blocked = true;
      var updateResult = await atContact.update(contact);
      print('update result : $updateResult');
      expect(updateResult, true);

      var result = await (atContact.get(atSign));
      print(result);
      expect(result is AtContact, true);
      expect(result!.blocked, true);
    });

    //test get all blocked contacts
    test(' test get all blocked contacts', () async {
      var result = await atContact.listBlockedContacts();
      print('result : $result');
      expect(result.length, greaterThan(0));
    });

    // test favorite contact
    test('test check favorite  contact', () async {
      // update the contact type
      contact.type = ContactType.Institute;
      contact.favourite = true;
      var updateResult = await atContact.update(contact);
      print('update result : $updateResult');
      expect(updateResult, true);

      var result = await (atContact.get(atSign));
      print(result);
      expect(result is AtContact, true);
      expect(result!.favourite, true);
    });

    // test get all favorite contacts
    test(' test get all favorite contacts', () async {
      var result = await atContact.listFavoriteContacts();
      print('result : $result');
      expect(result.length, greaterThan(0));
    });

    // test get all contacts
    test(' test get all contacts', () async {
      var result = await atContact.listContacts();
      print('getAll result : $result');
      expect(result.length, greaterThan(0));
    });

    //delete contact
    test(' test delete contact by atSign', () async {
      var result = await atContact.delete(atSign);
      print('delete result : $result');
      expect(result, true);
    });
  });
}
