import 'package:at_events_flutter/utils/colors.dart';
import 'package:at_events_flutter/utils/texts.dart';
import 'package:flutter/material.dart';
import 'package:at_common_flutter/at_common_flutter.dart';

class ErrorScreen extends StatelessWidget {
  final Function? onPressed;
  const ErrorScreen({Key? key, this.onPressed}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(AllText().SOMETHING_WENT_WRONG),
          const SizedBox(height: 10),
          CustomButton(
            buttonText: AllText().RETRY,
            width: 120.toWidth,
            height: 40.toHeight,
            buttonColor: Theme.of(context).brightness == Brightness.light
                ? AllColors().Black
                : AllColors().WHITE,
            fontColor: Theme.of(context).brightness == Brightness.light
                ? AllColors().WHITE
                : AllColors().Black,
            onPressed: () async {
              if (onPressed != null) {
                onPressed!();
              }
            },
          )
        ],
      ),
    );
  }
}
