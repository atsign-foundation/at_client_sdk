import 'package:at_follows_flutter/utils/custom_textstyles.dart';
import 'package:at_follows_flutter/utils/strings.dart';
import 'package:flutter/material.dart';

//a class to display errors
class CustomErrorDialog extends StatelessWidget {
  final error;
  CustomErrorDialog({required this.error});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Text(
            Strings.Error,
            style: CustomTextStyles.fontR14primary,
          ),
          Icon(Icons.sentiment_dissatisfied)
        ],
      ),
      content: Text('${this.error}'),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text(Strings.Close),
        )
      ],
    );
  }
}

class ErrorDialog {
  static final ErrorDialog _singleton = ErrorDialog._internal();

  ErrorDialog._internal();
  // final AtSignLogger _logger = AtSignLogger('ErrorDialog');

  factory ErrorDialog.getInstance() {
    return _singleton;
  }

  void show(var error, {required BuildContext context}) {
    showDialog(
        context: context,
        builder: (_) {
          return CustomErrorDialog(
            error: error.toString(),
          );
        });
  }
}
