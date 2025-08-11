import 'dart:typed_data';

import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/utils/colors.dart';
import 'package:at_contacts_group_flutter/desktop_routes/desktop_route_names.dart';
import 'package:at_contacts_group_flutter/desktop_routes/desktop_routes.dart';
import 'package:at_contacts_group_flutter/models/group_contacts_model.dart';
import 'package:at_contacts_group_flutter/services/group_service.dart';
import 'package:at_contacts_group_flutter/services/navigation_service.dart';
import 'package:at_contacts_group_flutter/utils/text_constants.dart';
import 'package:at_contacts_group_flutter/widgets/confirmation_dialog.dart';
import 'package:at_contacts_group_flutter/widgets/custom_toast.dart';
import 'package:at_contacts_group_flutter/widgets/desktop_custom_input_field.dart';
import 'package:at_contacts_group_flutter/widgets/desktop_header.dart';
import 'package:at_contacts_group_flutter/widgets/desktop_person_horizontal_tile.dart';
import 'package:flutter/material.dart';

class DesktopGroupList extends StatefulWidget {
  final List<AtGroup> groups;
  final int expandIndex;
  final bool showBackButton;

  const DesktopGroupList(this.groups,
      {Key? key, this.expandIndex = 0, this.showBackButton = true})
      : super(key: key);
  @override
  _DesktopGroupListState createState() => _DesktopGroupListState();
}

class _DesktopGroupListState extends State<DesktopGroupList> {
  int _selectedIndex = 0;
  String searchText = '';
  var _filteredList = <AtGroup>[];
  bool showBackIcon = true;

  @override
  void initState() {
    _selectedIndex = widget.expandIndex;
    showBackIcon = GroupService().groupPreferece.showBackButton;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (searchText != '') {
      _filteredList = widget.groups.where((grp) {
        return grp.groupName!.contains(searchText);
      }).toList();
    } else {
      _filteredList = widget.groups;
    }

    return Container(
      color: const Color(0xFFF7F7FF),
      child: Column(
        children: <Widget>[
          const SizedBox(
            height: 10,
          ),
          DesktopHeader(
            title: 'Groups',
            isTitleCentered: false,
            showBackIcon: showBackIcon,
            onBackTap: () {
              DesktopGroupSetupRoutes.exitGroupPackage();
            },
            actions: [
              Expanded(
                child: DesktopCustomInputField(
                  backgroundColor: Colors.white,
                  hintText: 'Search...',
                  icon: Icons.search,
                  height: 45,
                  iconColor: ColorConstants.greyText,
                  value: (str) {
                    setState(() {
                      searchText = str;
                    });
                  },
                  initialValue: searchText,
                ),
              ),
              const SizedBox(width: 15),
              TextButton(
                onPressed: () {
                  Navigator.of(
                          NavService.groupPckgRightHalfNavKey.currentContext!)
                      .pushNamed(DesktopRoutes.DESKTOP_GROUP_CONTACT_VIEW,
                          arguments: {
                        'onBackArrowTap': (selectedGroupContacts) {
                          Navigator.of(NavService
                                  .groupPckgRightHalfNavKey.currentContext!)
                              .pop();
                        },
                        'onDoneTap': () {
                          Navigator.of(NavService
                                  .groupPckgRightHalfNavKey.currentContext!)
                              .pushNamed(DesktopRoutes.DESKTOP_NEW_GROUP,
                                  arguments: {
                                'onPop': () {
                                  Navigator.of(NavService
                                          .groupPckgRightHalfNavKey
                                          .currentContext!)
                                      .pop();
                                },
                                'onDone': () {},
                              });
                        },
                        'contactSelectedHistory':
                            <GroupContactsModel>[] // will always be empty
                      });
                },
                style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith<Color>(
                  (Set<WidgetState> states) {
                    return ColorConstants.orangeColor;
                  },
                ), fixedSize: WidgetStateProperty.resolveWith<Size>(
                  (Set<WidgetState> states) {
                    return const Size(100, 40);
                  },
                )),
                child: const Text(
                  'Add',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              const SizedBox(width: 10)
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredList.length,
              itemBuilder: (context, index) {
                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedIndex = index;
                    });
                    DesktopGroupSetupRoutes.navigator(
                        DesktopRoutes.DESKTOP_GROUP_DETAIL,
                        arguments: {
                          'group': _filteredList[index],
                          'currentIndex': index,
                        })();
                  },
                  child: Container(
                    color: index == _selectedIndex
                        ? const Color(0xffF86060).withAlpha(20)
                        : Colors.transparent,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            top: 8.0,
                            right: 15,
                            left: 20,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(
                                top: 15.0, bottom: 15, left: 15, right: 15),
                            child: DesktopCustomPersonHorizontalTile(
                              title: _filteredList[index].groupName,
                              image: _filteredList[index].groupPicture,
                              subTitle: _filteredList[index]
                                  .members!
                                  .length
                                  .toString(),
                              isDesktop: true,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Padding(
                                  padding: const EdgeInsets.only(right: 15.0),
                                  child: InkWell(
                                    onTap: () {
                                      showMyDialog(
                                          context, _filteredList[index]);
                                    },
                                    child: const Icon(Icons.delete),
                                  )),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  Future<void> showMyDialog(BuildContext context, AtGroup group) async {
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
          heading: 'Are you sure you want to delete this group?',
          onYesPressed: () async {
            var result = await GroupService().deleteGroup(group);

            if(!context.mounted) return;
            if (result != null && result) {
              Navigator.of(context).pop();
            } else {
              CustomToast().show(TextConstants().SERVICE_ERROR, context);
            }
          },
          image: groupPicture,
        );
      },
    );
  }
}
