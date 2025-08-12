// ignore: must_be_immutable
// ignore_for_file: avoid_function_literals_in_foreach_calls, avoid_unnecessary_containers

import 'dart:typed_data';
import 'package:at_common_flutter/services/size_config.dart';
import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/services/contact_service.dart';
import 'package:at_events_flutter/common_components/bottom_sheet.dart';
import 'package:at_events_flutter/common_components/contacts_initials.dart';
import 'package:at_events_flutter/common_components/custom_button.dart';
import 'package:at_events_flutter/common_components/custom_toast.dart';
import 'package:at_events_flutter/common_components/event_time_selection.dart';
import 'package:at_events_flutter/models/event_key_location_model.dart';
import 'package:at_events_flutter/models/event_notification.dart';
import 'package:at_events_flutter/services/at_event_notification_listener.dart';
import 'package:at_events_flutter/services/contact_service.dart';
import 'package:at_events_flutter/services/event_key_stream_service.dart';
import 'package:at_events_flutter/services/event_services.dart';
import 'package:at_events_flutter/utils/colors.dart';
import 'package:at_events_flutter/utils/constants.dart';
import 'package:at_events_flutter/utils/text_styles.dart';
import 'package:at_events_flutter/utils/texts.dart';
import 'package:flutter/material.dart';

// ignore: must_be_immutable
class EventNotificationDialog extends StatefulWidget {
  String? event, invitedPeopleCount, timeAndDate, userName;
  final EventNotificationModel? eventData;
  bool showMembersCount;

  int? minutes;
  EventNotificationDialog(
      {Key? key,
      required this.eventData,
      this.event,
      this.invitedPeopleCount,
      this.timeAndDate,
      this.userName,
      this.showMembersCount = false})
      : super(key: key);

  @override
  _EventNotificationDialogState createState() =>
      _EventNotificationDialogState();
}

class _EventNotificationDialogState extends State<EventNotificationDialog> {
  int? minutes;
  EventNotificationModel? concurrentEvent;
  bool? isOverlap = false, loading = false;
  AtContact? contact;
  Uint8List? image;
  String? locationUserImageToShow;

  @override
  void initState() {
    if (widget.eventData != null) checkForEventOverlap();
    getEventCreator();
    super.initState();

    if (widget.eventData != null) {
      widget.showMembersCount = true;
    }
  }

  /// retrieves the event creator's details
  // ignore: always_declare_return_types
  getEventCreator() async {
    var contact = await getAtSignDetails(widget.eventData != null
        ? widget.eventData!.atsignCreator
        : locationUserImageToShow);
    // ignore: unnecessary_null_comparison
    if (contact != null) {
      if (contact.tags != null && contact.tags!['image'] != null) {
        List<int>? intList = contact.tags!['image'].cast<int>();
        setState(() {
          image = Uint8List.fromList(intList!);
        });
      }
    }
  }

  /// checks for event overlap with other events
  void checkForEventOverlap() {
    var allEventsExcludingCurrentEvent = <EventKeyLocationModel>[];
    var allSavedEvents = EventKeyStreamService().allEventNotifications;
    dynamic overlapData = [];

    allSavedEvents.forEach((event) {
      var keyMicrosecondId = event.eventNotificationModel!.key!
          .split('createevent-')[1]
          .split('@')[0];
      if (!event.eventNotificationModel!.key!.contains(keyMicrosecondId)) {
        allEventsExcludingCurrentEvent.add(event);
      }
    });
    overlapData = EventService().isEventTimeSlotOverlap(
        allEventsExcludingCurrentEvent
            .map((e) => e.eventNotificationModel)
            .toList(),
        widget.eventData);
    isOverlap = overlapData[0];
    if (isOverlap != null) {
      if (isOverlap == true) concurrentEvent = overlapData[1];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      child: AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(10, 20, 5, 10),
        content: Container(
          child: SingleChildScrollView(
            child: Container(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Text(
                      '${widget.eventData!.atsignCreator} ${AllText().SHARE_EVENT_DES}',
                      style: CustomTextStyles().grey16,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 30),
                  Stack(
                    children: [
                      image != null
                          ? ClipRRect(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(30.toFont)),
                              child: Image.memory(
                                image!,
                                width: 50.toFont,
                                height: 50.toFont,
                                fit: BoxFit.fill,
                              ),
                            )
                          : ContactInitial(
                              initials: widget.eventData != null
                                  ? widget.eventData!.atsignCreator
                                  : locationUserImageToShow,
                              size: 60,
                            ),
                      widget.showMembersCount
                          ? Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 30.toFont,
                                height: 30.toFont,
                                decoration: BoxDecoration(
                                  color: AllColors().BLUE,
                                  borderRadius:
                                      BorderRadius.circular(20.toFont),
                                ),
                                child: Center(
                                    child: Text(
                                  '+${widget.eventData!.group!.members!.length}',
                                  style: CustomTextStyles().black10,
                                )),
                              ),
                            )
                          : const SizedBox()
                    ],
                  ),
                  SizedBox(height: widget.eventData != null ? 10.toHeight : 0),
                  (ContactService().contactList.indexWhere((element) =>
                              element.atSign ==
                              widget.eventData!.atsignCreator) ==
                          -1)
                      ? Text(
                          'NOTE: ${widget.eventData!.atsignCreator} is not in your contacts list.',
                          style: CustomTextStyles().red12,
                        )
                      : const SizedBox(),
                  SizedBox(height: 10.toHeight),
                  widget.eventData != null
                      ? Text(
                          widget.eventData!.title!,
                          style: CustomTextStyles().black18,
                          textAlign: TextAlign.center,
                        )
                      : const SizedBox(),
                  SizedBox(height: widget.eventData != null ? 5.toHeight : 0),
                  widget.eventData != null
                      ? Text(
                          (widget.eventData!.group!.members!.length == 1)
                              ? '${widget.eventData!.group!.members!.length} ${AllText().PER_INVITED}'
                              : '${widget.eventData!.group!.members!.length} ${AllText().PEP_INVITED}',
                          style: CustomTextStyles().grey14)
                      : const SizedBox(),
                  SizedBox(height: widget.eventData != null ? 10.toHeight : 0),
                  widget.eventData != null
                      ? Text(
                          '${timeOfDayToString(widget.eventData!.event!.startTime!)} on ${dateToString(widget.eventData!.event!.date!)}',
                          style: CustomTextStyles().black14)
                      : const SizedBox(),
                  isOverlap! ? SizedBox(height: 10.toHeight) : const SizedBox(),
                  isOverlap! ? const Divider(height: 2) : const SizedBox(),
                  SizedBox(height: 10.toHeight),
                  isOverlap!
                      ? Text(
                          AllText().EVENT_RUNNING_DES,
                          textAlign: TextAlign.center,
                          style: CustomTextStyles().grey16,
                        )
                      : const SizedBox(),
                  SizedBox(height: 10.toHeight),
                  isOverlap!
                      ? Text(concurrentEvent!.title!,
                          style: CustomTextStyles().black18)
                      : const SizedBox(),
                  SizedBox(height: 5.toHeight),
                  SizedBox(height: 10.toHeight),
                  isOverlap!
                      ? Text(
                          '${timeOfDayToString(concurrentEvent!.event!.startTime!)} on ${dateToString(concurrentEvent!.event!.date!)}',
                          style: CustomTextStyles().black14)
                      : const SizedBox(),
                  SizedBox(height: 10.toHeight),
                  loading!
                      ? const CircularProgressIndicator()
                      : CustomButton(
                          onTap: () => () async {
                            bottomSheet(
                                context,
                                EventTimeSelection(
                                    eventNotificationModel: widget.eventData,
                                    title: AllText().LOC_START_TIME_TITLE,
                                    isStartTime: true,
                                    options: MixedConstants.startTimeOptions,
                                    onSelectionChanged: (dynamic startTime) {
                                      widget.eventData!.group!.members!
                                          .forEach((groupMember) {
                                        if (groupMember.atSign ==
                                            AtEventNotificationListener()
                                                .currentAtSign) {
                                          groupMember.tags!['shareFrom'] =
                                              startTime.toString();
                                        }
                                      });

                                      bottomSheet(
                                          context,
                                          EventTimeSelection(
                                            eventNotificationModel:
                                                widget.eventData,
                                            title: AllText().LOC_END_TIME_TITLE,
                                            options:
                                                MixedConstants.endTimeOptions,
                                            onSelectionChanged:
                                                (dynamic endTime) async {
                                              startLoading();

                                              widget.eventData!.group!.members!
                                                  .forEach((groupMember) {
                                                if (groupMember.atSign ==
                                                    AtEventNotificationListener()
                                                        .currentAtSign) {
                                                  groupMember.tags!['shareTo'] =
                                                      endTime.toString();
                                                }
                                              });

                                              /// For inner bottomsheet
                                              Navigator.of(context).pop();

                                              /// For outer bottomsheet
                                              Navigator.of(context).pop();

                                              // updateEvent(widget.eventData);
                                              var result =
                                                  await EventKeyStreamService()
                                                      .actionOnEvent(
                                                          widget.eventData!,
                                                          ATKEY_TYPE_ENUM
                                                              .ACKNOWLEDGEEVENT,
                                                          isAccepted: true,
                                                          isSharing: true,
                                                          isExited: false);

                                              if (result == true) {
                                                CustomToast().show(
                                                    AllText()
                                                        .REQ_TO_UPDATE_DATA_SUB,
                                                    AtEventNotificationListener()
                                                        .navKey!
                                                        .currentContext,
                                                    isSuccess: true);
                                              } else {
                                                CustomToast().show(
                                                    AllText()
                                                        .SOMETHING_WENT_WRONG_TRY_AGAIN,
                                                    AtEventNotificationListener()
                                                        .navKey!
                                                        .currentContext,
                                                    isError: true);
                                              }

                                              stopLoading();

                                              /// For dialog box
                                              Navigator.of(context).pop();
                                            },
                                          ),
                                          400);
                                    }),
                                400);
                          }(),
                          bgColor: AllColors().Black,
                          width: 164,
                          height: 48.toHeight,
                          child: Text(AllText().YES,
                              style: TextStyle(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  fontSize: 15.toFont)),
                        ),
                  SizedBox(height: 10.toHeight),
                  loading!
                      ? const SizedBox()
                      : InkWell(
                          onTap: () async {
                            startLoading();
                            var result = await EventKeyStreamService()
                                .actionOnEvent(widget.eventData!,
                                    ATKEY_TYPE_ENUM.ACKNOWLEDGEEVENT,
                                    isSharing: false,
                                    isAccepted: false,
                                    isExited: true);

                            if (result == true) {
                              CustomToast().show(
                                  AllText().REQ_TO_UPDATE_DATA_SUB,
                                  AtEventNotificationListener()
                                      .navKey!
                                      .currentContext,
                                  isSuccess: true);
                            } else {
                              CustomToast().show(
                                  AllText().SOMETHING_WENT_WRONG_TRY_AGAIN,
                                  AtEventNotificationListener()
                                      .navKey!
                                      .currentContext,
                                  isError: true);
                            }

                            /// For dialog box
                            Navigator.of(context).pop();

                            stopLoading();
                          },
                          child: Text(
                            AllText().NO,
                            style: CustomTextStyles().black14,
                          ),
                        ),
                  loading! ? const SizedBox() : SizedBox(height: 10.toHeight),
                  loading!
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
          ),
        ),
      ),
    );
  }

  /// starts the loading state
  void startLoading() {
    if (mounted) {
      setState(() {
        loading = true;
      });
    }
  }

  /// stops the loading state
  void stopLoading() {
    if (mounted) {
      setState(() {
        loading = false;
      });
    }
  }
}
