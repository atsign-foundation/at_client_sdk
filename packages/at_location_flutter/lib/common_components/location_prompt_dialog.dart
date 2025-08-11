import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_location_flutter/location_modal/location_notification.dart';
import 'package:at_location_flutter/service/at_location_notification_listener.dart';
import 'package:at_location_flutter/service/request_location_service.dart';
import 'package:at_location_flutter/service/sharing_location_service.dart';
import 'package:at_location_flutter/utils/constants/text_strings.dart';
import 'package:at_location_flutter/utils/constants/text_styles.dart';
import 'package:flutter/material.dart';

import 'custom_toast.dart';

/// Displays a location prompt dialog
Future<void> locationPromptDialog(
    {String? text,
    String? yesText,
    String? noText,
    required bool isShareLocationData,
    required bool isRequestLocationData,
    bool onlyText = false,
    LocationNotificationModel? locationNotificationModel}) {
  var value = showDialog<void>(
    context: AtLocationNotificationListener().navKey.currentContext!,
    barrierDismissible: true,
    builder: (BuildContext context) {
      return LocationPrompt(
          text: text,
          yesText: yesText,
          noText: noText,
          onlyText: onlyText,
          isShareLocationData: isShareLocationData,
          isRequestLocationData: isRequestLocationData,
          locationNotificationModel: locationNotificationModel);
    },
  );
  return value;
}

class LocationPrompt extends StatefulWidget {
  final String? text, yesText, noText;
  final bool isShareLocationData, isRequestLocationData, onlyText;
  final LocationNotificationModel? locationNotificationModel;

  const LocationPrompt(
      {Key? key,
      this.text,
      this.yesText,
      this.noText,
      this.onlyText = false,
      required this.isShareLocationData,
      required this.isRequestLocationData,
      this.locationNotificationModel})
      : super(key: key);

  @override
  _LocationPromptState createState() => _LocationPromptState();
}

class _LocationPromptState extends State<LocationPrompt> {
  late bool loading;

  @override
  void initState() {
    loading = false;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: SizeConfig().screenWidth * 0.8,
      child: AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(15, 30, 15, 20),
        content: SingleChildScrollView(
          child: Container(
            child: widget.onlyText
                ? Column(
                    children: [
                      Text(
                        widget.text ?? '...',
                        style: CustomTextStyles().grey16,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),
                      CustomButton(
                        onPressed: () => Navigator.of(context).pop(),
                        buttonText: AllText().OKAY,
                        fontColor: Colors.white,
                        width: 100.toWidth,
                        height: 48.toHeight,
                      )
                    ],
                  )
                : Column(
                    children: <Widget>[
                      Text(
                        widget.text!,
                        style: CustomTextStyles().grey16,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),
                      loading
                          ? const Center(
                              child: CircularProgressIndicator(),
                            )
                          : CustomButton(
                              onPressed: () async {
                                setState(() {
                                  loading = true;
                                });

                                if (widget.isShareLocationData) {
                                  await updateShareLocation();
                                } else if (widget.isRequestLocationData) {
                                  await updateRequestLocation();
                                }

                                if (mounted) {
                                  setState(() {
                                    loading = false;
                                  });
                                }

                                Navigator.of(AtLocationNotificationListener()
                                        .navKey
                                        .currentContext!)
                                    .pop();
                              },
                              buttonText: widget.yesText ?? '${AllText().YES}!',
                              fontColor: Colors.white,
                              width: 164.toWidth,
                              height: 48.toHeight,
                            ),
                      const SizedBox(height: 10),
                      CustomButton(
                        onPressed: () async {
                          if (widget.isShareLocationData) {
                            CustomToast()
                                .show(AllText().UPDATE_CANCELLED, context);
                          } else if (widget.isRequestLocationData) {
                            CustomToast()
                                .show(AllText().PROMPT_CANCELLED, context);
                          }
                          Navigator.of(context).pop();
                        },
                        buttonText: widget.noText ?? '${AllText().NO}!',
                        buttonColor: Colors.white,
                        fontColor: Colors.black,
                        width: 164.toWidth,
                        height: 48.toHeight,
                      )
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// Updates the sharing location status and sends an acknowledgement
  Future<void> updateShareLocation() async {
    var update = await SharingLocationService()
        .updateWithShareLocationAcknowledge(widget.locationNotificationModel!,
            rePrompt: widget.locationNotificationModel!.rePrompt,
            shouldCheckForTimeChanges: true);

    if (update) {
      CustomToast().show(
          '${AllText().SHARE_LOC_REQ_SENT_TO} ${widget.locationNotificationModel!.receiver}',
          context,
          isSuccess: true);
    } else {
      CustomToast().show(
          '${AllText().SOMETHING_WENT_WRONG_FOR} ${widget.locationNotificationModel!.receiver}',
          context,
          isError: true);
    }
  }

  /// Updates the request location status and sends an acknowledgement
  Future<void> updateRequestLocation() async {
    var update = await RequestLocationService()
        .updateWithRequestLocationAcknowledge(widget.locationNotificationModel!,
            rePrompt: widget.locationNotificationModel!.rePrompt);

    if (update) {
      CustomToast().show(
          '${AllText().PROMPTED_AGAIN_TO} ${widget.locationNotificationModel!.atsignCreator}',
          context,
          isSuccess: true);
    } else {
      CustomToast().show(
          '${AllText().SOMETHING_WENT_WRONG_FOR} ${widget.locationNotificationModel!.atsignCreator}',
          context,
          isError: true);
    }
  }
}
