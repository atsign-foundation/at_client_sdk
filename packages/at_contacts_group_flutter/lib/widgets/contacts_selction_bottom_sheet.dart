import 'package:at_common_flutter/services/size_config.dart';
import 'package:at_common_flutter/widgets/custom_button.dart';
import 'package:at_contacts_flutter/utils/colors.dart';
import 'package:at_contacts_flutter/utils/text_styles.dart';
import 'package:at_contacts_group_flutter/models/group_contacts_model.dart';
import 'package:at_contacts_group_flutter/services/group_service.dart';
import 'package:at_contacts_group_flutter/utils/colors.dart';
import 'package:flutter/material.dart';

/// A bottom sheet widget to diaplay the number of contacts selected from
/// contact list and what to do of that list on press of [Done]
/// takes in @param [onPressed] which defines what to be executed on press of [Done]
/// @param [selectedList] is a [ValueChanged] function which return the selected contacts
/// to be used outside of package.
class ContactSelectionBottomSheet extends StatefulWidget {
  final Function? onPressed;
  final ValueChanged<List<GroupContactsModel?>>? selectedList;
  final bool isDesktop;
  const ContactSelectionBottomSheet({Key? key, this.onPressed, this.selectedList, this.isDesktop = false})
      : super(key: key);

  @override
  State<ContactSelectionBottomSheet> createState() => _ContactSelectionBottomSheetState();
}

class _ContactSelectionBottomSheetState extends State<ContactSelectionBottomSheet> {
  bool processing = false;
  @override
  Widget build(BuildContext context) {
    var _groupService = GroupService();
    return StreamBuilder<List<GroupContactsModel?>>(
      stream: _groupService.selectedContactsStream,
      initialData: _groupService.selectedGroupContacts,
      builder: (context, snapshot) => (snapshot.data!.isEmpty)
          ? Container(
              height: 0,
            )
          : Container(
              padding: EdgeInsets.symmetric(horizontal: 20.toWidth),
              height: 70.toHeight,
              decoration: const BoxDecoration(color: Color(0xffF7F7FF), boxShadow: [BoxShadow(color: Colors.grey)]),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: Text(
                      (_groupService.length != 25)
                          ? '${_groupService.length} Contacts Selected'
                          : '25 of 25 Contact Selected',
                      style: CustomTextStyles.primaryMedium14,
                    ),
                  ),
                  CustomButton(
                    buttonText: processing ? 'Processing...' : 'Done',
                    width: 120.toWidth,
                    height: 40.toHeight,
                    onPressed: processing
                        ? null
                        : () async {
                            setState(() {
                              processing = true;
                            });

                            widget.selectedList!(_groupService.selectedGroupContacts);
                            await widget.onPressed!();

                            if (mounted) {
                              setState(() {
                                processing = true;
                              });
                            }
                          },
                    buttonColor: processing
                        ? ColorConstants.dullText
                        : (Theme.of(context).brightness == Brightness.light
                            ? widget.isDesktop
                                ? AllColors().Orange
                                : Colors.black
                            : Colors.white),
                    fontColor: Theme.of(context).brightness == Brightness.light ? Colors.white : Colors.black,
                  )
                ],
              ),
            ),
    );
  }
}
