// ignore: import_of_legacy_library_into_null_safe
import 'package:at_common_flutter/widgets/custom_button.dart';
import 'package:at_contacts_flutter/utils/text_styles.dart';
import 'package:at_contacts_group_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:at_common_flutter/services/size_config.dart';

class GroupBottomSheet extends StatefulWidget {
  final Function? onPressed;
  final String buttontext, message;
  const GroupBottomSheet({
    Key? key,
    this.onPressed,
    required this.buttontext,
    this.message = '',
  }) : super(key: key);

  @override
  _GroupBottomSheetState createState() => _GroupBottomSheetState();
}

class _GroupBottomSheetState extends State<GroupBottomSheet> {
  late bool isLoading;
  @override
  void initState() {
    super.initState();
    isLoading = false;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20.toWidth),
      height: 70.toHeight,
      decoration: const BoxDecoration(
          color: Color(0xffF7F7FF), boxShadow: [BoxShadow(color: Colors.grey)]),
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
              : CustomButton(
                  buttonText: widget.buttontext,
                  width: 120.toWidth,
                  height: 40.toHeight,
                  // isInverted: false,
                  onPressed: () async {
                    setState(() {
                      isLoading = true;
                    });

                    if (widget.onPressed != null) await widget.onPressed!();

                    if (mounted) {
                      setState(() {
                        isLoading = false;
                      });
                    }
                  },
                  buttonColor: Theme.of(context).brightness == Brightness.light
                      ? AllColors().Black
                      : AllColors().WHITE,
                  fontColor: Theme.of(context).brightness == Brightness.light
                      ? AllColors().WHITE
                      : AllColors().Black,
                )
        ],
      ),
    );
  }
}
