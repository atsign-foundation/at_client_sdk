import 'dart:typed_data';
// ignore: import_of_legacy_library_into_null_safe
import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_flutter/widgets/contacts_initials.dart';
import 'package:at_contacts_flutter/widgets/custom_circle_avatar.dart';
import 'package:at_contacts_group_flutter/models/group_contacts_model.dart';
import 'package:at_contacts_group_flutter/services/group_service.dart';
import 'package:at_contacts_group_flutter/utils/colors.dart';
import 'package:at_contacts_group_flutter/utils/images.dart';
import 'package:at_utils/at_logger.dart';
import 'package:flutter/material.dart';

class CircularContacts extends StatefulWidget {
  final Function? onCrossPressed, onLongPressed, onTap;
  final bool asSelectionTile, selectSingle;
  final GroupContactsModel? groupContact;
  final IconData? actionIcon;
  final AtSignLogger atSignLogger = AtSignLogger('CircularContacts');
  final ValueChanged<List<GroupContactsModel?>>? selectedList;

  CircularContacts(
      {Key? key,
      this.onCrossPressed,
      this.onLongPressed,
      this.onTap,
      this.actionIcon,
      this.groupContact,
      this.selectSingle = false,
      this.asSelectionTile = false,
      this.selectedList})
      : super(key: key);

  @override
  _CircularContactsState createState() => _CircularContactsState();
}

class _CircularContactsState extends State<CircularContacts> {
  bool isSelected = false;
  bool isLoading = false;
  late GroupService _groupService;
  String? initials = 'UG';
  Uint8List? image;

  @override
  void initState() {
    _groupService = GroupService();
    // ignore: omit_local_variable_types
    getIsSelectedValue();

    super.initState();
  }

  getIsSelectedValue() {
    isSelected = false;
    for (GroupContactsModel? el in _groupService.selectedGroupContacts) {
      if (el!.contact != null &&
          widget.groupContact!.contact != null &&
          el.contact!.atSign == widget.groupContact!.contact!.atSign) {
        isSelected = true;
      } else if (el.group != null &&
          widget.groupContact!.group != null &&
          el.group!.groupId == widget.groupContact!.group!.groupId) {
        isSelected = true;
      }
    }
  }

  getNameAndImage() {
    try {
      if (widget.groupContact?.contact != null) {
        initials = widget.groupContact?.contact?.atSign;
        if ((initials?[0] ?? 'not@') == '@') {
          initials = initials?.substring(1);
        }

        if (widget.groupContact?.contact?.tags != null &&
            widget.groupContact?.contact?.tags!['image'] != null) {
          List<int> intList =
              widget.groupContact?.contact?.tags!['image'].cast<int>();
          image = Uint8List.fromList(intList);
        }
      } else {
        if (widget.groupContact?.group?.groupPicture != null) {
          image = Uint8List.fromList(
              widget.groupContact?.group?.groupPicture?.cast<int>());
        }

        initials = widget.groupContact?.group?.displayName;
      }
    } catch (e) {
      initials = 'UG';
      widget.atSignLogger.info('Error in getting image $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    getNameAndImage();

    return StreamBuilder<List<GroupContactsModel?>>(
        initialData: _groupService.selectedGroupContacts,
        stream: _groupService.selectedContactsStream,
        builder: (context, snapshot) {
          getIsSelectedValue();
          return GestureDetector(
            onTap: () {
              if (widget.asSelectionTile) {
                if (widget.selectSingle) {
                  _groupService.selectedGroupContacts = [];
                  _groupService.addGroupContact(widget.groupContact);
                  widget.selectedList!([widget.groupContact]);
                  Navigator.pop(context);
                } else if (!widget.selectSingle) {
                  if (mounted) {
                    setState(() {
                      if (isSelected) {
                        _groupService.removeGroupContact(widget.groupContact);
                      } else {
                        _groupService.addGroupContact(widget.groupContact);
                      }
                      isSelected = !isSelected;
                    });
                  }
                }
              } else {
                widget.onTap!();
              }
            },
            onLongPress: widget.onLongPressed as void Function()?,
            child: Container(
              padding: EdgeInsets.symmetric(
                  vertical: 10.toHeight, horizontal: 10.toWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    alignment: AlignmentDirectional.topCenter,
                    children: [
                      SizedBox(
                        height: 50.toHeight,
                        width: 50.toHeight,
                        child: (image != null)
                            ? CustomCircleAvatar(
                                byteImage: image,
                                nonAsset: true,
                              )
                            : ContactInitial(
                                initials: (initials ?? 'UG'),
                              ),
                        // child:
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: GestureDetector(
                            onTap: (widget.asSelectionTile == false &&
                                    widget.onCrossPressed != null)
                                ? widget.onCrossPressed as void Function()?
                                : selectRemoveContact(),
                            child: (widget.asSelectionTile)
                                ? Container(
                                    height: 15.toHeight,
                                    width: 15.toHeight,
                                    decoration: const BoxDecoration(
                                        color: Colors.black,
                                        shape: BoxShape.circle),
                                    child: Icon(
                                      (isSelected) ? Icons.close : Icons.add,
                                      size: 15.toHeight,
                                      color: Colors.white,
                                    ))
                                : Container(
                                    height: 15.toHeight,
                                    width: 15.toHeight,
                                    decoration: const BoxDecoration(
                                        color: Colors.transparent,
                                        shape: BoxShape.circle),
                                    child: Image.asset(
                                      AllImages().SEND,
                                      width: 20.toWidth,
                                      height: 18.toHeight,
                                      package: 'at_contacts_group_flutter',
                                    ),
                                  )),
                      ),
                    ],
                  ),
                  Tooltip(
                    triggerMode: TooltipTriggerMode.tap,
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                        color: AllColors().GREY,
                        borderRadius: BorderRadius.circular(8)),
                    textStyle: TextStyle(color: AllColors().WHITE),
                    message:
                        '${widget.groupContact?.contact?.tags != null && widget.groupContact?.contact?.tags!['name'] != null ? widget.groupContact?.contact?.tags!['name'] : (widget.groupContact?.contact?.atSign?.substring(1) ?? widget.groupContact?.group?.groupName?.substring(0))!}\n${(widget.groupContact?.contact?.atSign ?? widget.groupContact?.group?.groupName)!}',
                    child: SizedBox(
                        child: Column(children: [
                      SizedBox(height: 10.toHeight),
                      SizedBox(
                        width: 80.toWidth,
                        child: Text(
                          widget.groupContact?.contact?.tags != null &&
                                  widget.groupContact?.contact?.tags!['name'] !=
                                      null
                              ? widget.groupContact?.contact?.tags!['name']
                              : (widget.groupContact?.contact?.atSign
                                      ?.substring(1) ??
                                  widget.groupContact?.group?.groupName
                                      ?.substring(0))!,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AllColors().Black,
                            fontSize: 14.toFont,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ),
                      SizedBox(height: 10.toHeight),
                      SizedBox(
                        width: 60.toWidth,
                        child: Text(
                          (widget.groupContact?.contact?.atSign ??
                              widget.groupContact?.group?.groupName)!,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AllColors().FADED_TEXT,
                            fontSize: 14.toFont,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ),
                    ])),
                  )
                ],
              ),
            ),
          );
        });
  }

  // ignore: always_declare_return_types
  selectRemoveContact() {}
}
