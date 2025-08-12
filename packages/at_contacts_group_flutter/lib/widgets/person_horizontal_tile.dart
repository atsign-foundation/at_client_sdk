import 'dart:typed_data';

import 'package:at_contacts_flutter/widgets/contacts_initials.dart';
import 'package:at_contacts_group_flutter/utils/text_styles.dart';
import 'package:flutter/material.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:at_common_flutter/at_common_flutter.dart';

// ignore: must_be_immutable
class CustomPersonHorizontalTile extends StatelessWidget {
  final String? title, subTitle;
  final bool isTopRight;
  final IconData? icon;
  List<dynamic>? image;

  CustomPersonHorizontalTile({
    Key? key,
    this.image,
    this.title,
    this.subTitle,
    this.isTopRight = false,
    this.icon,
  }) : super(key: key) {
    if (image != null) {
      var intList = image!.cast<int>();
      image = Uint8List.fromList(intList);
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Row(
      children: <Widget>[
        Stack(
          children: [
            image != null
                ? ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(30.toWidth)),
                    child: Image.memory(
                      image as Uint8List,
                      width: 50.toWidth,
                      height: 50.toWidth,
                      fit: BoxFit.fill,
                    ),
                  )
                : ContactInitial(
                    size: SizeConfig().isTablet(context)
                        ? 28.toWidth
                        : 45.toWidth,
                    initials: title ?? ' ',
                    minSize: 40.0,
                    maxSize: 40.0,
                  ),
            icon != null
                ? Positioned(
                    top: isTopRight ? 0 : null,
                    right: 0,
                    bottom: !isTopRight ? 0 : null,
                    child: Icon(icon))
                : const SizedBox(),
          ],
        ),
        SizedBox(width: 10.toHeight),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: title != null
                  ? Text(
                      title!,
                      style: CustomTextStyles().grey16,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : const SizedBox(),
            ),
            SizedBox(height: 5.toHeight),
            subTitle != null
                ? Text(
                    subTitle!,
                    style: CustomTextStyles().grey14,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : const SizedBox(),
          ],
        )
      ],
    );
  }
}
