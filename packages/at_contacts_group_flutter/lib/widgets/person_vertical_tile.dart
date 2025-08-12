import 'dart:typed_data';

import 'package:at_contacts_flutter/at_contacts_flutter.dart';
import 'package:at_contacts_flutter/widgets/contacts_initials.dart';
import 'package:at_contacts_group_flutter/utils/text_styles.dart';
import 'package:at_contacts_group_flutter/widgets/custom_circle_avatar.dart';
import 'package:flutter/material.dart';

class CustomPersonVerticalTile extends StatefulWidget {
  final String? imageLocation, title, subTitle, atsign;
  final bool isTopRight, isAssetImage;
  final IconData? icon;
  final Function? onCrossPressed;
  final Uint8List? imageIntList;

  const CustomPersonVerticalTile(
      {Key? key,
      this.imageLocation,
      this.title,
      this.subTitle,
      this.isTopRight = false,
      this.icon,
      this.onCrossPressed,
      this.isAssetImage = true,
      this.imageIntList,
      this.atsign})
      : super(key: key);

  @override
  _CustomPersonVerticalTileState createState() =>
      _CustomPersonVerticalTileState();
}

class _CustomPersonVerticalTileState extends State<CustomPersonVerticalTile> {
  Uint8List? image;
  String? contactName;
  @override
  void initState() {
    super.initState();
    getAtsignImage();
  }

  // ignore: always_declare_return_types
  getAtsignImage() async {
    if (widget.atsign == null) return;
    var contact = await getAtSignDetails(widget.atsign!);

    // ignore: unnecessary_null_comparison
    if (contact != null) {
      if (contact.tags != null && contact.tags!['image'] != null) {
        List<int>? intList = contact.tags!['image'].cast<int>();
        if (mounted) {
          setState(() {
            image = Uint8List.fromList(intList!);
          });
        }
      }
      if (contact.tags != null && contact.tags!['name'] != null) {
        if (mounted) {
          setState(() {
            contactName = contact.tags!['name'];
          });
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
                    : image != null
                        ? ClipRRect(
                            borderRadius:
                                BorderRadius.all(Radius.circular(30.toFont)),
                            child: Image.memory(
                              image!,
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
                        onTap: widget.onCrossPressed as void Function()?,
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
              ? Text(
                  widget.subTitle!,
                  style: CustomTextStyles().grey14,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                )
              : const SizedBox(),
          const SizedBox(height: 2),
        ],
      ),
    );
  }
}
