import 'dart:typed_data';

import 'package:at_common_flutter/services/size_config.dart';
import 'package:at_common_flutter/widgets/custom_button.dart';
import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/widgets/contacts_initials.dart';
import 'package:at_contacts_flutter/widgets/custom_circle_avatar.dart';
import 'package:at_contacts_group_flutter/services/group_service.dart';
import 'package:at_contacts_group_flutter/utils/text_styles.dart';
import 'package:flutter/material.dart';

class RemoveTrustedContact extends StatefulWidget {
  final String? image, title;
  final String? name;
  final String? atSign;
  final AtContact? contact;
  final AtGroup? atGroup;

  const RemoveTrustedContact(
    this.title, {
    Key? key,
    this.image,
    this.name,
    this.atSign,
    this.contact,
    this.atGroup,
  }) : super(key: key);

  @override
  _RemoveTrustedContactState createState() => _RemoveTrustedContactState();
}

class _RemoveTrustedContactState extends State<RemoveTrustedContact> {
  Uint8List? image;
  bool loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.contact?.tags != null &&
        widget.contact?.tags!['image'] != null) {
      List<int> intList = widget.contact?.tags!['image'].cast<int>();
      image = Uint8List.fromList(intList);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.toWidth),
      ),
      titlePadding: EdgeInsets.all(20.toHeight),
      title: Row(
        children: [
          Expanded(
            child: Text(
              widget.title!,
              style: CustomTextStyles.primaryBold16,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
      content: SizedBox(
        height: 280.toHeight,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                (image != null)
                    ? CustomCircleAvatar(
                        byteImage: image,
                        nonAsset: true,
                      )
                    : ContactInitial(
                        initials: widget.contact?.tags != null &&
                                widget.contact?.tags!['name'] != null
                            ? widget.contact?.tags!['name']
                            : widget.contact?.atSign,
                        size: 50.toWidth,
                        maxSize: (80.0 - 30.0),
                        minSize: 50,
                      )
              ],
            ),
            SizedBox(
              height: 20.toHeight,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Center(
                      child: Text(
                    widget.contact?.tags != null &&
                            widget.contact?.tags!['name'] != null
                        ? widget.contact?.tags!['name']
                        : widget.contact?.atSign!.substring(1),
                    style: CustomTextStyles.primaryBold16,
                  )),
                ),
              ],
            ),
            SizedBox(
              height: 5.toHeight,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      widget.contact!.atSign ?? '',
                      style: CustomTextStyles.secondaryRegular14,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 20.toHeight,
            ),
            loading
                ? const CircularProgressIndicator()
                : Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CustomButton(
                            buttonText: 'Yes',
                            width: 200.toWidth,
                            buttonColor: Colors.black,
                            fontColor: Colors.white,
                            onPressed: () async {
                              setState(() {
                                loading = true;
                              });
                              var result =
                                  await GroupService().deletGroupMembers(
                                [widget.contact!],
                                widget.atGroup!,
                              );

                              if (result is bool && result) {
                                if(context.mounted){
                                  Navigator.of(context).pop();
                                }
                              } else if (result == null) {
                                _error = 'Something went wrong';
                              } else {
                                _error = result.toString();
                              }

                              if (mounted) {
                                setState(() {
                                  loading = false;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      SizedBox(height: 10.toHeight),
                      CustomButton(
                        buttonText: 'No',
                        buttonColor: Colors.white,
                        fontColor: Colors.black,
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),
                      SizedBox(height: 10.toHeight),
                      _error != null
                          ? Text(
                              _error!,
                              style: CustomTextStyles.error14,
                            )
                          : const SizedBox(),
                    ],
                  )
          ],
        ),
      ),
    );
  }
}
