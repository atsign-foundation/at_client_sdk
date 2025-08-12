import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:at_contacts_flutter/widgets/contacts_initials.dart';
import 'package:at_contacts_flutter/at_contacts_flutter.dart';
import 'package:at_contacts_group_flutter/utils/text_styles.dart';

class PersonHorizontal extends StatefulWidget {
  final String? title, subTitle, atsign;
  final Function? onDelete;

  const PersonHorizontal({
    Key? key,
    this.title,
    this.subTitle,
    this.atsign,
    this.onDelete,
  }) : super(key: key);

  @override
  State<PersonHorizontal> createState() => _PersonHorizontalState();
}

class _PersonHorizontalState extends State<PersonHorizontal> {
  Uint8List? image;
  String? contactName;

  @override
  void initState() {
    super.initState();
    getAtsignImage();
  }

  getAtsignImage() async {
    if (widget.atsign == null) return;
    var contact = await getAtSignDetails(widget.atsign!);

    // ignore: unnecessary_null_comparison
    if (contact != null) {
      if (contact.tags != null && contact.tags!['image'] != null) {
        List<int>? intList = contact.tags!['image'].cast<int>();
        setState(() {
          image = Uint8List.fromList(intList!);
        });
      }
      if (contact.tags != null && contact.tags!['name'] != null) {
        setState(() {
          contactName = contact.tags!['name'];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            height: 60.toHeight,
            width: 60.toHeight,
            child: image != null
                ? ClipRRect(
                    borderRadius: BorderRadius.all(
                      Radius.circular(
                        30.toFont,
                      ),
                    ),
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
          SizedBox(
            width: 12.toWidth,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                widget.title != null
                    ? Text(
                        widget.title!,
                        style: CustomTextStyles().grey16,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : const SizedBox(),
                SizedBox(height: 5.toHeight),
                widget.subTitle != null
                    ? Text(
                        widget.subTitle!,
                        style: CustomTextStyles().grey14,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : const SizedBox(),
              ],
            ),
          ),
          InkWell(
            onTap: () {
              widget.onDelete?.call();
            },
            child: const Icon(
              Icons.close_rounded,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}