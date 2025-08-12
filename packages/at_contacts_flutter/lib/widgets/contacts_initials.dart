// ignore_for_file: must_be_immutable

import 'package:at_contacts_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:at_common_flutter/services/size_config.dart';

class ContactInitial extends StatelessWidget {
  /// Size of the circular profile placeholder
  final double size;
  final double? maxSize, minSize;

  /// Initials of the atsign
  String initials;

  /// Index in the list of atsigns
  final int? index;

  ContactInitial(
      {Key? key,
      this.size = 40,
      required this.initials,
      this.index,
      this.maxSize,
      this.minSize})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    if (initials[0] == '@') {
      initials = initials.substring(1);
    }
    var encodedInitials = initials.runes;

    return Container(
      height: size.toFont,
      width: size.toFont,
      decoration: BoxDecoration(
        color: ContactInitialsColors.getColor(initials),
        borderRadius: BorderRadius.circular((size.toFont)),
      ),
      child: Center(
        child: Text(
          String.fromCharCodes(encodedInitials, 0,
                  (encodedInitials.length < 2 ? encodedInitials.length : 2))
              .toUpperCase(),
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
