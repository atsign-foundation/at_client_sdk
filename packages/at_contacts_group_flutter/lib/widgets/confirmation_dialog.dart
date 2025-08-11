import 'dart:typed_data';

import 'package:at_contacts_flutter/utils/init_contacts_service.dart';
import 'package:at_contacts_group_flutter/utils/colors.dart';
import 'package:at_contacts_group_flutter/utils/text_styles.dart';
import 'package:at_contacts_group_flutter/widgets/contact_initial.dart';
import 'package:flutter/material.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:at_common_flutter/at_common_flutter.dart';

// ignore: must_be_immutable
class ConfirmationDialog extends StatefulWidget {
  final String? heading, subtitle, atsign;
  String title;
  final Function onYesPressed;
  final Uint8List? image;
  ConfirmationDialog(
      {Key? key,
      required this.heading,
      required this.title,
      required this.onYesPressed,
      this.subtitle,
      this.atsign,
      this.image})
      : super(key: key);

  @override
  _ConfirmationDialogState createState() => _ConfirmationDialogState();
}

class _ConfirmationDialogState extends State<ConfirmationDialog> {
  late bool isLoading;
  Uint8List? contactImage;
  late String contactInitial;

  @override
  void initState() {
    isLoading = false;
    getAtsignImage();
    super.initState();
    if (widget.title[0] == '@') {
      contactInitial = widget.title.substring(1, widget.title.length);
    } else {
      contactInitial = widget.title;
    }
  }

  // ignore: always_declare_return_types
  getAtsignImage() async {
    if (widget.atsign == null) return;
    var contact = await getAtSignDetails(widget.atsign!);

    // ignore: unnecessary_null_comparison
    if (contact != null) {
      if (contact.tags != null && contact.tags!['image'] != null) {
        List<int>? intList = contact.tags!['image'].cast<int>();
        setState(() {
          contactImage = Uint8List.fromList(intList!);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: const EdgeInsets.only(top: 0),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.toWidth)),
      content: Container(
        height: 410.toHeight,
        width: 200.toWidth,
        color: Theme.of(context).brightness == Brightness.light
            ? AllColors().WHITE
            : AllColors().Black,
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.heading!,
                style: CustomTextStyles().grey16,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 15.toHeight),
              // when image is direclty passed as parameter(for group picture)
              widget.image != null
                  ? ClipRRect(
                      borderRadius:
                          BorderRadius.all(Radius.circular(30.toFont)),
                      child: Image.memory(
                        widget.image!,
                        width: 50.toFont,
                        height: 50.toFont,
                        fit: BoxFit.fill,
                      ),
                    )
                  // when we have to find image of the atsign
                  : contactImage != null
                      ? ClipRRect(
                          borderRadius:
                              BorderRadius.all(Radius.circular(30.toFont)),
                          child: Image.memory(
                            contactImage!,
                            width: 50.toFont,
                            height: 50.toFont,
                            fit: BoxFit.fill,
                          ),
                        )
                      : ContactInitial(initials: contactInitial, size: 60),

              SizedBox(height: 15.toHeight),
              Text(
                widget.title,
                style: CustomTextStyles().grey16,
              ),
              widget.subtitle != null
                  ? Text(
                      widget.subtitle!,
                      style: CustomTextStyles().grey16,
                    )
                  : const SizedBox(),
              SizedBox(height: 20.toHeight),
              isLoading
                  ? const CircularProgressIndicator()
                  : CustomButton(
                      height: 60.toHeight,
                      width: double.infinity,
                      buttonText: 'Yes',
                      onPressed: () async {
                        setState(() {
                          isLoading = true;
                        });

                        // ignore: unnecessary_null_comparison
                        if (widget.onYesPressed != null) {
                          await widget.onYesPressed();
                        }

                        if (mounted) {
                          setState(() {
                            isLoading = false;
                          });
                        }
                      },
                      buttonColor:
                          Theme.of(context).brightness == Brightness.light
                              ? AllColors().Black
                              : AllColors().WHITE,
                      fontColor:
                          Theme.of(context).brightness == Brightness.light
                              ? AllColors().WHITE
                              : AllColors().Black,
                    ),
              SizedBox(height: 10.toHeight),
              CustomButton(
                height: 60.toHeight,
                width: double.infinity,
                buttonText: 'No',
                onPressed: () async {
                  Navigator.of(context).pop();
                },
                buttonColor: Theme.of(context).brightness == Brightness.light
                    ? AllColors().WHITE
                    : AllColors().Black,
                fontColor: Theme.of(context).brightness == Brightness.light
                    ? AllColors().Black
                    : AllColors().WHITE,
              )
            ],
          ),
        ),
      ),
    );
  }
}
