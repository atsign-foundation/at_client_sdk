// ignore_for_file: use_build_context_synchronously

import 'dart:typed_data';

// ignore: import_of_legacy_library_into_null_safe
import 'package:at_contact/at_contact.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_flutter/screens/contacts_screen.dart';
import 'package:at_contacts_flutter/utils/colors.dart';
import 'package:at_contacts_group_flutter/at_contacts_group_flutter.dart';
import 'package:at_contacts_group_flutter/screens/group_view/group_view.dart';
import 'package:at_contacts_group_flutter/screens/new_group/new_group.dart';
import 'package:at_contacts_group_flutter/services/group_service.dart';
import 'package:at_contacts_group_flutter/utils/colors.dart';
import 'package:at_contacts_group_flutter/utils/text_constants.dart';
import 'package:at_contacts_group_flutter/widgets/circular_group_contact.dart';
import 'package:at_contacts_group_flutter/widgets/custom_toast.dart';
import 'package:at_contacts_group_flutter/widgets/error_screen.dart';
import 'package:at_contacts_group_flutter/widgets/person_horizontal_tile.dart';
import 'package:at_contacts_group_flutter/widgets/confirmation_dialog.dart';
import 'package:at_utils/at_logger.dart';
import 'package:flutter/material.dart';

/// [GroupList] shows all the created groups.
///
/// If no group is present, an empty screen is shows.
///
/// [GroupList] also provides an option to create a new group.
class GroupList extends StatefulWidget {
  const GroupList({Key? key}) : super(key: key);
  @override
  _GroupListState createState() => _GroupListState();
}

class _GroupListState extends State<GroupList> {
  List<AtContact?> selectedContactList = [];
  bool showAddGroupIcon = false, errorOcurred = false, toggleList = false;
  AtSignLogger atSignLogger = AtSignLogger('GroupList');
  @override
  void initState() {
    try {
      super.initState();
      GroupService().getAllGroupsDetails();
      GroupService().atGroupStream.listen((groupList) {
        if (groupList.isNotEmpty) {
          showAddGroupIcon = true;
        } else {
          showAddGroupIcon = false;
        }
        if (mounted) setState(() {});
      });
    } catch (e) {
      atSignLogger.severe('Error in init of Group_list $e');
      if (mounted) {
        setState(() {
          errorOcurred = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.light
          ? AllColors().WHITE
          : AllColors().Black,
      appBar: CustomAppBar(
        showBackButton: true,
        showLeadingIcon: true,
        showTitle: true,
        titleText: 'Groups',
        showTrailingIcon: showAddGroupIcon,
        trailingIcon: Icon(
          Icons.add,
          color: AllColors().ORANGE,
          size: 20.toFont,
        ),
        onTrailingIconPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ContactsScreen(
              asSelectionScreen: true,
              selectedList: (selectedList) {
                selectedContactList = selectedList;
                if (selectedContactList.isNotEmpty) {
                  GroupService().setSelectedContacts(selectedContactList);
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
        ),
      ),
      body: SafeArea(
        child: errorOcurred
            ? const ErrorScreen()
            : Column(
                children: [
                  Container(
                    padding: EdgeInsets.only(right: 20.toWidth),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Icon(
                          Icons.view_module,
                          color: ColorConstants.greyText,
                        ),
                        Switch(
                            value: toggleList,
                            activeColor: Colors.white,
                            activeTrackColor:
                                ColorConstants.fadedGreyBackground,
                            onChanged: (s) {
                              setState(() {
                                toggleList = !toggleList;
                              });
                            }),
                        const Icon(Icons.view_list,
                            color: ColorConstants.greyText),
                      ],
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder(
                      stream: GroupService().atGroupStream,
                      builder: (BuildContext context,
                          AsyncSnapshot<List<AtGroup>> snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        } else {
                          if (snapshot.hasError) {
                            return ErrorScreen(onPressed: () {
                              GroupService().getAllGroupsDetails();
                            });
                          } else {
                            if (snapshot.hasData) {
                              if (snapshot.data!.isEmpty) {
                                showAddGroupIcon = false;

                                return const EmptyGroup();
                              } else {
                                return toggleList
                                    ? ListView.separated(
                                        padding: const EdgeInsets.all(20.0),
                                        itemCount: snapshot.data!.length,
                                        separatorBuilder: (context, index) =>
                                            Divider(
                                          color: Colors.transparent,
                                          indent: 16.toWidth,
                                        ),
                                        itemBuilder: (context, index) {
                                          return Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: InkWell(
                                              onLongPress: () {
                                                showDeleteGroupDialog(context,
                                                    snapshot.data![index]);
                                              },
                                              onTap: () async {
                                                WidgetsBinding.instance
                                                    .addPostFrameCallback(
                                                        (_) async {
                                                  GroupService()
                                                      .groupViewSink
                                                      .add(snapshot
                                                          .data![index]);
                                                });

                                                await Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                      builder: (context) =>
                                                          GroupView(
                                                              group: snapshot
                                                                      .data![
                                                                  index])),
                                                );
                                              },
                                              child: CustomPersonHorizontalTile(
                                                image: (snapshot.data![index]
                                                            .groupPicture !=
                                                        null)
                                                    ? snapshot.data![index]
                                                        .groupPicture
                                                    : null,
                                                title: snapshot.data![index]
                                                        .displayName ??
                                                    ' ',
                                                subTitle: snapshot.data![index]
                                                            .members!.length ==
                                                        1
                                                    ? '${snapshot.data![index].members!.length} member'
                                                    : '${snapshot.data![index].members!.length} members',
                                              ),
                                            ),
                                          );
                                        },
                                      )
                                    : GridView.builder(
                                        physics:
                                            const AlwaysScrollableScrollPhysics(),
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                                crossAxisCount: SizeConfig()
                                                        .isTablet(context)
                                                    ? 5
                                                    : 3,
                                                childAspectRatio: 1 /
                                                    (SizeConfig()
                                                            .isTablet(context)
                                                        ? 1.2
                                                        : 1.1)),
                                        shrinkWrap: true,
                                        itemCount: snapshot.data!.length,
                                        itemBuilder: (context, index) {
                                          return InkWell(
                                            onLongPress: () {
                                              showDeleteGroupDialog(context,
                                                  snapshot.data![index]);
                                            },
                                            onTap: () async {
                                              WidgetsBinding.instance
                                                  .addPostFrameCallback(
                                                      (_) async {
                                                GroupService()
                                                    .groupViewSink
                                                    .add(snapshot.data![index]);
                                              });

                                              await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                    builder: (context) =>
                                                        GroupView(
                                                            group: snapshot
                                                                .data![index])),
                                              );
                                            },
                                            child: CircularGroupContact(
                                              image: (snapshot.data![index]
                                                          .groupPicture !=
                                                      null)
                                                  ? snapshot
                                                      .data![index].groupPicture
                                                  : null,
                                              title: snapshot.data![index]
                                                      .displayName ??
                                                  ' ',
                                              subTitle: snapshot.data![index]
                                                          .members!.length ==
                                                      1
                                                  ? '${snapshot.data![index].members!.length} member'
                                                  : '${snapshot.data![index].members!.length} members',
                                            ),
                                          );
                                        },
                                      );
                              }
                            } else {
                              return const EmptyGroup();
                            }
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

Future<void> showDeleteGroupDialog(
  BuildContext context,
  AtGroup group, {
  String? heading,
  Function? onDeleteSuccess,
}) async {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) {
      Uint8List? groupPicture;
      if (group.groupPicture != null) {
        List<int> intList = group.groupPicture.cast<int>();
        groupPicture = Uint8List.fromList(intList);
      }
      return ConfirmationDialog(
        title: '${group.displayName}',
        heading: heading ?? 'Are you sure you want to delete this group?',
        onYesPressed: () async {
          var result = await GroupService().deleteGroup(group);

          if (result is bool && result) {
            Navigator.of(context).pop();
            onDeleteSuccess?.call();
          } else {
            CustomToast().show(TextConstants().SERVICE_ERROR, context);
          }
        },
        image: groupPicture,
      );
    },
  );
}
