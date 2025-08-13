// ignore_for_file: use_build_context_synchronously

import 'dart:typed_data';

import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_commons/at_commons.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_group_flutter/services/group_service.dart';
import 'package:at_contacts_group_flutter/services/image_picker.dart';
import 'package:at_contacts_group_flutter/utils/colors.dart';
import 'package:at_contacts_group_flutter/utils/text_constants.dart';
import 'package:at_contacts_group_flutter/widgets/bottom_sheet.dart';
import 'package:at_contacts_group_flutter/widgets/custom_toast.dart';
import 'package:at_contacts_group_flutter/widgets/person_vertical_tile.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

/// This widget provides screen to create a new group
class NewGroup extends StatefulWidget {
  const NewGroup({Key? key}) : super(key: key);
  @override
  _NewGroupState createState() => _NewGroupState();
}

class _NewGroupState extends State<NewGroup> {
  /// List of contacts selected for the group
  List<AtContact?>? selectedContacts;

  /// Name of the group
  String groupName = '';

  /// Image in bytes selected for the group
  Uint8List? selectedImageByteData;

  /// Boolean flag to indicate keyboard visibility
  bool isKeyBoardVisible = false,

      /// Boolean flag to indicate emoji keyboard visibility
      showEmojiPicker = false;

  /// Text controller for text field to enter group name
  TextEditingController textController = TextEditingController();
  UniqueKey key = UniqueKey();

  /// Focus node for the text field
  FocusNode textFieldFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    getContacts();
  }

  // ignore: always_declare_return_types
  getContacts() {
    if (GroupService().selecteContactList.isNotEmpty) {
      selectedContacts = GroupService().selecteContactList;
    } else {
      selectedContacts = [];
    }
  }

  // ignore: always_declare_return_types
  createGroup() async {
    var isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom != 0 ? true : false;
    groupName = textController.text;
    // ignore: unnecessary_null_comparison
    if (groupName != null) {
      // if (groupName.contains(RegExp(TextConstants().GROUP_NAME_REGEX))) {
      //   CustomToast().show(TextConstants().INVALID_NAME, context);
      //   return;
      // }

      if (groupName.trim().isNotEmpty) {
        var group = AtGroup(
          groupName,
          description: 'group desc',
          displayName: groupName,
          members: Set.from(selectedContacts!),
          createdBy: GroupService().currentAtsign,
          updatedBy: GroupService().currentAtsign,
        );

        if (selectedImageByteData != null) {
          group.groupPicture = selectedImageByteData;
        }

        var result = await GroupService().createGroup(group);

        isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom != 0 ? true : false;

        if (result is AtGroup) {
          Navigator.of(context).pop();
        } else if (result != null) {
          if (result.runtimeType == AlreadyExistsException) {
            CustomToast().show(TextConstants().GROUP_ALREADY_EXISTS, context, gravity: isKeyboardOpen ? 2 : 0);
          } else if (result.runtimeType == InvalidAtSignException) {
            CustomToast().show(result.message, context, gravity: isKeyboardOpen ? 2 : 0);
          } else {
            CustomToast().show(TextConstants().SERVICE_ERROR, context, gravity: isKeyboardOpen ? 2 : 0);
          }
        } else {
          CustomToast().show(TextConstants().SERVICE_ERROR, context, gravity: isKeyboardOpen ? 2 : 0);
        }
      } else {
        CustomToast().show(TextConstants().EMPTY_NAME, context, gravity: isKeyboardOpen ? 2 : 0);
      }
    } else {
      CustomToast().show(TextConstants().EMPTY_NAME, context, gravity: isKeyboardOpen ? 2 : 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.light ? AllColors().WHITE : AllColors().Black,
      bottomSheet: GroupBottomSheet(
        onPressed: createGroup,
        message: selectedContacts!.length == 1
            ? '${selectedContacts!.length} Contact Selected'
            : '${selectedContacts!.length} Contacts Selected',
        buttontext: 'Done',
      ),
      appBar: const CustomAppBar(titleText: 'New Group', showTitle: true, showBackButton: true, showLeadingIcon: true),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            SizedBox(height: 20.toHeight),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 15.toWidth,
                ),
                InkWell(
                  onTap: () async {
                    var image = await ImagePicker().pickImage();
                    setState(() {
                      selectedImageByteData = image;
                    });
                  },
                  child: Container(
                    width: 68.toWidth,
                    height: 68.toWidth,
                    decoration: BoxDecoration(
                      color: AllColors().MILD_GREY,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: selectedImageByteData != null
                          ? SizedBox(
                              width: 68.toWidth,
                              height: 68.toWidth,
                              child: CircleAvatar(
                                backgroundImage: Image.memory(selectedImageByteData!).image,
                              ),
                            )
                          : Icon(Icons.add, color: AllColors().ORANGE),
                    ),
                  ),
                ),
                SizedBox(width: 10.toWidth),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Group name',
                          style: TextStyle(
                            fontSize: 18.toFont,
                            fontWeight: FontWeight.normal,
                          )),
                      const SizedBox(height: 5),
                      Padding(
                        padding: const EdgeInsets.only(right: 15.0),
                        child: Container(
                          width: 330.toWidth,
                          height: 50.toHeight,
                          decoration: BoxDecoration(
                            color: AllColors().INPUT_FIELD_COLOR,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: TextField(
                                  readOnly: false,
                                  focusNode: textFieldFocus,
                                  style: TextStyle(
                                    fontSize: 15.toFont,
                                    fontWeight: FontWeight.normal,
                                  ),
                                  decoration: InputDecoration(
                                    // hintText: hintText,
                                    enabledBorder: InputBorder.none,
                                    border: InputBorder.none,
                                    hintStyle: TextStyle(
                                      color: AllColors().INPUT_FIELD_COLOR,
                                      fontSize: 15.toFont,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                  onTap: () {
                                    if (showEmojiPicker) {
                                      setState(() {
                                        showEmojiPicker = false;
                                      });
                                    }
                                  },
                                  onChanged: (val) {},
                                  controller: textController,
                                  onSubmitted: (str) {},
                                ),
                              ),
                              InkWell(
                                onTap: () {
                                  showEmojiPicker = !showEmojiPicker;
                                  if (showEmojiPicker) {
                                    textFieldFocus.unfocus();
                                  }

                                  setState(() {});
                                },
                                child: Icon(
                                  Icons.emoji_emotions_outlined,
                                  color: Colors.grey,
                                  size: 20.toFont,
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
            SizedBox(height: 13.toHeight),
            const Divider(),
            SizedBox(height: 13.toHeight),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.only(right: 15, left: 15),
                child: SingleChildScrollView(
                  child: GridView.count(
                    physics: const ScrollPhysics(),
                    shrinkWrap: true,
                    crossAxisCount: 4,
                    childAspectRatio: ((SizeConfig().screenWidth * 0.25) / (SizeConfig().screenHeight * 0.2)),
                    children: List.generate(selectedContacts!.length, (index) {
                      return CustomPersonVerticalTile(
                        key: UniqueKey(),
                        imageLocation: null,
                        title: selectedContacts![index]!.atSign,
                        subTitle: selectedContacts![index]!.atSign,
                        icon: Icons.close,
                        isTopRight: true,
                        atsign: selectedContacts![index]!.atSign,
                        onCrossPressed: () {
                          setState(() {
                            selectedContacts!.removeAt(index);
                          });
                        },
                      );
                    }),
                  ),
                ),
              ),
            ),
            showEmojiPicker
                ? Container(
                    height: 250,
                    margin: EdgeInsets.only(bottom: 70.toHeight),
                    child: EmojiPicker(
                      key: UniqueKey(),
                      config: const Config(
                        emojiViewConfig: EmojiViewConfig(
                          columns: 7,
                          emojiSizeMax: 32.0,
                          backgroundColor: Color(0xFFF2F2F2),
                          noRecents: Text(
                            "No Recents",
                            style: TextStyle(
                              fontSize: 20,
                              color: Colors.black26,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                      onEmojiSelected: (category, emoji) {
                        textController.text += emoji.emoji;
                      },
                    ),
                  )
                : const SizedBox()
          ],
        ),
      ),
    );
  }
}
