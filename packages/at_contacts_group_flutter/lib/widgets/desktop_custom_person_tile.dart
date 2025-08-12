import 'package:at_common_flutter/services/size_config.dart';
import 'package:at_contacts_flutter/widgets/contacts_initials.dart';
import 'package:at_contacts_group_flutter/utils/text_styles.dart';
import 'package:flutter/material.dart';

class DesktopCustomPersonVerticalTile extends StatelessWidget {
  final String? title, subTitle;
  final bool showCancelIcon;
  final Function? onRemovePress;
  const DesktopCustomPersonVerticalTile({
    Key? key,
    this.title,
    this.subTitle,
    this.showCancelIcon = true,
    this.onRemovePress,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Stack(
          children: [
            ContactInitial(
              initials: title ?? ' ',
              size: 30,
              maxSize: (80.0 - 30.0),
              minSize: 50,
            ),
            showCancelIcon
                ? Positioned(
                    top: 0,
                    right: 0,
                    child: InkWell(
                      onTap: () {
                        onRemovePress!();
                      },
                      child: const Icon(Icons.cancel),
                    ),
                  )
                : const SizedBox(),
          ],
        ),
        SizedBox(width: 10.toHeight),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                title!,
                style: CustomTextStyles.desktopPrimaryRegular14,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 5.toHeight),
              subTitle != null
                  ? Text(
                      subTitle!,
                      style: CustomTextStyles.secondaryRegular12,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : const SizedBox(),
            ],
          ),
        )
      ],
    );
  }
}
