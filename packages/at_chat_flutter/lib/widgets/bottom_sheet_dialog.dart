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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: 16,
        ),
        GestureDetector(
          onTap: () {
            setState(() {
              isLoading = true;
            });
            widget.deleteCallback();
          },
          child: Container(
            width: 240,
            padding: EdgeInsets.symmetric(
                vertical: 16, horizontal: 0),
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
                  width: 36,
                ),
                const Text(
                  'Delete Message',
                  style: TextStyle(color: Colors.red, fontSize: 14),
                ),
                SizedBox(
                  width: 16,
                ),
                SizedBox(
                  width: 20,
                  height: 20,
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
          height: 8,
        ),
        GestureDetector(
          onTap: () {
            Navigator.of(context).pop();
          },
          child: Container(
            width: 240,
            padding: EdgeInsets.symmetric(
                vertical: 16, horizontal: 0),
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
          height: 16,
        ),
      ],
    );
  }
}
