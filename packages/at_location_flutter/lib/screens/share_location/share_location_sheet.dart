import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contact/at_contact.dart';
import 'package:at_location_flutter/common_components/custom_toast.dart';
import 'package:at_location_flutter/common_components/pop_button.dart';
import 'package:at_location_flutter/service/sharing_location_service.dart';
import 'package:at_location_flutter/service/at_location_notification_listener.dart';
import 'package:at_location_flutter/utils/constants/colors.dart';
import 'package:at_location_flutter/utils/constants/text_strings.dart';
import 'package:at_location_flutter/utils/constants/text_styles.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:flutter/material.dart';

class ShareLocationSheet extends StatefulWidget {
  final Function? onTap;

  const ShareLocationSheet({Key? key, this.onTap}) : super(key: key);

  @override
  _ShareLocationSheetState createState() => _ShareLocationSheetState();
}

class _ShareLocationSheetState extends State<ShareLocationSheet> {
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
      height: SizeConfig().screenHeight * 0.5,
      padding: const EdgeInsets.all(25),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(AllText().SHARE_LOCATION, style: CustomTextStyles().black18),
              PopButton(label: AllText().CANCEL)
            ],
          ),
          const SizedBox(
            height: 25,
          ),
          Text(AllText().SHARE_WITH, style: CustomTextStyles().greyLabel14),
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
          const SizedBox(height: 25),
          Text(
            AllText().DURATION,
            style: CustomTextStyles().greyLabel14,
          ),
          const SizedBox(height: 10),
          Container(
            color: AllColors().INPUT_GREY_BACKGROUND,
            width: 330.toWidth,
            padding: const EdgeInsets.only(left: 10, right: 10),
            child: DropdownButton(
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down),
              underline: const SizedBox(),
              elevation: 0,
              dropdownColor: AllColors().INPUT_GREY_BACKGROUND,
              value: selectedOption,
              hint: Text(AllText().OCCURS_ON),
              items: [
                AllText().k30mins,
                AllText().k2hours,
                AllText().k24hours,
                AllText().untilTurnedOff
              ].map((String option) {
                return DropdownMenuItem<String>(
                  value: option,
                  child: Text(option),
                );
              }).toList(),
              onChanged: (dynamic value) {
                setState(() {
                  textField = textField;
                  selectedOption = value;
                });
              },
            ),
          ),
          const Expanded(child: SizedBox()),
          Center(
            child: isLoading
                ? const CircularProgressIndicator()
                : CustomButton(
                    buttonText: AllText().SHARE,
                    onPressed: onShareTap,
                    fontColor: AllColors().WHITE,
                    width: 164,
                    height: 48,
                  ),
          ),
        ],
      ),
    );
  }

  void onShareTap() async {
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

    if (selectedOption == null) {
      CustomToast().show(AllText().SELECT_TIME, context, isError: true);
      return;
    }

    var minutes = (selectedOption == AllText().k30mins
        ? 30
        : (selectedOption == AllText().k2hours
            ? (2 * 60)
            : (selectedOption == AllText().k24hours ? (24 * 60) : null)));

    var result = await SharingLocationService()
        .sendShareLocationEvent(textField, false, minutes: minutes);

    if (result == null) {
      setState(() {
        isLoading = false;
      });
      Navigator.of(context).pop();
      return;
    }

    if (result == true) {
      CustomToast()
          .show(AllText().SHARE_LOC_REQ_SENT, context, isSuccess: true);
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
