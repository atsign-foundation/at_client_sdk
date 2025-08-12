import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/models/contact_base_model.dart';
import 'package:at_contacts_flutter/services/contact_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAtcontactImpl extends Mock implements AtContactsImpl {}

void main() {
  MockAtcontactImpl mockAtcontactImpl = MockAtcontactImpl();
  group('Contact Screen test', () {
    test('Fetching contacts', () async {
      when(() => mockAtcontactImpl.listContacts())
          .thenAnswer((invocation) async => [AtContact(atSign: '@alice')]);

      ContactService().atContactImpl = mockAtcontactImpl;
      var res = await ContactService().fetchContacts();

      expect(res, isA<List<AtContact>>());
    });

    test("compare_contact_list_for_updates", () {
      ContactService().contactList = [
        AtContact(atSign: "@83apedistinct"),
        AtContact(atSign: "@45expected")
      ];
      ContactService().baseContactList = [
        BaseContact(AtContact(atSign: "@83apedistinct")),
      ];

      ContactService().compareContactListForUpdatedState();

      expect(ContactService().baseContactList.length, 2);
    });

    test("compare_contact_list_for_update_for_one_contact", () {
      ContactService().baseContactList = [];
      var contact = AtContact(atSign: "@83apedistinct");
      ContactService().compareContactListForUpdatedStateForOneContact(contact);

      expect(ContactService().baseContactList.length, 1);
    });

    test('block_unblock_contact', () async {
      var contact = AtContact(atSign: "@83apedistinct");

      when(() => mockAtcontactImpl.update(contact))
          .thenAnswer((invocation) async => true);

      when(() => mockAtcontactImpl.listBlockedContacts())
          .thenAnswer((invocation) async => [contact]);

      when(() => mockAtcontactImpl.listContacts())
          .thenAnswer((invocation) async => [AtContact(atSign: '@alice')]);

      ContactService().atContactImpl = mockAtcontactImpl;
      var res = await ContactService()
          .blockUnblockContact(contact: contact, blockAction: true);

      expect(res, true);
    });

    test('mark_fav_contact', () async {
      var contact = AtContact(atSign: "@83apedistinct");

      when(() => mockAtcontactImpl.update(contact))
          .thenAnswer((invocation) async => true);

      ContactService().atContactImpl = mockAtcontactImpl;
      var res = await ContactService().markFavContact(contact);

      expect(res, true);
    });

    test('fetch_blocked_contact', () async {
      var contact = AtContact(atSign: "@83apedistinct");

      when(() => mockAtcontactImpl.listBlockedContacts())
          .thenAnswer((invocation) async => [contact]);

      ContactService().atContactImpl = mockAtcontactImpl;
      var res = await ContactService().fetchBlockContactList();

      expect(res, isA<List<AtContact>?>());
    });

    test("compare_blocked_contact_list_for_updates", () {
      ContactService().blockContactList = [
        AtContact(atSign: "@83apedistinct"),
        AtContact(atSign: "@45expected")
      ];
      ContactService().baseBlockedList = [
        BaseContact(AtContact(atSign: "@83apedistinct")),
      ];

      ContactService().compareBlockedContactListForUpdatedState();

      expect(ContactService().baseBlockedList.length, 2);
    });

    test("delete_atSign", () async {
      var atSign = "@83apedistinct";

      when(() => mockAtcontactImpl.delete(atSign))
          .thenAnswer((invocation) async => true);

      ContactService().atContactImpl = mockAtcontactImpl;
      var res = await ContactService().deleteAtSign(atSign: atSign);

      expect(res, true);
    });

    test("remove_atSign", () async {
      var contact = AtContact(atSign: "@83apedistinct");
      ContactService().selectedContacts = [contact];
      ContactService().removeSelectedAtSign(contact);

      expect(ContactService().selectedContacts.length, 0);
    });

    test("select_atSign", () async {
      var contact = AtContact(atSign: "@83apedistinct");
      var contact2 = AtContact(atSign: "@45expected");
      ContactService().selectedContacts = [contact];
      ContactService().selectAtSign(contact2);

      expect(ContactService().selectedContacts.length, 2);
    });

    test("clear_atSign", () async {
      var contact = AtContact(atSign: "@83apedistinct");
      var contact2 = AtContact(atSign: "@45expected");
      ContactService().selectedContacts = [contact, contact2];
      ContactService().clearAtSigns();

      expect(ContactService().selectedContacts.length, 0);
    });

    test("compare_atSign", () async {
      var atSign = "@45expected";
      var atSign2 = "@83apedistinct";
      var atSign3 = "45expected";

      var res = ContactService().compareAtSign(atSign, atSign3);
      var res2 = ContactService().compareAtSign(atSign, atSign2);
      expect(res, true);
      expect(res2, false);
    });
  });
}
