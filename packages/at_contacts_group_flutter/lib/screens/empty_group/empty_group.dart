// ignore: import_of_legacy_library_into_null_safe
import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/screens/contacts_screen.dart';
import 'package:at_contacts_group_flutter/screens/new_group/new_group.dart';
import 'package:at_contacts_group_flutter/services/group_service.dart';
import 'package:at_contacts_group_flutter/utils/colors.dart';
import 'package:at_contacts_group_flutter/utils/images.dart';
import 'package:at_contacts_group_flutter/utils/text_styles.dart';
import 'package:flutter/material.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:at_common_flutter/at_common_flutter.dart';

/// [EmptyGroup] is displayed when no group is created.
///  It also provides option to create a new group.
class EmptyGroup extends StatefulWidget {
  const EmptyGroup({Key? key}) : super(key: key);
  @override
  _EmptyGroupState createState() => _EmptyGroupState();
}

class _EmptyGroupState extends State<EmptyGroup> {
  /// List of selected contacts
  List<AtContact?>? selectedContactList;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              AllImages().EMPTY_GROUP,
              width: 181.toWidth,
              height: 181.toWidth,
              fit: BoxFit.cover,
              package: 'at_contacts_group_flutter',
            ),
            SizedBox(
              height: 15.toHeight,
            ),
            Text('No Groups!', style: CustomTextStyles().grey16),
            SizedBox(
              height: 5.toHeight,
            ),
            Text(
              'Would you like to create a group?',
              style: CustomTextStyles().grey16,
            ),
            SizedBox(
              height: 20.toHeight,
            ),
            CustomButton(
              height: 40.toHeight,
              width: 120.toWidth,
              buttonText: 'Create',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ContactsScreen(
                      asSelectionScreen: true,
                      selectedList: (selectedList) {
                        selectedContactList = selectedList;

                        if (selectedContactList!.isNotEmpty) {
                          GroupService()
                              .setSelectedContacts(selectedContactList);
                        }
                      },
                      saveGroup: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const NewGroup(),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
              buttonColor: Theme.of(context).brightness == Brightness.light
                  ? AllColors().Black
                  : AllColors().WHITE,
              fontColor: Theme.of(context).brightness == Brightness.light
                  ? AllColors().WHITE
                  : AllColors().Black,
              // isInverted: Theme.of(context).primaryColor == Color(0xFF000000)
              //     ? false
              //     : true,
            )
          ],
        ),
      ),
    );
  }
}
