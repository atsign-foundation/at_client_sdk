import 'dart:typed_data';
import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/utils/init_contacts_service.dart';
import 'package:at_contacts_flutter/widgets/contacts_initials.dart';
import 'package:at_contacts_group_flutter/utils/text_styles.dart';
import 'package:at_contacts_group_flutter/widgets/custom_circle_avatar.dart';
import 'package:flutter/material.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:at_common_flutter/services/size_config.dart';

class DesktopCustomPersonVerticalTile extends StatefulWidget {
  final String? imageLocation, title, subTitle, atsign;
  final bool isTopRight, isAssetImage;
  final IconData? icon;
  final Function? onCrossPressed;
  final List<dynamic>? imageByteList;

  const DesktopCustomPersonVerticalTile({
    Key? key,
    this.imageLocation,
    this.title,
    this.subTitle,
    this.isTopRight = false,
    this.icon,
    this.onCrossPressed,
    this.isAssetImage = true,
    this.imageByteList,
    this.atsign,
  }) : super(key: key);

  @override
  _DesktopCustomPersonVerticalTileState createState() =>
      _DesktopCustomPersonVerticalTileState();
}

class _DesktopCustomPersonVerticalTileState
    extends State<DesktopCustomPersonVerticalTile> {
  Uint8List? atsignImage;
  String? contactName;
  @override
  void initState() {
    super.initState();
    getAtsignImage();
  }

  getAtsignImage() {
    if (widget.atsign != null) {
      AtContact? contact = getCachedContactDetail(widget.atsign!);
      if (contact != null &&
          contact.tags != null &&
          contact.tags!['image'] != null) {
        var image = contact.tags!['image'];
        image = image!.cast<int>();
        atsignImage = Uint8List.fromList(image);
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: <Widget>[
          Stack(
            children: <Widget>[
              SizedBox(
                height: 60.toHeight,
                width: 60.toHeight,
                child: widget.isAssetImage && widget.imageLocation != null
                    ? CustomCircleAvatar(
                        size: 60.toHeight,
                        image: widget.imageLocation,
                      )
                    : atsignImage != null
                        ? ClipRRect(
                            borderRadius:
                                BorderRadius.all(Radius.circular(30.toFont)),
                            child: Image.memory(
                              atsignImage!,
                              width: 50.toFont,
                              height: 50.toFont,
                              fit: BoxFit.fill,
                            ),
                          )
                        : ContactInitial(
                            initials: widget.subTitle ?? ' ',
                          ),
              ),
              widget.icon != null
                  ? Positioned(
                      top: widget.isTopRight ? 0 : null,
                      bottom: !widget.isTopRight ? 0 : null,
                      right: 0,
                      child: GestureDetector(
                        onTap: widget.onCrossPressed as void Function(),
                        child: Container(
                          height: 20.toHeight,
                          width: 20.toHeight,
                          decoration: const BoxDecoration(
                              color: Colors.black, shape: BoxShape.circle),
                          child: Icon(
                            Icons.close,
                            size: 15.toHeight,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(),
            ],
          ),
          const SizedBox(height: 2),
          contactName != null
              ? Text(
                  contactName!,
                  style: CustomTextStyles().grey16,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                )
              : const SizedBox(),
          const SizedBox(height: 2),
          widget.subTitle != null
              ? SizedBox(
                  width: 120,
                  child: Text(
                    widget.subTitle!,
                    style: CustomTextStyles().grey16,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                )
              : const SizedBox(),
          const SizedBox(height: 2),
        ],
      ),
    );
  }
}
