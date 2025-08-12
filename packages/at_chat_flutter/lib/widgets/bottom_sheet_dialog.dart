import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:flutter/material.dart';

class BottomSheetDialog extends StatefulWidget {
  final Function() deleteCallback;

  const BottomSheetDialog(
    this.deleteCallback, {
    Key? key,
  }) : super(key: key);

  @override
  State<BottomSheetDialog> createState() => _BottomSheetDialogState();
}

class _BottomSheetDialogState extends State<BottomSheetDialog> {
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: 16.toHeight,
        ),
        GestureDetector(
          onTap: () {
            setState(() {
              isLoading = true;
            });
            widget.deleteCallback();
          },
          child: Container(
            width: 240.toWidth,
            padding: EdgeInsets.symmetric(
                vertical: 16.toHeight, horizontal: 0.toWidth),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(
                Radius.circular(5.0),
              ),
              border: Border.all(color: Colors.grey.shade50),
              color: Colors.white,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 36.toWidth,
                ),
                const Text(
                  'Delete Message',
                  style: TextStyle(color: Colors.red, fontSize: 14),
                ),
                SizedBox(
                  width: 16.toWidth,
                ),
                SizedBox(
                  width: 20.toWidth,
                  height: 20.toHeight,
                  child: Visibility(
                    visible: isLoading,
                    child: const CircularProgressIndicator(),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 8.toHeight,
        ),
        GestureDetector(
          onTap: () {
            Navigator.of(context).pop();
          },
          child: Container(
            width: 240.toWidth,
            padding: EdgeInsets.symmetric(
                vertical: 16.toHeight, horizontal: 0.toWidth),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(
                Radius.circular(5.0),
              ),
              border: Border.all(color: Colors.grey.shade50),
              color: Colors.white,
            ),
            child: const Center(
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.black, fontSize: 14),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 16.toHeight,
        ),
      ],
    );
  }
}
