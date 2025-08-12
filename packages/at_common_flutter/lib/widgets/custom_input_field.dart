import 'package:at_common_flutter/utils/colors.dart';
import 'package:flutter/material.dart';

/// This is a custom input field to have common functionalities of the app
// ignore: must_be_immutable
class CustomInputField extends StatelessWidget {
  /// The string to display if the input field is empty.
  final String hintText;

  /// A string to pre-populate the input field.
  final String initialValue;

  /// sets the width of the input field.
  final double width;

  /// sets the height of the input field.
  final double height;

  /// The trailing icon on the input field and calls the [onIconTap] or [onTap] when tapped.
  final IconData? icon;

  /// defines the function to execute on tap on the input field.
  final Function? onTap;

  /// defines the function to execute on tap on the [icon].
  final Function? onIconTap;

  /// defines the to execute on submit in the input field.
  final Function? onSubmitted;

  /// The color to fill the [icon].
  final Color? iconColor;

  /// The observable value of the input field.
  final ValueChanged<String>? value;

  /// makes the input field to be read only.
  final bool isReadOnly;

  /// this widget comes as prefix to input field.
  final Widget? prefix;

  /// background color of input field.
  final Color? inputFieldColor;

  /// The style to use for the text being edited.
  /// If null, defaults to the `subtitle1` text style from the current [Theme].
  final TextStyle style;

  /// The style to use for the [hintText].
  final TextStyle hintStyle;

  TextEditingController textController = TextEditingController();

  CustomInputField({
    Key? key,
    this.hintText = '',
    this.height = 50,
    this.width = 300,
    this.iconColor,
    this.icon,
    this.onTap,
    this.onIconTap,
    this.value,
    this.initialValue = '',
    this.onSubmitted,
    this.isReadOnly = false,
    this.prefix,
    this.inputFieldColor,
    this.style = const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.normal,
    ),
    this.hintStyle = const TextStyle(
      color: ColorConstants.darkGrey,
      fontSize: 15,
      fontWeight: FontWeight.normal,
    ),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    textController = TextEditingController.fromValue(TextEditingValue(
        text: initialValue,
        selection: TextSelection.collapsed(offset: initialValue.length)));
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: inputFieldColor ?? ColorConstants.inputFieldGrey,
        borderRadius: BorderRadius.circular(5),
      ),
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
      child: Row(
        children: <Widget>[
          prefix != null ? prefix! : const SizedBox(),
          Expanded(
            child: TextField(
              readOnly: isReadOnly,
              style: style,
              decoration: InputDecoration(
                hintText: hintText,
                enabledBorder: InputBorder.none,
                border: InputBorder.none,
                hintStyle: hintStyle,
              ),
              onTap: onTap as void Function()? ?? () {},
              onChanged: (val) {
                value!(val);
              },
              controller: textController,
              onSubmitted: (str) {
                if (onSubmitted != null) {
                  onSubmitted!(str);
                }
              },
            ),
          ),
          icon != null
              ? InkWell(
                  onTap: onIconTap as void Function()? ??
                      onTap as void Function()?,
                  child: Icon(
                    icon,
                    color: iconColor ?? ColorConstants.darkGrey,
                  ),
                )
              : const SizedBox()
        ],
      ),
    );
  }
}
