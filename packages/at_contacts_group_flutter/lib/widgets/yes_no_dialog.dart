import 'package:at_common_flutter/services/size_config.dart';
import 'package:flutter/material.dart';

shownConfirmationDialog(
  BuildContext context,
  String title,
  Function onYesTap, {
  Function? onNoTap,
}) {
  showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.toWidth),
          ),
          content: Container(
            width: 400.toWidth,
            padding: EdgeInsets.all(15.toFont),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title),
                  SizedBox(
                    height: 20.toHeight,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            onYesTap();
                          },
                          child: Text('Yes',
                              style: TextStyle(
                                fontSize: 16.toFont,
                                fontWeight: FontWeight.normal,
                              ))),
                      TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            onNoTap?.call();
                          },
                          child: Text('Cancel',
                              style: TextStyle(
                                fontSize: 16.toFont,
                                fontWeight: FontWeight.normal,
                              )))
                    ],
                  )
                ],
              ),
            ),
          ),
        );
      });
}
