import 'package:at_contacts_flutter/utils/colors.dart';
import 'package:flutter/material.dart';

import 'package:at_common_flutter/at_common_flutter.dart';

class ErrorScreen extends StatelessWidget {
  final Function? onPressed;
  final String msg;
  const ErrorScreen(
      {Key? key,
      this.onPressed,
      this.msg = 'Something went wrong, please retry.'})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(msg,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.normal,
              )),
          const SizedBox(height: 10),
          onPressed != null
              ? CustomButton(
                  buttonText: 'Retry',
                  width: 120.toWidth,
                  height: 40.toHeight,
                  onPressed: () async {
                    if (onPressed != null) {
                      onPressed!();
                    }
                  },
                  buttonColor: Theme.of(context).brightness == Brightness.light
                      ? ColorConstants.fontPrimary
                      : ColorConstants.scaffoldColor,
                  fontColor: Theme.of(context).brightness == Brightness.light
                      ? ColorConstants.scaffoldColor
                      : ColorConstants.fontPrimary,
                )
              : const SizedBox()
        ],
      ),
    );
  }
}
