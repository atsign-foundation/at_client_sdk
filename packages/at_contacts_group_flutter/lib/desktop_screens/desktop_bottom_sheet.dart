// ignore: import_of_legacy_library_into_null_safe
import 'package:at_contacts_flutter/utils/colors.dart';
import 'package:at_contacts_group_flutter/utils/text_styles.dart';
import 'package:flutter/material.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:at_common_flutter/services/size_config.dart';

class DesktopGroupBottomSheet extends StatefulWidget {
  final Function onPressed;
  final String buttontext, message;
  const DesktopGroupBottomSheet(
    this.onPressed,
    this.buttontext, {
    Key? key,
    this.message = '',
  }) : super(key: key);

  @override
  _DesktopGroupBottomSheetState createState() =>
      _DesktopGroupBottomSheetState();
}

class _DesktopGroupBottomSheetState extends State<DesktopGroupBottomSheet> {
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20.toWidth),
      height: 70.toHeight,
      decoration: const BoxDecoration(
          color: Colors.white, boxShadow: [BoxShadow(color: Colors.grey)]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: Text(
              widget.message,
              style: CustomTextStyles.primaryMedium14,
            ),
          ),
          isLoading
              ? const CircularProgressIndicator()
              : TextButton(
                  onPressed: () {},
                  style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith<Color>(
                    (Set<WidgetState> states) {
                      return ColorConstants.orangeColor;
                    },
                  ), fixedSize: WidgetStateProperty.resolveWith<Size>(
                    (Set<WidgetState> states) {
                      return const Size(120, 40);
                    },
                  )),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}
