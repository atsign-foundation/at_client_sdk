import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contact/at_contact.dart';
import 'package:at_location_flutter/common_components/custom_toast.dart';
import 'package:at_location_flutter/common_components/pop_button.dart';
import 'package:at_location_flutter/service/request_location_service.dart';
import 'package:at_location_flutter/service/at_location_notification_listener.dart';
import 'package:at_location_flutter/utils/constants/colors.dart';
import 'package:at_location_flutter/utils/constants/text_strings.dart';
import 'package:at_location_flutter/utils/constants/text_styles.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:flutter/material.dart';

class RequestLocationSheet extends StatefulWidget {
  final Function? onTap;

  const RequestLocationSheet({Key? key, this.onTap}) : super(key: key);

  @override
  _RequestLocationSheetState createState() => _RequestLocationSheetState();
}

class _RequestLocationSheetState extends State<RequestLocationSheet> {
  AtContact? selectedContact;
  late bool isLoading;
  String? selectedOption, textField;

  @override
  void initState() {
    super.initState();
    isLoading = false;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: SizeConfig().screenHeight * 0.4,
      padding: const EdgeInsets.all(25),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(AllText().REQUEST_LOCATION,
                  style: CustomTextStyles().black18),
              PopButton(label: AllText().CANCEL)
            ],
          ),
          const SizedBox(
            height: 25,
          ),
          Text(AllText().REQUEST_FROM, style: CustomTextStyles().greyLabel14),
          const SizedBox(height: 10),
          CustomInputField(
            width: 330.toWidth,
            height: 50,
            hintText: AllText().TYPE_AT_SIGN,
            initialValue: textField ?? '',
            value: (str) {
              if (!str.contains('@')) {
                str = '@$str';
              }
              textField = str;
            },
            icon: Icons.contacts_rounded,
            onTap: widget.onTap,
          ),
          const Expanded(child: SizedBox()),
          Center(
            child: isLoading
                ? const CircularProgressIndicator()
                : CustomButton(
                    buttonText: AllText().REQUEST,
                    onPressed: onRequestTap,
                    fontColor: AllColors().WHITE,
                    width: 164,
                    height: 48,
                  ),
          )
        ],
      ),
    );
  }

  void onRequestTap() async {
    setState(() {
      isLoading = true;
    });
    var validAtSign = await checkAtsign(textField);

    if (!validAtSign) {
      setState(() {
        isLoading = false;
      });
      CustomToast().show(AllText().AT_SIGN_NOT_VALID, context, isError: true);
      return;
    }

    var result =
        await RequestLocationService().sendRequestLocationEvent(textField);

    if (result == null) {
      setState(() {
        isLoading = false;
      });
      Navigator.of(context).pop();
      return;
    }

    if (result == true) {
      CustomToast()
          .show(AllText().REQUEST_LOCATION_SENT, context, isSuccess: true);
      setState(() {
        isLoading = false;
      });
      Navigator.of(context).pop();
    } else {
      CustomToast().show(AllText().SOMETHING_WENT_WRONG_TRY_AGAIN, context,
          isError: true);
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<bool> checkAtsign(String? atSign) async {
    if (atSign == null) {
      return false;
    } else if (!atSign.contains('@')) {
      atSign = '@$atSign';
    }
    var checkPresence = (await CacheableSecondaryAddressFinder(
                AtLocationNotificationListener().ROOT_DOMAIN ?? '', 64)
            .findSecondary(atSign))
        .toString();
    return checkPresence.isNotEmpty;
  }
}
