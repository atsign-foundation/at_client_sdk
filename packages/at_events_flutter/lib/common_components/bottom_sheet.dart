import 'package:at_events_flutter/utils/colors.dart';
import 'package:flutter/material.dart';

/// displays a bottom sheet with the provided widget 'T' and 'height' in the given 'context', and calls 'onSheetClosed' function when the sheet is closed
void bottomSheet(BuildContext context, T, double height,
    {Function? onSheetCLosed}) {
  var future = showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const StadiumBorder(),
      builder: (BuildContext context) {
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.light
                ? AllColors().WHITE
                : AllColors().Black,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12.0),
              topRight: Radius.circular(12.0),
            ),
          ),
          child: T,
        );
      });

  future.then((value) {
    if (onSheetCLosed != null) onSheetCLosed();
  });
}
