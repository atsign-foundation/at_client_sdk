// ignore_for_file: avoid_unnecessary_containers

import 'package:at_common_flutter/widgets/custom_button.dart';
import 'package:at_events_flutter/models/event_notification.dart';
import 'package:at_events_flutter/services/event_services.dart';
import 'package:at_events_flutter/utils/colors.dart';
import 'package:at_events_flutter/utils/text_styles.dart';
import 'package:at_events_flutter/utils/texts.dart';
import 'package:flutter/material.dart';
import 'package:at_common_flutter/services/size_config.dart';

class ConcurrentEventRequest extends StatefulWidget {
  final String? reqEvent,
      reqInvitedPeopleCount,
      reqTimeAndDate,
      currentEvent,
      currentEventTimeAndDate;
  final EventNotificationModel? concurrentEvent;
  // ignore: use_key_in_widget_constructors
  const ConcurrentEventRequest(
      {this.reqEvent,
      this.reqInvitedPeopleCount,
      this.reqTimeAndDate,
      this.currentEvent,
      this.currentEventTimeAndDate,
      required this.concurrentEvent});

  @override
  _ConcurrentEventRequestState createState() => _ConcurrentEventRequestState();
}

class _ConcurrentEventRequestState extends State<ConcurrentEventRequest> {
  late bool isLoader;
  @override
  void initState() {
    super.initState();
    isLoader = false;
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
                    AllText().EVENT_RUNNING_DES,
                    textAlign: TextAlign.center,
                    style: CustomTextStyles().grey16,
                  ),
                  const Divider(
                    height: 2,
                  ),
                  SizedBox(height: 15.toHeight),
                  widget.concurrentEvent != null
                      ? Text(widget.concurrentEvent!.title!,
                          style: CustomTextStyles().black16)
                      : const SizedBox(),
                  widget.concurrentEvent != null
                      ? Text(
                          '${timeOfDayToString(widget.concurrentEvent!.event!.startTime!)} on ${dateToString(widget.concurrentEvent!.event!.date!)}',
                          style: CustomTextStyles().black14)
                      : const SizedBox(),
                  SizedBox(height: 20.toHeight),
                  !isLoader
                      ? CustomButton(
                          onPressed: () async {
                            setState(() {
                              isLoader = true;
                            });
                            await EventService().createEvent(
                                isEventOverlap: true, context: context);
                            if (mounted) {
                              setState(() {
                                isLoader = true;
                              });
                            }
                          },
                          buttonText: AllText().YES_CREATE_ANOTHER,
                          width: 278,
                          height: 48.toHeight,
                          buttonColor:
                              Theme.of(context).brightness == Brightness.light
                                  ? AllColors().Black
                                  : AllColors().WHITE,
                          fontColor:
                              Theme.of(context).brightness == Brightness.light
                                  ? AllColors().WHITE
                                  : AllColors().Black,
                        )
                      : const CircularProgressIndicator(),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      AllText().NO_CANCEL_THIS,
                      style: CustomTextStyles().black14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
