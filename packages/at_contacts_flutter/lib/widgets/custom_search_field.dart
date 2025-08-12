import 'package:at_common_flutter/services/size_config.dart';
import 'package:at_contacts_flutter/utils/colors.dart';
import 'package:flutter/material.dart';

/// A search field to filter out the contacts
class ContactSearchField extends StatelessWidget {
  final Function(String) onChanged;
  final String hintText;
  const ContactSearchField(this.hintText, this.onChanged, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12.toFont),
      child: TextField(
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hintText,
          hintStyle: TextStyle(
            fontSize: 16.toFont,
            color: ColorConstants.greyText,
            fontWeight: FontWeight.normal,
          ),
          filled: true,
          fillColor: ColorConstants.inputFieldColor,
          contentPadding: EdgeInsets.symmetric(vertical: 15.toHeight),
          prefixIcon: Icon(
            Icons.search,
            color: ColorConstants.greyText,
            size: 20.toFont,
          ),
        ),
        style: TextStyle(
          fontSize: 16.toFont,
          color: ColorConstants.fontPrimary,
          fontWeight: FontWeight.normal,
        ),
      ),
    );
  }
}
