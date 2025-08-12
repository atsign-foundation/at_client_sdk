// ignore: import_of_legacy_library_into_null_safe
import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_flutter/services/contact_service.dart';
import 'package:at_contacts_flutter/utils/text_strings.dart';
import 'package:at_contacts_flutter/utils/text_styles.dart';
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
    var deviceTextFactor = MediaQuery.of(context).textScaler.scale(20) / 20;
    return SizedBox(
      height: 100 * deviceTextFactor,
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
          child: Column(
            children: [
              // SizedBox(
              //   height: 21.toHeight,
              // ),
              // CustomCircleAvatar(
              //   image: ImageConstants.imagePlaceholder,
              //   size: 75,
              // ),
              SizedBox(
                height: 10.toHeight,
              ),
              Text(
                widget.atSignName ?? 'Levina Thomas',
                style: CustomTextStyles.primaryBold16,
              ),
              SizedBox(
                height: 25.toHeight,
              ),
              // Text(
              //   widget.atSignName ?? '',
              //   style: CustomTextStyles.secondaryRegular16,
              // ),
              (isLoading)
                  ? const CircularProgressIndicator()
                  : CustomButton(
                      buttonText: TextStrings().yes,
                      buttonColor:
                          Theme.of(context).brightness == Brightness.light
                              ? Colors.black
                              : Colors.white,
                      fontColor:
                          Theme.of(context).brightness == Brightness.light
                              ? Colors.white
                              : Colors.black,
                      onPressed: () async {
                        setState(() {
                          isLoading = true;
                        });
                        await ContactService()
                            .addAtSign(atSign: widget.atSignName);
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
                buttonColor: Theme.of(context).brightness == Brightness.light
                    ? Colors.black
                    : Colors.white,
                fontColor: Theme.of(context).brightness == Brightness.light
                    ? Colors.white
                    : Colors.black,
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
        // actions: [
        //   ],
      ),
    );
  }
}
