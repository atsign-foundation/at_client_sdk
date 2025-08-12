import 'dart:typed_data';
import 'package:at_common_flutter/widgets/custom_button.dart';
import 'package:at_contact/at_contact.dart';
import 'package:at_location_flutter/common_components/bottom_sheet.dart';
import 'package:at_location_flutter/common_components/contacts_initial.dart';
import 'package:at_location_flutter/common_components/text_tile_repeater.dart';
import 'package:at_location_flutter/location_modal/location_notification.dart';
import 'package:at_location_flutter/service/at_location_notification_listener.dart';
import 'package:at_location_flutter/service/contact_service.dart';
import 'package:at_location_flutter/service/request_location_service.dart';
import 'package:at_location_flutter/service/sharing_location_service.dart';
import 'package:at_location_flutter/utils/constants/colors.dart';
import 'package:at_location_flutter/utils/constants/text_strings.dart';
import 'package:at_location_flutter/utils/constants/text_styles.dart';
import 'package:flutter/material.dart';
import 'package:at_common_flutter/services/size_config.dart';
import 'package:at_contacts_flutter/services/contact_service.dart';

// ignore: must_be_immutable
class NotificationDialog extends StatefulWidget {
  String? userName;
  final LocationNotificationModel? locationData;
  final bool showMembersCount;

  int? minutes;
  NotificationDialog(
      {Key? key,
      this.locationData,
      this.userName,
      this.showMembersCount = false})
      : super(key: key);

  @override
  _NotificationDialogState createState() => _NotificationDialogState();
}

class _NotificationDialogState extends State<NotificationDialog> {
  int? minutes;
  AtContact? contact;
  Uint8List? image;
  String? locationUserImageToShow;
  bool loading = false;

  @override
  void initState() {
    locationUserImageToShow = (widget.locationData!.atsignCreator ==
            AtLocationNotificationListener().currentAtSign
        ? widget.locationData!.receiver
        : widget.locationData!.atsignCreator);

    widget.userName = locationUserImageToShow;
    getEventCreator();

    super.initState();
  }

  void getEventCreator() async {
    var contact = await getAtSignDetails(locationUserImageToShow);
    // ignore: unnecessary_null_comparison
    if (contact != null) {
      if (contact.tags != null && contact.tags!['image'] != null) {
        List<int>? intList = contact.tags!['image'].cast<int>();
        if (mounted) {
          setState(() {
            image = Uint8List.fromList(intList!);
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(10, 20, 5, 10),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Text(
                ((!widget.locationData!.isRequest)
                    ? '${widget.userName} ${AllText().ACCEPT_SHARE_LOCATION}'
                    : '${widget.userName} ${AllText().SHARE_YOUR_LOCATION}'),
                style: CustomTextStyles().grey16,
                textAlign: TextAlign.center),
            const SizedBox(height: 30),
            Stack(
              children: [
                image != null
                    ? ClipRRect(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(30)),
                        child: Image.memory(
                          image!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.fill,
                        ),
                      )
                    : ContactInitial(
                        initials: locationUserImageToShow,
                        size: 60,
                      ),
                widget.showMembersCount
                    ? Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AllColors().BLUE,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                              child: Text(
                            '+10',
                            style: CustomTextStyles().black10,
                          )),
                        ),
                      )
                    : const SizedBox()
              ],
            ),
            SizedBox(height: 10.toHeight),
            (ContactService().contactList.indexWhere(
                        (element) => element.atSign == widget.userName) ==
                    -1)
                ? Text(
                    'NOTE: ${widget.userName} is not in your contacts list.',
                    style: CustomTextStyles().red12,
                  )
                : const SizedBox(),
            SizedBox(height: 10.toHeight),
            loading
                ? const CircularProgressIndicator()
                : CustomButton(
                    onPressed: () => () async {
                      // ignore: unnecessary_statements
                      ((!widget.locationData!.isRequest)
                          ? {
                              startLoading(),
                              await SharingLocationService()
                                  .shareLocationAcknowledgment(
                                      widget.locationData!, true),
                              stopLoading(),
                              Navigator.of(context).pop(),
                            }
                          : {
                              startLoading(),
                              timeSelect(context),
                            });
                    }(),
                    buttonText: AllText().YES,
                    buttonColor: AllColors().Black,
                    fontColor: AllColors().WHITE,
                    width: 164.toWidth,
                    height: 48.toHeight,
                  ),
            const SizedBox(height: 5),
            loading
                ? const SizedBox()
                : CustomButton(
                    onPressed: () => () async {
                      // ignore: unnecessary_statements
                      ((!widget.locationData!.isRequest)
                          ? {
                              startLoading(),
                              await SharingLocationService()
                                  .shareLocationAcknowledgment(
                                      widget.locationData!, false),
                              stopLoading(),
                              Navigator.of(context).pop(),
                            }
                          : {
                              startLoading(),
                              await RequestLocationService()
                                  .requestLocationAcknowledgment(
                                      widget.locationData!, false,
                                      sendAck: true),
                              stopLoading(),
                              Navigator.of(context).pop(),
                            });
                    }(),
                    buttonText: AllText().NO,
                    buttonColor: AllColors().WHITE,
                    fontColor: AllColors().Black,
                    width: 164.toWidth,
                    height: 48.toHeight,
                  ),
            loading ? const SizedBox() : SizedBox(height: 10.toHeight),
            loading
                ? const SizedBox()
                : InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                    },
                    child: Text(AllText().DECIDE_LATER,
                        style: CustomTextStyles().orange14,
                        textAlign: TextAlign.center),
                  ),
          ],
        ),
      ),
    );
  }

  void timeSelect(BuildContext context) {
    int? result;
    bottomSheet(
        context,
        TextTileRepeater(
          title: AllText().HOW_LONG_DO_YOU_WANT_SHARE_YOUR_LOCATION,
          options: [
            AllText().k30mins, AllText().k2hours, AllText().k24hours,
            // , 'Until turned off'
          ],
          onChanged: (value) {
            result = (value == AllText().k30mins
                ? 30
                : (value == AllText().k2hours
                    ? (2 * 60)
                    : (value == AllText().k24hours
                        ? (24 * 60)
                        : (value == AllText().untilTurnedOff
                            ? (24 * 60)
                            : null))));
          },
        ),
        350, onSheetCLosed: () async {
      if (result != null) {
        /// so, that we dont send location when nothing is pressed
        if (result == (24 * 60)) {
          result = null;
        }
        await RequestLocationService().requestLocationAcknowledgment(
            widget.locationData!, true,
            minutes: result, sendAck: true);
      }

      stopLoading();
      Navigator.of(context).pop();
      return result;
    });
  }

  void startLoading() {
    if (mounted) {
      setState(() {
        loading = true;
      });
    }
  }

  void stopLoading() {
    if (mounted) {
      setState(() {
        loading = false;
      });
    }
  }
}
