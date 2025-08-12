import 'package:at_chat_flutter/utils/colors.dart';

/// This is a widget to display the initials of an atsign which does not have a profile picture
/// it takes in @param [size] as a double and
/// @param [initials] as String and display those initials in a circular avatar with random colors

import 'package:flutter/material.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:at_common_flutter/services/size_config.dart';

// ignore: must_be_immutable
class ContactInitial extends StatelessWidget {
  final double size;
  final String initials;
  int? index;
  final Color? backgroundColor;
  ContactInitial(
      {Key? key,
      this.size = 50,
      required this.initials,
      this.index,
      this.backgroundColor})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (initials.length < 3) {
      index = initials.length;
    } else {
      index = 3;
    }

    return Container(
      height: size.toHeight,
      width: size.toHeight,
      decoration: BoxDecoration(
        color: backgroundColor ?? ContactInitialsColors.getColor(initials),
        borderRadius: BorderRadius.circular(size.toWidth),
      ),
      child: Center(
        child: Text(
          initials.substring((index == 1) ? 0 : 1, index).toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontSize: 16.toFont,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
