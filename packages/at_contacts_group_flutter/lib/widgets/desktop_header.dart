import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_group_flutter/utils/text_constants.dart';
import 'package:at_contacts_group_flutter/utils/text_styles.dart';
import 'package:flutter/material.dart';

// ignore: must_be_immutable
class DesktopHeader extends StatelessWidget {
  final String? title;
  final ValueChanged<bool>? onFilter;
  List<Widget>? actions;
  Function onBackTap;
  List<String> options = [
    'By type',
    'By name',
    'By size',
    'By date',
    'add-btn'
  ];
  bool showBackIcon, isTitleCentered;
  DesktopHeader({
    Key? key,
    required this.onBackTap,
    this.title,
    this.showBackIcon = true,
    this.onFilter,
    this.actions,
    this.isTitleCentered = false,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: SizeConfig().screenWidth - TextConstants.SIDEBAR_WIDTH,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 20),
          showBackIcon
              ? InkWell(
                  onTap: () {
                    onBackTap();
                  },
                  child: const Icon(Icons.arrow_back),
                )
              : const SizedBox(),
          const SizedBox(width: 15),
          title != null && isTitleCentered
              ? Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: Center(
                      child: Text(
                        title!,
                        style: CustomTextStyles.primaryRegular20,
                      ),
                    ),
                  ),
                )
              : const SizedBox(),
          title != null && !isTitleCentered
              ? Center(
                  child: Text(
                    title!,
                    style: CustomTextStyles.primaryRegular20,
                  ),
                )
              : const SizedBox(),
          const SizedBox(width: 15),
          // !isTitleCentered ? Expanded(child: SizedBox()) : SizedBox(),
          actions != null
              ? Expanded(
                  child: Row(
                    children: actions!,
                  ),
                )
              : const SizedBox()
        ],
      ),
    );
  }
}
