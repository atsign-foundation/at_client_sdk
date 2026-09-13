@Skip('Live tests with no live environment. They need a provisioned '
    '@sitaram on a running virtualenv, a real CRAM secret, and encryption '
    'keys loaded onto the client — and this fixture supplies none of the '
    'three: TestUtil.getPreferenceLocal() carries the literal placeholder '
    "'<cram_secret>', and setCurrentAtSign is called with no atChops and no "
    'key loading, so createGroup fails in putText with "Self encryption key '
    'is not set" before any network call. Confirmed with no containers '
    'running at all, so it is not a missing virtualenv.\n'
    '\n'
    'Skipped rather than left red because nothing was going to notice: '
    'at_contact is in at_libraries.yaml\'s `build` job, which runs pub get '
    'and dart analyze and no tests, so these had failed for anyone running '
    '`dart test` here since the 2022 package move without ever reddening '
    'CI. Unskipping means giving them the environment the live packs have '
    '(see tests/at_functional_test, which loads encryption keys through '
    'AtEncryptionKeysLoader) — not editing the assertions.\n'
    '\n'
    'The sibling at_contact_tests.dart is the same shape and holds 11 more, '
    'and the runner has never collected it: it does not end in _test.dart.')
library;

import 'package:at_client/at_client.dart';
import 'package:at_contact/src/at_contacts_impl.dart';
import 'package:at_contact/src/model/at_contact.dart';
import 'package:at_contact/src/model/at_group.dart';
import 'package:test/test.dart';

import 'test_util.dart';

Future<void> main() async {
  late AtContactsImpl atContactsImpl;
  AtGroup? atGroup;
  var atSign = '@sitaram🛠';
  var preference = TestUtil.getPreferenceLocal();
  try {
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'me', preference);
    atClientManager.atClient.syncService.sync();
    atContactsImpl = await AtContactsImpl.getInstance(atSign);
    // set contact details
    atGroup = AtGroup(atSign, description: 'test', displayName: 'test1');
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  group('A group of at_group  tests', () {
    //test create contact
    test(' test create a group', () async {
      var result = await atContactsImpl.createGroup(atGroup);
      print('create result : $result');
      expect(result is AtGroup, true);
    });

    test(' test add members to group', () async {
      var contact1 = AtContact(type: ContactType.Individual, atSign: '@colin');
      var contact2 = AtContact(type: ContactType.Individual, atSign: '@bob');
      var atContacts = <AtContact>{};
      atContacts.add(contact1);
      atContacts.add(contact2);
      var result = await atContactsImpl.addMembers(atContacts, atGroup);
      print('create result : $result');
      expect(result, true);
    });

    test(' test get group names', () async {
      var result = await atContactsImpl.listGroupNames();
      print('create result : $result');
      expect((result.length > 1), true);
    });

    test(' test get group Ids', () async {
      var result = await atContactsImpl.listGroupIds();
      print('create result : $result');
      expect((result.length > 1), true);
    });

    test(' test delete members from group', () async {
      var contact1 = AtContact(type: ContactType.Individual, atSign: '@colin');
      var atContacts = <AtContact>{};
      atContacts.add(contact1);
      var result = await atContactsImpl.deleteMembers(atContacts, atGroup);
      print('create result : $result');
      expect(result, true);
    });
  });
}
