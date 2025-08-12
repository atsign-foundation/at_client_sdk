import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/services/contact_service.dart';
import 'package:at_contacts_group_flutter/services/group_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAtContactImpl extends Mock implements AtContactsImpl {}

class MockAtClient extends Mock implements AtClient {}

class MockGroupService extends Mock implements GroupService {}

class MockContactService extends Mock implements ContactService {}

void main() {
  MockAtContactImpl mockAtContactImpl = MockAtContactImpl();
  MockAtClient mockAtClient = MockAtClient();

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {});

  test("create_group_test", () async {
    AtGroup grp = AtGroup("new_test_group", groupId: "1");
    mockAtContactImpl.atClient = mockAtClient;

    when(() => mockAtContactImpl.createGroup(grp))
        .thenAnswer((invocation) async => grp);

    GroupService().atContactImpl = mockAtContactImpl;
    dynamic res = await GroupService().createGroup(grp);
    expect(res, isA<AtGroup>());
  });

  test("add_group_members", () async {
    AtGroup grp = AtGroup("new_test_group", groupId: "1");
    List<AtContact> contacts = [AtContact(atSign: '@45expected')];

    when(() => mockAtContactImpl.addMembers(Set.from(contacts), grp))
        .thenAnswer(
      (invocation) async => true,
    );

    GroupService().atContactImpl = mockAtContactImpl;
    dynamic res = await GroupService().addGroupMembers(contacts, grp);

    expect(res, true);
  });

  test("delete_group_members", () async {
    AtGroup grp = AtGroup("new_test_group", groupId: "1");
    List<AtContact> contacts = [AtContact(atSign: '@45expected')];

    when(() => mockAtContactImpl.deleteMembers(Set.from(contacts), grp))
        .thenAnswer(
      (invocation) async => true,
    );

    GroupService().atContactImpl = mockAtContactImpl;
    dynamic res = await GroupService().deletGroupMembers(contacts, grp);

    expect(res, true);
  });

  test("get_group_detail", () async {
    AtGroup grp = AtGroup("new_test_group", groupId: "1");

    when(() => mockAtContactImpl.getGroup("1")).thenAnswer(
      (invocation) async => grp,
    );

    GroupService().atContactImpl = mockAtContactImpl;
    AtGroup? res = await GroupService().getGroupDetail("1");

    expect(res, isA<AtGroup>());
  });

  test("update_group", () async {
    AtGroup grp = AtGroup("new_test_group", groupId: "1");

    when(() => mockAtContactImpl.updateGroup(grp)).thenAnswer(
      (invocation) async => grp,
    );

    GroupService().atContactImpl = mockAtContactImpl;
    dynamic res = await GroupService().updateGroup(grp);

    expect(res, isA<AtGroup>());
  });

  test("delete_group", () async {
    AtGroup grp = AtGroup("new_test_group", groupId: "1");

    when(() => mockAtContactImpl.deleteGroup(grp)).thenAnswer(
      (invocation) async => true,
    );

    GroupService().atContactImpl = mockAtContactImpl;
    dynamic res = await GroupService().deleteGroup(grp);

    expect(res, true);
  });
}
