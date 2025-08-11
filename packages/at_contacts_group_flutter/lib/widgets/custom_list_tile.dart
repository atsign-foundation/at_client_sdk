import 'dart:developer';
import 'dart:typed_data';

// ignore: import_of_legacy_library_into_null_safe
import 'package:at_common_flutter/at_common_flutter.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/widgets/contacts_initials.dart';
import 'package:at_contacts_flutter/widgets/custom_circle_avatar.dart';
import 'package:at_contacts_group_flutter/models/group_contacts_model.dart';
import 'package:at_contacts_group_flutter/services/group_service.dart';
import 'package:at_contacts_group_flutter/utils/colors.dart';
import 'package:at_contacts_group_flutter/utils/images.dart';
import 'package:at_utils/at_logger.dart';
import 'package:flutter/material.dart';

/// A custom list tile to display the contacts
/// takes in a function @param [onTap] to define what happens on tap of the tile
/// @param [onTrailingPresses] to set the behaviour for trailing icon
/// @param [asSelectionTile] to toggle whether the tile is selectable to select contacts
/// @param [contact] for details of the contact
/// @param [contactService] to get an instance of [AtContactsImpl]
class CustomListTile extends StatefulWidget {
  final Function? onTap;
  final Function? onTrailingPressed;
  final bool asSelectionTile;
  final GroupContactsModel? item;
  final bool selectSingle;
  final ValueChanged<List<GroupContactsModel?>>? selectedList;

  const CustomListTile({
    Key? key,
    this.onTap,
    this.onTrailingPressed,
    this.asSelectionTile = false,
    this.item,
    this.selectSingle = false,
    this.selectedList,
  }) : super(key: key);
  @override
  _CustomListTileState createState() => _CustomListTileState();
}

class _CustomListTileState extends State<CustomListTile> {
  bool isSelected = false;
  bool isLoading = false;
  late GroupService _groupService;
  AtContact? localContact;
  AtGroup? localGroup;
  AtSignLogger atSignLogger = AtSignLogger('CustomListTile');
  String? initials = 'UG';
  Uint8List? image;

  @override
  void initState() {
    _groupService = GroupService();
    // ignore: omit_local_variable_types

    getIsSelectedValue(_groupService.selectedGroupContacts);
    super.initState();
  }

  getIsSelectedValue(List<GroupContactsModel?> selectedGroupContacts) {
    isSelected = false;
    for (GroupContactsModel? groupContact in selectedGroupContacts) {
      if (groupContact!.contact != null &&
          widget.item!.contact != null &&
          groupContact.contact!.atSign == widget.item!.contact!.atSign) {
        isSelected = true;
      } else if (groupContact.group != null &&
          widget.item!.group != null &&
          groupContact.group!.groupId == widget.item!.group!.groupId) {
        isSelected = true;
      }
    }
  }

  getNameAndImage() {
    try {
      if (widget.item?.contact != null) {
        initials = widget.item?.contact?.atSign;
        if ((initials?[0] ?? 'not@') == '@') {
          initials = initials?.substring(1);
        }

        if (widget.item?.contact?.tags != null && widget.item?.contact?.tags!['image'] != null) {
          List<int> intList = widget.item?.contact?.tags!['image'].cast<int>();
          image = Uint8List.fromList(intList);
        }
      } else {
        if (widget.item?.group?.groupPicture != null) {
          image = Uint8List.fromList(widget.item?.group?.groupPicture?.cast<int>());
        }

        initials = widget.item?.group?.displayName;
      }
    } catch (e) {
      initials = 'UG';
      log('Error in getting image $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    getNameAndImage();

    return StreamBuilder<List<GroupContactsModel?>>(
        initialData: _groupService.selectedGroupContacts,
        stream: _groupService.selectedContactsStream,
        builder: (context, snapshot) {
          getIsSelectedValue(_groupService.selectedGroupContacts);

          return ListTile(
            onTap: () {
              if (widget.asSelectionTile) {
                if (widget.selectSingle) {
                  _groupService.selectedGroupContacts = [];
                  _groupService.addGroupContact(widget.item);
                  widget.selectedList!([widget.item]);
                  Navigator.pop(context);
                } else if (!widget.selectSingle) {
                  if (mounted) {
                    setState(() {
                      if (isSelected) {
                        _groupService.removeGroupContact(widget.item);
                      } else {
                        _groupService.addGroupContact(widget.item);
                      }
                      isSelected = !isSelected;
                    });
                  }
                }
              } else {
                widget.onTap!();
              }
            },
            title: Text(
              widget.item!.contact == null
                  // ignore: prefer_if_null_operators
                  ? widget.item!.group!.displayName == null
                      ? widget.item!.group!.groupName
                      : widget.item!.group!.displayName
                  // ignore: prefer_if_null_operators
                  : widget.item!.contact!.tags!['name'] == null
                      ? widget.item!.contact!.atSign!.substring(1)
                      : widget.item!.contact!.tags!['name'],
              style: TextStyle(
                color: Colors.black,
                fontSize: 14.toFont,
                fontWeight: FontWeight.normal,
              ),
            ),
            subtitle: Text(
              widget.item?.contact?.atSign ?? '${widget.item?.group?.members?.length} Members',
              style: TextStyle(
                color: AllColors().FADED_TEXT,
                fontSize: 14.toFont,
                fontWeight: FontWeight.normal,
              ),
            ),
            leading: Container(
                height: 40.toHeight,
                width: 40.toHeight,
                decoration: const BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                ),
                child: (isLoading)
                    ? const CircularProgressIndicator()
                    : (image != null)
                        ? CustomCircleAvatar(
                            byteImage: image,
                            nonAsset: true,
                          )
                        : ContactInitial(
                            initials: (initials ?? 'UG'),
                          )),
            trailing: IconButton(
              onPressed: (widget.asSelectionTile == false && widget.onTrailingPressed != null)
                  ? widget.onTrailingPressed as void Function()?
                  : selectRemoveContact(),
              icon: (widget.asSelectionTile)
                  ? (isSelected)
                      ? const Icon(
                          Icons.cancel_rounded,
                          size: 26.0,
                          color: Colors.red,
                        )
                      : const Icon(Icons.add, size: 24.0, color: Colors.green)
                  : Image.asset(
                      AllImages().SEND,
                      width: 21.toWidth,
                      height: 18.toHeight,
                      package: 'at_contacts_group_flutter',
                    ),
            ),
          );
        });
  }

  // ignore: always_declare_return_types
  selectRemoveContact() {}
}
