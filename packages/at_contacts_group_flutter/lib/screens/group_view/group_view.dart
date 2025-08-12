// ignore_for_file: use_build_context_synchronously

import 'dart:typed_data';

// ignore: import_of_legacy_library_into_null_safe
import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/screens/contacts_screen.dart';
import 'package:at_contacts_group_flutter/screens/edit/group_edit.dart';
import 'package:at_contacts_group_flutter/services/group_service.dart';
import 'package:at_contacts_group_flutter/utils/colors.dart';
import 'package:at_contacts_group_flutter/utils/text_constants.dart';
import 'package:at_contacts_group_flutter/utils/text_styles.dart';
import 'package:at_contacts_group_flutter/widgets/custom_toast.dart';
import 'package:at_contacts_group_flutter/widgets/error_screen.dart';
import 'package:at_contacts_group_flutter/widgets/person_vertical_tile.dart';
import 'package:at_contacts_group_flutter/widgets/confirmation_dialog.dart';
import 'package:flutter/material.dart';

// ignore: import_of_legacy_library_into_null_safe
import 'package:at_common_flutter/at_common_flutter.dart';

import '../list/group_list.dart';

/// This widget shows the group details with it's members in a grid view
class GroupView extends StatefulWidget {
  final AtGroup group;

  const GroupView({Key? key, required this.group}) : super(key: key);

  @override
  _GroupViewState createState() => _GroupViewState();
}

class _GroupViewState extends State<GroupView> {
  List<AtContact> contacts = [];
  late NavigatorState _navigator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      GroupService().showLoaderSink.add(false);
    });
  }

  @override
  void didChangeDependencies() {
    _navigator = Navigator.of(context);
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.light
          ? AllColors().WHITE
          : AllColors().Black,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Stack(
            children: [
              Column(
                children: [
                  StreamBuilder(
                    stream: GroupService().groupViewStream,
                    builder: (context, AsyncSnapshot<AtGroup> snapshot) {
                      if (snapshot.connectionState == ConnectionState.active) {
                        if (snapshot.hasData) {
                          if (snapshot.data!.groupPicture != null) {
                            List<int> intList =
                                snapshot.data!.groupPicture.cast<int>();
                            var groupPicture = Uint8List.fromList(intList);

                            return Image.memory(
                              groupPicture,
                              height: 272.toHeight,
                              fit: BoxFit.fill,
                            );
                          } else {
                            return SizedBox(
                                height: 272.toHeight,
                                width: double.infinity,
                                child: Icon(Icons.groups_rounded,
                                    size: 200, color: AllColors().LIGHT_GREY));
                          }
                        } else {
                          return const SizedBox();
                        }
                      } else {
                        return SizedBox(
                            height: 272.toHeight,
                            width: double.infinity,
                            child: Icon(Icons.groups_rounded,
                                size: 200, color: AllColors().LIGHT_GREY));
                      }
                    },
                  ),
                  SizedBox(
                    height: 60.toHeight,
                  ),
                  StreamBuilder(
                    stream: GroupService().showLoaderStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.active) {
                        if (snapshot.data == true) {
                          return const CircularProgressIndicator();
                        } else {
                          return const SizedBox();
                        }
                      } else {
                        return const SizedBox();
                      }
                    },
                  ),
                  Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 15.toWidth, vertical: 0.toHeight),
                      child: StreamBuilder(
                        stream: GroupService().groupViewStream,
                        builder: (context, AsyncSnapshot<AtGroup> snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.active) {
                            if (snapshot.hasError) {
                              return ErrorScreen(
                                onPressed: () {
                                  GroupService()
                                      .updateGroupStreams(widget.group);
                                },
                              );
                            } else {
                              if (snapshot.hasData) {
                                var groupData = snapshot.data!;
                                contacts = groupData.members?.toList() ?? [];
                                return GridView.count(
                                  physics: const NeverScrollableScrollPhysics(),
                                  shrinkWrap: true,
                                  crossAxisCount: 4,
                                  childAspectRatio:
                                      ((SizeConfig().screenWidth * 0.25) /
                                          (SizeConfig().screenHeight * 0.2)),
                                  children: List.generate(
                                      groupData.members!.length, (index) {
                                    return InkWell(
                                      onTap: () {
                                        if (index < groupData.members!.length) {
                                          showMyDialog(
                                              context,
                                              groupData.members!
                                                  .elementAt(index),
                                              widget.group);
                                        } else {
                                          GroupService()
                                              .updateGroupStreams(widget.group);
                                        }
                                      },
                                      child: CustomPersonVerticalTile(
                                        key: UniqueKey(),
                                        imageLocation: null,
                                        title: groupData.members!
                                                    .elementAt(index)
                                                    .tags !=
                                                null
                                            ? groupData.members!
                                                .elementAt(index)
                                                .tags!['name']
                                            : null,
                                        subTitle: groupData.members!
                                            .elementAt(index)
                                            .atSign,
                                        isAssetImage: false,
                                        atsign: groupData.members!
                                            .elementAt(index)
                                            .atSign,
                                      ),
                                    );
                                  }),
                                );
                              } else {
                                return const SizedBox();
                              }
                            }
                          } else {
                            return const SizedBox();
                          }
                        },
                      )),
                ],
              ),
              Positioned(
                top: 240.toHeight,
                child: Container(
                  height: 80.toHeight,
                  width: SizeConfig().screenWidth * 0.92,
                  margin: EdgeInsets.symmetric(
                      horizontal: 15.toWidth, vertical: 0.toHeight),
                  padding: EdgeInsets.symmetric(
                      horizontal: 15.toWidth, vertical: 10.toHeight),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10.0),
                    color: Theme.of(context).brightness == Brightness.light
                        ? AllColors().WHITE
                        : AllColors().Black,
                    boxShadow: [
                      BoxShadow(
                        color: AllColors().DARK_GREY,
                        blurRadius: 10.0,
                        spreadRadius: 1.0,
                        offset: const Offset(0.0, 0.0),
                      )
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StreamBuilder(
                              stream: GroupService().groupViewStream,
                              builder:
                                  (context, AsyncSnapshot<AtGroup> snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.active) {
                                  var groupData = snapshot.data!;
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 250.toWidth,
                                        child: Text(
                                          groupData.displayName!,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          // softWrap: false,
                                          style: TextStyle(
                                            color: AllColors().GREY,
                                            fontSize: 16.toFont,
                                            fontWeight: FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${groupData.members!.length} members',
                                        style: CustomTextStyles().grey14,
                                      ),
                                    ],
                                  );
                                } else {
                                  return const SizedBox();
                                }
                              }),
                        ],
                      ),
                      InkWell(
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ContactsScreen(
                                asSelectionScreen: true,
                                selectedList:
                                    (List<AtContact?> selectedList) async {
                                  GroupService().selecteContactList =
                                      selectedList;
                                },
                                saveGroup: () async {
                                  if (GroupService()
                                      .selecteContactList
                                      .isNotEmpty) {
                                    GroupService().showLoaderSink.add(true);

                                    var result = await GroupService()
                                        .addGroupMembers([
                                      ...GroupService().selecteContactList
                                    ], widget.group);

                                    GroupService().showLoaderSink.add(false);
                                    if (mounted) {
                                      if (result == null) {
                                        CustomToast().show(
                                            TextConstants().SERVICE_ERROR,
                                            context);
                                      } else if (result is bool && result) {
                                        // CustomToast().show(
                                        //     TextConstants().MEMBER_ADDED,
                                        //     context);

                                      } else {
                                        CustomToast().show(
                                            TextConstants().SERVICE_ERROR,
                                            context);
                                      }
                                    }
                                  }
                                },
                              ),
                            ),
                          );
                        },
                        child: Icon(
                          Icons.add,
                          size: 30.toFont,
                        ),
                      )
                    ],
                  ),
                ),
              ),
              Positioned(
                  top: 30.toHeight,
                  left: 10.toWidth,
                  child: InkWell(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: EdgeInsets.all(5.toFont),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_back,
                        color: AllColors().Black,
                        size: 25.toFont,
                      ),
                    ),
                  )),
              Positioned(
                top: 30.toHeight,
                right: 10.toWidth,
                child: InkWell(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GroupEdit(
                          group: widget.group,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: EdgeInsets.all(5.toFont),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.edit,
                      color: AllColors().Black,
                      size: 25.toFont,
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> showMyDialog(
      BuildContext context, AtContact contact, AtGroup group) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return ConfirmationDialog(
          title: contact.atSign!,
          heading: 'Are you sure you want to remove from the group?',
          onYesPressed: () async {
            var result =
                await GroupService().deletGroupMembers([contact], widget.group);
            if (result is bool && result) {
              Navigator.of(context).pop();
              CustomToast().show(
                  "${contact.atSign ?? ''} deleted successfully!", context);
              if (contacts.isEmpty) {
                showDeleteGroupDialog(
                  context,
                  widget.group,
                  heading: "Do you want to remove this group?",
                  onDeleteSuccess: () async {
                    if (!mounted) return;

                    if (_navigator.canPop()) {
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
}
