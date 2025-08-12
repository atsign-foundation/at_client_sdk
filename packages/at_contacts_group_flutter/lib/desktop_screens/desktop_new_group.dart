import 'dart:typed_data';

import 'package:at_common_flutter/services/size_config.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/utils/colors.dart';
import 'package:at_contacts_flutter/widgets/common_button.dart';
import 'package:at_contacts_group_flutter/desktop_routes/desktop_route_names.dart';
import 'package:at_contacts_group_flutter/services/group_service.dart';
import 'package:at_contacts_group_flutter/services/navigation_service.dart';
import 'package:at_contacts_group_flutter/utils/text_constants.dart';
import 'package:at_contacts_group_flutter/utils/text_styles.dart';
import 'package:at_contacts_group_flutter/widgets/custom_toast.dart';
import 'package:at_contacts_group_flutter/services/desktop_image_picker.dart';
import 'package:at_contacts_group_flutter/widgets/desktop_person_vertical_tile.dart';
import 'package:flutter/material.dart';

class DesktopNewGroup extends StatefulWidget {
  final Function? onPop, onDone;
  const DesktopNewGroup({Key? key, this.onPop, @required this.onDone})
      : super(key: key);
  @override
  _DesktopNewGroupState createState() => _DesktopNewGroupState();
}

class _DesktopNewGroupState extends State<DesktopNewGroup> {
  List<AtContact?>? selectedContacts;
  String groupName = '';
  Uint8List? selectedImageByteData;
  bool isKeyBoardVisible = false, showEmojiPicker = false, processing = false;
  TextEditingController textController = TextEditingController();
  UniqueKey key = UniqueKey();
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

  createGroup() async {
    groupName = textController.text;
    // ignore: unnecessary_null_comparison
    if (groupName != null) {
      setState(() {
        processing = true;
      });

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
        if (result is AtGroup) {
          // Navigator.of(context).pop();

          widget.onDone!();

          setState(() {
            processing = false;
          });

          GroupService().setSelectedContacts([]);

          await Navigator.of(
                  NavService.groupPckgRightHalfNavKey.currentContext!)
              .pushReplacementNamed(DesktopRoutes.DESKTOP_GROUP_DETAIL,
                  arguments: {
                'group': result,
              });
          await Navigator.of(NavService.groupPckgLeftHalfNavKey.currentContext!)
              .pushReplacementNamed(
            DesktopRoutes.DESKTOP_GROUP_LIST,
            arguments: {
              'group': result,
            },
          );
        } else if (result != null) {
          if (mounted) {
            if (result.runtimeType == AlreadyExistsException) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(TextConstants().GROUP_ALREADY_EXISTS)));
            } else if (result.runtimeType == InvalidAtSignException) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(result.message)));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(TextConstants().SERVICE_ERROR)));
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(TextConstants().SERVICE_ERROR)));
          }
        }
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(TextConstants().EMPTY_NAME)));
      }

      setState(() {
        processing = false;
      });
    } else {
      CustomToast().show(TextConstants().EMPTY_NAME, context, gravity: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: ColorConstants.listBackground,
        persistentFooterButtons: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  selectedContacts!.length == 1
                      ? '${selectedContacts!.length} Contact Selected'
                      : '${selectedContacts!.length} Contacts Selected',
                  style: CustomTextStyles.primaryRegular20,
                ),
                CommonButton(
                  processing ? 'Creating...' : 'Done',
                  processing
                      ? () {}
                      : () async {
                          await createGroup();
                          // widget.onDone!();
                        },
                  color: processing
                      ? ColorConstants.dullText
                      : ColorConstants.orangeColor,
                  border: 3,
                  height: 45,
                  width: 130,
                  fontSize: 20,
                  removePadding: true,
                ),
              ],
            ),
          )
        ],
        body: Stack(
          children: [
            Column(
              children: <Widget>[
                SizedBox(height: 20.toHeight),
                GestureDetector(
                  onTap: () async {},
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 100.toWidth,
                        height: 100.toWidth,
                        decoration: const BoxDecoration(
                          color: ColorConstants.dividerColor,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: selectedImageByteData != null
                              ? SizedBox(
                                  width: 98.toWidth,
                                  height: 98.toWidth,
                                  child: CircleAvatar(
                                    backgroundImage:
                                        Image.memory(selectedImageByteData!)
                                            .image,
                                  ),
                                )
                              : const SizedBox(),
                        ),
                      ),
                      Positioned(
                        bottom: -5,
                        right: -5,
                        child: InkWell(
                          onTap: () async {
                            var _imageBytes = await desktopImagePicker();
                            if (_imageBytes != null) {
                              setState(() {
                                selectedImageByteData = _imageBytes;
                              });
                            }
                          },
                          child: Container(
                              width: 30,
                              height: 30,
                              decoration: const BoxDecoration(
                                color: ColorConstants.fadedbackground,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.image)),
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 15.toWidth,
                    ),
                    SizedBox(width: 10.toWidth),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 5),
                          Padding(
                            padding: const EdgeInsets.only(right: 15.0),
                            child: Container(
                              width: ((SizeConfig().screenWidth -
                                          TextConstants.SIDEBAR_WIDTH) /
                                      2) -
                                  150,
                              height: 50.toHeight,
                              decoration: BoxDecoration(
                                color: ColorConstants.listBackground,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    child: TextField(
                                      readOnly: false,
                                      style: TextStyle(
                                        fontSize: 15.toFont,
                                        fontWeight: FontWeight.normal,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'Enter Group Name',
                                        enabledBorder:
                                            const UnderlineInputBorder(),
                                        border: const UnderlineInputBorder(),
                                        hintStyle: TextStyle(
                                          fontSize: 15.toFont,
                                          fontWeight: FontWeight.normal,
                                        ),
                                      ),
                                      onTap: () {},
                                      onChanged: (val) {},
                                      controller: textController,
                                      onSubmitted: (str) {},
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () {},
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
                      child: Wrap(
                        alignment: WrapAlignment.start,
                        runAlignment: WrapAlignment.start,
                        runSpacing: 10.0,
                        spacing: 50.0,
                        children:
                            List.generate(selectedContacts!.length, (index) {
                          return DesktopCustomPersonVerticalTile(
                            title: selectedContacts![index]!.atSign,
                            subTitle: selectedContacts![index]!.atSign,
                            icon: Icons.close,
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
              ],
            ),
            widget.onPop != null
                ? Positioned(
                    top: 20,
                    left: 20,
                    child: InkWell(
                        onTap: () {
                          widget.onPop!();
                        },
                        child: const Icon(Icons.arrow_back,
                            size: 25, color: Colors.black)),
                  )
                : const SizedBox()
          ],
        ),
      ),
    );
  }
}
