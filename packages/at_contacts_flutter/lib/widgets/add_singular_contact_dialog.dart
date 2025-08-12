import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_flutter/services/contact_service.dart';
import 'package:at_contacts_flutter/utils/images.dart';
import 'package:at_contacts_flutter/utils/text_strings.dart';
import 'package:at_contacts_flutter/utils/text_styles.dart';
import 'package:at_contacts_flutter/widgets/custom_circle_avatar.dart';
import 'package:flutter/material.dart';

/// This widgets pops up when a contact is added it takes [name]
/// [handle] to display the name and the handle of the user and an
/// onTap function named as [onYesTap] for on press of [Yes] button of the dialog

class AddSingleContact extends StatefulWidget {
  final String? atSignName;
  // final ContactProvider contactProvider;

  const AddSingleContact({Key? key, this.atSignName}) : super(key: key);

  @override
  _AddSingleContactState createState() => _AddSingleContactState();
}

class _AddSingleContactState extends State<AddSingleContact> {
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return SizedBox(
      height: 100,
      width: 100,
      child: AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.toWidth)),
        titlePadding: EdgeInsets.only(
            top: 20.toHeight, left: 25.toWidth, right: 25.toWidth),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                TextStrings().addContactHeading,
                textAlign: TextAlign.center,
                style: CustomTextStyles.secondaryRegular16,
              ),
            )
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: 190.toHeight),
          child: SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(
                  height: 21.toHeight,
                ),
                CustomCircleAvatar(
                  image: ImageConstants.imagePlaceholder,
                  size: 75,
                ),
                SizedBox(
                  height: 10.toHeight,
                ),
                Text(
                  widget.atSignName!.substring(1),
                  style: CustomTextStyles.primaryBold16,
                ),
                SizedBox(
                  height: 2.toHeight,
                ),
                Text(
                  widget.atSignName ?? '',
                  style: CustomTextStyles.secondaryRegular16,
                ),
              ],
            ),
          ),
        ),
        actions: [
          (isLoading)
              ? const CircularProgressIndicator()
              : CustomButton(
                  buttonText: TextStrings().yes,
                  onPressed: () async {
                    isLoading = true;
                    await ContactService().addAtSign(atSign: widget.atSignName);
                    setState(() {
                      isLoading = false;
                      Navigator.pop(context);
                    });
                  },
                ),
          SizedBox(
            height: 10.toHeight,
          ),
          CustomButton(
            buttonText: TextStrings().no,
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
