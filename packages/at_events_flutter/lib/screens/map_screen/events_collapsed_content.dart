// ignore_for_file: avoid_unnecessary_containers

import 'package:at_common_flutter/services/size_config.dart';
import 'package:at_events_flutter/at_events_flutter.dart';
import 'package:at_events_flutter/common_components/bottom_sheet.dart';
import 'package:at_events_flutter/common_components/custom_toast.dart';
import 'package:at_events_flutter/common_components/draggable_symbol.dart';
import 'package:at_events_flutter/common_components/loading_widget.dart';
import 'package:at_events_flutter/models/event_notification.dart';
import 'package:at_events_flutter/services/at_event_notification_listener.dart';
import 'package:at_events_flutter/utils/colors.dart';
import 'package:at_events_flutter/utils/text_styles.dart';
import 'package:at_events_flutter/utils/texts.dart';
import 'package:flutter/material.dart';
import 'package:at_location_flutter/common_components/confirmation_dialog.dart';
import 'participants.dart';

// ignore: must_be_immutable
class EventsCollapsedContent extends StatefulWidget {
  late EventNotificationModel eventListenerKeyword;
  late bool isStatic; // true when no clicks should work
  EventsCollapsedContent(this.eventListenerKeyword,
      {Key? key, this.isStatic = false})
      : super(key: key);

  @override
  _EventsCollapsedContentState createState() => _EventsCollapsedContentState();
}

class _EventsCollapsedContentState extends State<EventsCollapsedContent> {
  bool isExited = false;
  bool isSharingEvent = true, isAdmin = false, isCancelled = false;
  var currentAtSign = AtEventNotificationListener().currentAtSign;

  late EventNotificationModel eventListenerKeyword;

  @override
  void initState() {
    eventListenerKeyword = widget.eventListenerKeyword;
    isAdmin = eventListenerKeyword.atsignCreator == currentAtSign;

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    var _myEventInfo = HomeEventService().getMyEventInfo(eventListenerKeyword);
    isCancelled = HomeEventService().isEventCancelled(eventListenerKeyword);

    if (_myEventInfo != null) {
      isSharingEvent = _myEventInfo.isSharing;
      isExited = _myEventInfo.isExited;
    }

    return Container(
      height: 431,
      padding: const EdgeInsets.fromLTRB(15, 3, 15, 0),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(10.0), topRight: Radius.circular(10.0)),
        color: AllColors().WHITE,
        boxShadow: [
          BoxShadow(
            color: AllColors().DARK_GREY,
            blurRadius: 10.0,
            spreadRadius: 1.0,
            offset: const Offset(0.0, 0.0),
          )
        ],
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const DraggableSymbol(),
            const SizedBox(height: 3),
            Container(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          eventListenerKeyword.title!,
                          style: TextStyle(
                              color: AllColors().Black, fontSize: 18.toFont),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      !widget.isStatic && isAdmin
                          ? InkWell(
                              onTap: () {
                                bottomSheet(
                                  AtEventNotificationListener()
                                      .navKey!
                                      .currentContext!,
                                  CreateEvent(
                                    AtEventNotificationListener()
                                        .atClientManager,
                                    isUpdate: true,
                                    eventData: eventListenerKeyword,
                                    onEventSaved: (event) {},
                                  ),
                                  SizeConfig().screenHeight * 0.9,
                                );
                              },
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(AllText().EDIT,
                                      style: CustomTextStyles().orange16),
                                  Icon(Icons.edit, color: AllColors().ORANGE)
                                ],
                              ),
                            )
                          : const SizedBox()
                    ],
                  ),
                  Text(
                    '${eventListenerKeyword.atsignCreator}',
                    style: CustomTextStyles().black14,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(
                    height: 3,
                  ),
                  Text(
                    dateToString(eventListenerKeyword.event!.date!),
                    style: CustomTextStyles().darkGrey14,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(
                    height: 3,
                  ),
                  Text(
                    '${timeOfDayToString(eventListenerKeyword.event!.startTime!)} - ${timeOfDayToString(eventListenerKeyword.event!.endTime!)}',
                    style: CustomTextStyles().darkGrey14,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Divider(),
                  DisplayTile(
                    title:
                        '${eventListenerKeyword.atsignCreator} ${AllText().AND} ${eventListenerKeyword.group!.members!.length} ${AllText().MORE}',
                    atsignCreator: eventListenerKeyword.atsignCreator,
                    semiTitle: (eventListenerKeyword.group!.members!.length ==
                            1)
                        ? '${eventListenerKeyword.group!.members!.length} ${AllText().PERSON}'
                        : '${eventListenerKeyword.group!.members!.length} ${AllText().PEOPLE}',
                    number: eventListenerKeyword.group!.members!.length,
                    subTitle:
                        '${AllText().SHARE_MY_LOCATION_FROM} ${timeOfDayToString(eventListenerKeyword.event!.startTime!)} ${AllText().ON} ${dateToString(eventListenerKeyword.event!.date!)}',
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: () => bottomSheet(
                  AtEventNotificationListener().navKey!.currentContext!,
                  Participants(
                    eventListenerKeyword,
                    key: UniqueKey(),
                  ),
                  422),
              child: Text(
                AllText().SEE_PARTICIPANTS,
                style: CustomTextStyles().orange14,
              ),
            ),
            const Divider(),
            Flexible(
                child: RichText(
              text: TextSpan(
                text: AllText().ADDRESS,
                style: CustomTextStyles().darkGrey16,
                children: [
                  TextSpan(
                    text: ' ${eventListenerKeyword.venue!.label}',
                    style: CustomTextStyles().darkGrey14,
                  )
                ],
              ),
            )),
            widget.isStatic ? const SizedBox() : const Divider(),
            widget.isStatic
                ? const SizedBox()
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AllText().SHARE_LOCATION,
                        style: CustomTextStyles().darkGrey16,
                      ),
                      Switch(
                          value: isSharingEvent,
                          onChanged: (value) async {
                            if (isCancelled || isExited) {
                              CustomToast().show(
                                  isCancelled
                                      ? AllText().EVENT_CANCELLED
                                      : AllText().EVENT_EXITED,
                                  AtEventNotificationListener()
                                      .navKey!
                                      .currentContext,
                                  isError: true);
                              return;
                            }

                            LoadingDialog().show(text: AllText().UPDATING_DATA);
                            try {
                              // if (isAdmin) {
                              //   LocationService().eventListenerKeyword.isSharing =
                              //       value;
                              // }

                              var result =
                                  await EventKeyStreamService().actionOnEvent(
                                eventListenerKeyword,
                                isAdmin
                                    ? ATKEY_TYPE_ENUM.CREATEEVENT
                                    : ATKEY_TYPE_ENUM.ACKNOWLEDGEEVENT,
                                isSharing: value,
                                isAccepted: true,
                                isExited: false,
                              );
                              if (result == true) {
                                // CustomToast().show(
                                //     'Request to update data is submitted',
                                //     AtEventNotificationListener()
                                //         .navKey!
                                //         .currentContext,
                                //     isSuccess: true);
                              } else {
                                CustomToast().show(
                                    AllText().SOMETHING_WENT_WRONG_TRY_AGAIN,
                                    AtEventNotificationListener()
                                        .navKey!
                                        .currentContext,
                                    isError: true);
                              }
                              setState(() {});
                              LoadingDialog().hide();
                            } catch (e) {
                              CustomToast().show(
                                  AllText().SOMETHING_WENT_WRONG_TRY_AGAIN,
                                  AtEventNotificationListener()
                                      .navKey!
                                      .currentContext,
                                  isError: true);
                              LoadingDialog().hide();
                            }
                          })
                    ],
                  ),
            widget.isStatic ? const SizedBox() : const Divider(),
            (widget.isStatic || isAdmin)
                ? const SizedBox()
                : Expanded(
                    child: InkWell(
                      onTap: () async {
                        if (isCancelled) {
                          CustomToast().show(
                              AllText().EVENT_CANCELLED,
                              AtEventNotificationListener()
                                  .navKey!
                                  .currentContext,
                              isError: true);
                          return;
                        }

                        if (!isExited) {
                          await confirmationDialog(
                              '${AllText().DO_YOU_WANT_TO_EXIT} ${widget.eventListenerKeyword.title}?',
                              onYesPressed: _exitEvent);
                        }
                      },
                      child: Text(
                        isExited ? AllText().EXITED : AllText().EXIT_EVENT,
                        style: CustomTextStyles().orange16,
                      ),
                    ),
                  ),
            (widget.isStatic || isAdmin) ? const SizedBox() : const Divider(),
            (!widget.isStatic && isAdmin)
                ? Expanded(
                    child: InkWell(
                      onTap: () async {
                        if (!isCancelled) {
                          await confirmationDialog(
                              '${AllText().DO_YOU_WANT_TO_CANCEL} ${widget.eventListenerKeyword.title}?',
                              onYesPressed: _cancelEvent);
                        }
                      },
                      child: Text(
                        isCancelled
                            ? AllText().EVENT_CANCELLED
                            : AllText().CANCEL_EVENT,
                        style: CustomTextStyles().orange16,
                      ),
                    ),
                  )
                : const SizedBox()
            //   ],
            // ),
          ]),
    );
  }

  /// cancels an event
  _cancelEvent() async {
    LoadingDialog().show(text: AllText().CANCELLING);
    try {
      var result = await EventKeyStreamService().actionOnEvent(
        eventListenerKeyword,
        ATKEY_TYPE_ENUM.CREATEEVENT,
        isCancelled: true,
        isAccepted: false,
        isExited: true,
        isSharing: false,
      );
      if (result == true) {
      } else {
        CustomToast().show(AllText().SOMETHING_WENT_WRONG_TRY_AGAIN,
            AtEventNotificationListener().navKey!.currentContext,
            isError: true);
      }
      setState(() {});
      LoadingDialog().hide();
      Navigator.of(AtEventNotificationListener().navKey!.currentContext!).pop();
    } catch (e) {
      CustomToast().show(AllText().SOMETHING_WENT_WRONG_TRY_AGAIN,
          AtEventNotificationListener().navKey!.currentContext,
          isError: true);
      LoadingDialog().hide();
    }
  }

  /// exits an event
  _exitEvent() async {
    //if member has not exited then only following code will run.
    LoadingDialog().show(text: AllText().EXITING);
    try {
      var result = await EventKeyStreamService().actionOnEvent(
        eventListenerKeyword,
        isAdmin
            ? ATKEY_TYPE_ENUM.CREATEEVENT
            : ATKEY_TYPE_ENUM.ACKNOWLEDGEEVENT,
        isExited: true,
        isAccepted: false,
        isSharing: false,
      );
      if (result == true) {
      } else {
        CustomToast().show(AllText().SOMETHING_WENT_WRONG_TRY_AGAIN,
            AtEventNotificationListener().navKey!.currentContext,
            isError: true);
      }
      setState(() {});
      LoadingDialog().hide();
      Navigator.of(AtEventNotificationListener().navKey!.currentContext!).pop();
    } catch (e) {
      CustomToast().show(AllText().SOMETHING_WENT_WRONG_TRY_AGAIN,
          AtEventNotificationListener().navKey!.currentContext,
          isError: true);
      LoadingDialog().hide();
    }
  }
}
