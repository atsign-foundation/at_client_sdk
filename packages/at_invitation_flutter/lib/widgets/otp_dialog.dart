import 'dart:async';

import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_invitation_flutter/utils/text_styles.dart'
    as invitation_text_styles;
import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

class OTPDialog extends StatefulWidget {
  final String? uniqueID;
  final String? passcode;
  final String? webPageLink;
  const OTPDialog({Key? key, this.uniqueID, this.passcode, this.webPageLink})
      : super(key: key);

  @override
  State<OTPDialog> createState() => _OTPDialogState();
}

class _OTPDialogState extends State<OTPDialog> {
  TextEditingController textEditingController = TextEditingController();
  // ignore: close_sinks
  StreamController<ErrorAnimationType>? errorController;

  @override
  void initState() {
    errorController = StreamController<ErrorAnimationType>();
    super.initState();
  }

  @override
  void dispose() {
    errorController!.close();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    var deviceTextFactor = MediaQuery.of(context).textScaler.scale(20) / 20;
    return SizedBox(
      height: 100.toHeight * deviceTextFactor,
      width: 100.toWidth,
      child: SingleChildScrollView(
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
                  'Invite confirmation',
                  textAlign: TextAlign.center,
                  style: invitation_text_styles.CustomTextStyles.primaryBold18,
                ),
              )
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: 200.toHeight),
            child: Column(children: [
              const Text(
                'Please enter the OTP that you have recieved with the invite link',
                textAlign: TextAlign.center,
              ),
              SizedBox(
                height: 20.toHeight,
              ),
              PinCodeTextField(
                appContext: context,
                pastedTextStyle: TextStyle(
                  color: Colors.green.shade600,
                  fontWeight: FontWeight.bold,
                ),
                length: 4,
                obscureText: true,
                obscuringCharacter: '*',
                blinkWhenObscuring: true,
                animationType: AnimationType.fade,
                validator: (v) {
                  if (v!.length < 4) {
                    return "It is a 4 digit pin";
                  } else {
                    return null;
                  }
                },
                pinTheme: PinTheme(
                  shape: PinCodeFieldShape.box,
                  borderRadius: BorderRadius.circular(5),
                  fieldHeight: 50,
                  fieldWidth: 40,
                  activeFillColor: Colors.white,
                ),
                cursorColor: Colors.black,
                animationDuration: const Duration(milliseconds: 300),
                enableActiveFill: true,
                errorAnimationController: errorController,
                controller: textEditingController,
                keyboardType: TextInputType.number,
                boxShadows: const [
                  BoxShadow(
                    offset: Offset(0, 1),
                    color: Colors.black12,
                    blurRadius: 10,
                  )
                ],
                onCompleted: (v) {
                  Navigator.pop(context, v);
                },
                onChanged: (value) {},
                beforeTextPaste: (text) {
                  //if you return true then it will show the paste confirmation dialog. Otherwise if false, then nothing will happen.
                  //but you can show anything you want here, like your pop up saying wrong paste format or etc
                  return true;
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
