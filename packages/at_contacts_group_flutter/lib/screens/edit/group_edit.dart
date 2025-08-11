// ignore_for_file: use_build_context_synchronously

import 'dart:typed_data';

import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/screens/contacts_screen.dart';
import 'package:at_contacts_group_flutter/screens/edit/person_horizontal.dart';
import 'package:at_contacts_group_flutter/services/group_service.dart';
import 'package:at_contacts_group_flutter/services/image_picker.dart';
import 'package:at_contacts_group_flutter/utils/colors.dart';
import 'package:at_contacts_group_flutter/utils/text_constants.dart';
import 'package:at_contacts_group_flutter/utils/text_styles.dart';
import 'package:at_contacts_group_flutter/widgets/confirmation_dialog.dart';
import 'package:at_contacts_group_flutter/widgets/custom_toast.dart';
import 'package:at_contacts_group_flutter/widgets/yes_no_dialog.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

import '../../widgets/error_screen.dart';
import '../list/group_list.dart';

/// Screen to edit group details
class GroupEdit extends StatefulWidget {
  final AtGroup group;

  const GroupEdit({Key? key, required this.group}) : super(key: key);

  @override
  _GroupEditState createState() => _GroupEditState();
}

class _GroupEditState extends State<GroupEdit> {
  /// Name of the group
  String? groupName;

  /// Boolean flag to indicate loading status
  late bool isLoading;

  /// Profile picture for the group
  Uint8List? groupPicture;

  /// Boolean flag to check for keyboard visibility
  bool isKeyBoardVisible = false,

      /// Boolean to control emoji picker
      showEmojiPicker = false;

  /// Text controller for text field to input group name
  late TextEditingController textController;

  /// Focus node for text field
  FocusNode textFieldFocus = FocusNode();

  List<AtContact> contacts = [];

  bool _updateImage = false;

  late NavigatorState _navigator;

  @override
  void initState() {
    super.initState();
    isLoading = false;
    // ignore: unnecessary_null_comparison
    if (widget.group != null) groupName = widget.group.displayName;

    textController = TextEditingController.fromValue(
      TextEditingValue(
        text: groupName != null ? groupName! : '',
        selection: const TextSelection.collapsed(offset: -1),
      ),
    );

    if (widget.group.groupPicture != null) {
      List<int> intList = widget.group.groupPicture.cast<int>();
      groupPicture = Uint8List.fromList(intList);
    }

    WidgetsBinding.instance.addPostFrameCallback(
      (_) async {
        GroupService().groupViewSink.add(widget.group);
      },
    );
  }

  @override
  void didChangeDependencies() {
    _navigator = Navigator.of(context);
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: CustomAppBar(
        showLeadingIcon: true,
        leadingIcon: Center(
          child: Container(
            padding: const EdgeInsets.only(left: 10),
            child: GestureDetector(
              onTap: () {
                if (_updateImage || (textController.text != groupName)) {
                  shownConfirmationDialog(
                    context,
                    'Do you want to save your changes?',
                    () {
                      onDone();
                    },
                    onNoTap: () {
                      Navigator.pop(context);
                    },
                  );
                } else {
                  Navigator.pop(context);
                }
              },
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.light ? AllColors().Black : AllColors().Black,
                  fontSize: 14.toFont,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
        showTrailingIcon: true,
        showTitle: false,
        titleText: '',
        trailingIcon: isLoading
            ? Center(
                child: SizedBox(
                  width: 20.toHeight,
                  height: 20.toHeight,
                  child: const CircularProgressIndicator(),
                ),
              )
            : Text('Done',
                style: TextStyle(
                  color: AllColors().ORANGE,
                  fontSize: 15.toFont,
                  fontWeight: FontWeight.normal,
                )),
        onTrailingIconPressed: () {
          onDone();
        },
      ),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                (groupPicture != null)
                    ? Image.memory(
                        groupPicture!,
                        height: 272.toHeight,
                        fit: BoxFit.fill,
                      )
                    : SizedBox(
                        height: 272.toHeight,
                        width: double.infinity,
                        child: Icon(
                          Icons.groups_rounded,
                          size: 200,
                          color: AllColors().LIGHT_GREY,
                        ),
                      ),
                const Divider(height: 1),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 27.toWidth,
                    vertical: 15.toHeight,
                  ),
                  child: InkWell(
                    onTap: () => bottomSheetContent(
                      context,
                      119.toHeight,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Text(
                          'Edit group picture',
                          style: CustomTextStyles().orange12,
                        ),
                        SizedBox(
                          width: 5.toWidth,
                        ),
                        Icon(
                          Icons.edit,
                          color: AllColors().ORANGE,
                          size: 20.toFont,
                        )
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 27.toWidth, vertical: 2.toHeight),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Group Name',
                          style: CustomTextStyles().grey16,
                          textAlign: TextAlign.left,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 27.toWidth, vertical: 2.toHeight),
                  child: Container(
                    width: double.infinity,
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
                          child: const Icon(
                            Icons.emoji_emotions_outlined,
                            color: Colors.grey,
                          ),
                        )
                      ],
                    ),
                  ),
                ),
                _buildHeaderListMember,
                _buildListMember,
              ],
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: showEmojiPicker
                  ? Stack(children: [
                      SizedBox(
                        height: 250,
                        child: EmojiPicker(
                          key: UniqueKey(),
                          config: const Config(
                            emojiViewConfig: EmojiViewConfig(
                              columns: 7,
                              emojiSizeMax: 32.0,
                              noRecents: Text(
                                "No Recents",
                                style: TextStyle(
                                  fontSize: 20,
                                  color: Colors.black26,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ),
                            categoryViewConfig: CategoryViewConfig(
                              backgroundColor: Color(0xFFF2F2F2),
                            ),
                          ),
                          onEmojiSelected: (category, emoji) {
                            textController.text += emoji.emoji;
                          },
                        ),
                      ),
                    ])
                  : const SizedBox(),
            )
          ],
        ),
      ),
    );
  }

  Widget get _buildHeaderListMember {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 27.toWidth,
        vertical: 8.toHeight,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              "Members",
              style: CustomTextStyles().primaryBold18,
            ),
          ),
          InkWell(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ContactsScreen(
                    asSelectionScreen: true,
                    selectedList: (List<AtContact?> selectedList) async {
                      GroupService().selecteContactList = selectedList;
                    },
                    saveGroup: () async {
                      if (GroupService().selecteContactList.isNotEmpty) {
                        GroupService().showLoaderSink.add(true);

                        var result =
                            await GroupService().addGroupMembers([...GroupService().selecteContactList], widget.group);

                        GroupService().showLoaderSink.add(false);
                        if (!mounted) return;
                        if (result is bool && result) {
                          return;
                        } else if (result == null) {
                          CustomToast().show(TextConstants().SERVICE_ERROR, context);
                        } else {
                          CustomToast().show(TextConstants().SERVICE_ERROR, context);
                        }
                      }
                    },
                  ),
                ),
              );
            },
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.add,
                ),
                SizedBox(
                  width: 4.toWidth,
                ),
                Text(
                  "Add",
                  style: CustomTextStyles().grey14,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 12.toWidth,
          ),
          StreamBuilder(
            stream: GroupService().groupViewStream,
            builder: (context, AsyncSnapshot<AtGroup> snapshot) {
              if (snapshot.connectionState == ConnectionState.active) {
                if (snapshot.hasData) {
                  contacts = snapshot.data!.members?.toList() ?? [];
                  return Visibility(
                    visible: contacts.isNotEmpty,
                    child: InkWell(
                      onTap: () {
                        shownConfirmationDialog(
                          context,
                          'Are you sure you want to remove all members from the group?',
                          () async {
                            var result = await GroupService().deletGroupMembers(contacts, widget.group);

                            if (result == null) {
                              CustomToast().show(TextConstants().SERVICE_ERROR, context);
                            } else {
                              CustomToast().show("Deleted all members successfully!", context);

                              showDeleteGroupDialog(
                                context,
                                widget.group,
                                heading: "Do you want to remove this group?",
                                onDeleteSuccess: () {
                                  if (_navigator.canPop()) {
                                    _navigator.pop();
                                    _navigator.pop();
                                    GroupService().fetchGroupsAndContacts();
                                  }
                                },
                              );
                            }
                          },
                        );
                      },
                      child: Row(
                        children: <Widget>[
                          const Icon(
                            Icons.delete_forever,
                          ),
                          SizedBox(
                            width: 4.toWidth,
                          ),
                          Text(
                            "Delete all",
                            style: CustomTextStyles().grey14,
                          ),
                        ],
                      ),
                    ),
                  );
                } else {
                  return const SizedBox();
                }
              } else {
                return const SizedBox();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget get _buildListMember {
    return Expanded(
      child: StreamBuilder(
        stream: GroupService().groupViewStream,
        builder: (context, AsyncSnapshot<AtGroup> snapshot) {
          if (snapshot.connectionState == ConnectionState.active) {
            if (snapshot.hasError) {
              return ErrorScreen(
                onPressed: () {
                  GroupService().updateGroupStreams(widget.group);
                },
              );
            } else {
              if (snapshot.hasData) {
                var groupData = snapshot.data!;
                contacts = groupData.members?.toList() ?? [];
                return ListView.separated(
                  padding: EdgeInsets.symmetric(horizontal: 27.toWidth),
                  itemCount: groupData.members?.length ?? 0,
                  separatorBuilder: (context, index) {
                    return SizedBox(height: 10.toHeight);
                  },
                  itemBuilder: (context, index) {
                    return PersonHorizontal(
                      atsign: groupData.members!.elementAt(index).atSign,
                      title: groupData.members!.elementAt(index).tags != null
                          ? groupData.members!.elementAt(index).tags!['name']
                          : null,
                      subTitle: groupData.members!.elementAt(index).atSign,
                      onDelete: () async {
                        await showMyDialog(context, groupData.members!.elementAt(index), widget.group);
                      },
                    );
                  },
                );
              } else {
                return ErrorScreen(
                  msg: "Empty data!",
                  onPressed: () {
                    GroupService().updateGroupStreams(widget.group);
                  },
                );
              }
            }
          } else {
            return const SizedBox();
          }
        },
      ),
    );
  }

  void bottomSheetContent(BuildContext context, double height) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const StadiumBorder(),
      builder: (BuildContext context) {
        return Container(
          height: 119.toHeight,
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.light ? AllColors().WHITE : AllColors().Black,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12.0),
              topRight: Radius.circular(12.0),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                InkWell(
                  onTap: () async {
                    var image = await ImagePicker().pickImage();
                    if (image != null) {
                      setState(() {
                        groupPicture = image;
                        _updateImage = true;
                      });
                    }
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'Change Group Photo',
                    style: CustomTextStyles().grey16,
                  ),
                ),
                const Divider(),
                InkWell(
                  onTap: () {
                    setState(() {
                      groupPicture = null;
                    });
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'Remove Group Photo',
                    style: CustomTextStyles().grey16,
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> showMyDialog(BuildContext context, AtContact contact, AtGroup group) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return ConfirmationDialog(
          title: contact.atSign!,
          heading: 'Are you sure you want to remove from the group?',
          onYesPressed: () async {
            var result = await GroupService().deletGroupMembers([contact], widget.group);

            if (result is bool && result) {
              Navigator.of(context).pop();
              CustomToast().show("${contact.atSign ?? ''} deleted successfully!", context);
              if (contacts.isEmpty) {
                showDeleteGroupDialog(
                  context,
                  widget.group,
                  heading: "Do you want to remove this group?",
                  onDeleteSuccess: () async {
                    if (_navigator.canPop()) {
                      _navigator.pop();
                      _navigator.pop();
                      GroupService().fetchGroupsAndContacts();
                    }
                  },
                );
              }
            } else if (result == null) {
              CustomToast().show(TextConstants().SERVICE_ERROR, context);
            } else {
              CustomToast().show(result.toString(), context);
            }
          },
          atsign: contact.atSign,
        );
      },
    );
  }

  void onDone() async {
    groupName = textController.text;
    if (groupName != null) {
      if (groupName!.trim().isNotEmpty) {
        var group = widget.group;
        group.displayName = groupName!;
        group.groupName = groupName!;
        group.groupPicture = groupPicture;
        setState(() {
          isLoading = true;
        });

        await GroupService().updateGroupData(group, context);
      } else {
        CustomToast().show(TextConstants().INVALID_NAME, context);
      }
    } else {
      CustomToast().show(TextConstants().INVALID_NAME, context);
    }

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }
}
