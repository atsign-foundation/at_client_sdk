import 'dart:convert';

import 'package:at_common_flutter/services/size_config.dart';
import 'package:at_common_flutter/widgets/custom_button.dart';
import 'package:at_common_flutter/widgets/custom_input_field.dart';
import 'package:at_events_flutter/common_components/custom_heading.dart';
import 'package:at_events_flutter/common_components/custom_toast.dart';
import 'package:at_events_flutter/models/event_notification.dart';
import 'package:at_events_flutter/services/event_services.dart';
import 'package:at_events_flutter/utils/colors.dart';
import 'package:at_events_flutter/utils/text_styles.dart';
import 'package:at_events_flutter/utils/texts.dart';
import 'package:flutter/material.dart';

class RecurringEvent extends StatefulWidget {
  const RecurringEvent({Key? key}) : super(key: key);

  @override
  _RecurringEventState createState() => _RecurringEventState();
}

class _RecurringEventState extends State<RecurringEvent> {
  late List<String> repeatOccurance;
  late List<String> occursOnOptions;
  late bool isRepeatEveryWeek;
  EventNotificationModel? eventData;

  @override
  void initState() {
    super.initState();
    repeatOccurance = repeatOccuranceOptions;
    occursOnOptions = occursOnWeekOptions;
    eventData = EventNotificationModel.fromJson(jsonDecode(
        EventNotificationModel.convertEventNotificationToJson(
            EventService().eventNotificationModel!)));
    if (eventData!.event!.repeatCycle != null) {
      if (eventData!.event!.repeatCycle == RepeatCycle.MONTH) {
        isRepeatEveryWeek = false;
      } else if (eventData!.event!.repeatCycle == RepeatCycle.WEEK) {
        isRepeatEveryWeek = true;
      }
    } else {
      isRepeatEveryWeek = false;
      eventData!.event!.repeatCycle = RepeatCycle.MONTH;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: SizeConfig().screenHeight * 0.8,
      padding: const EdgeInsets.all(25),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CustomHeading(
                heading: AllText().RECURRING_EVENT, action: AllText().CANCEL),
            const SizedBox(height: 25),
            Text(AllText().REPEAT_EVERY, style: CustomTextStyles().greyLabel14),
            SizedBox(height: 6.toHeight),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                CustomInputField(
                  width: 155.toWidth,
                  height: 50.toHeight,
                  hintText: AllText().REPEAT_CYCLE,
                  icon: Icons.keyboard_arrow_down,
                  initialValue: eventData!.event!.repeatDuration != null
                      ? eventData!.event!.repeatDuration.toString()
                      : '',
                  value: (val) {
                    if (val.trim().isNotEmpty) {
                      var repeatCycle = int.parse(val);
                      eventData!.event!.repeatDuration = repeatCycle;
                    } else {
                      eventData!.event!.repeatDuration = null;
                    }
                  },
                ),
                Container(
                  color: AllColors().INPUT_GREY_BACKGROUND,
                  width: 155.toWidth,
                  padding: const EdgeInsets.only(left: 10, right: 10),
                  child: DropdownButton(
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down),
                    underline: const SizedBox(),
                    elevation: 0,
                    dropdownColor: AllColors().INPUT_GREY_BACKGROUND,
                    value: (eventData!.event!.repeatCycle != null)
                        ? eventData!.event!.repeatCycle == RepeatCycle.WEEK
                            ? AllText().WEEK
                            : eventData!.event!.repeatCycle == RepeatCycle.MONTH
                                ? AllText().MONTH
                                : null
                        : null,
                    hint: Text(AllText().SELECT_CATEGORY),
                    items: repeatOccurance.map((String option) {
                      return DropdownMenuItem<String>(
                        value: option,
                        child: Text(option),
                      );
                    }).toList(),
                    onChanged: (String? selectedOption) {
                      switch (selectedOption) {
                        case 'Week':
                          eventData!.event!.repeatCycle = RepeatCycle.WEEK;
                          isRepeatEveryWeek = true;
                          break;

                        case 'Month':
                          eventData!.event!.repeatCycle = RepeatCycle.MONTH;
                          isRepeatEveryWeek = false;
                          break;
                      }

                      setState(() {});
                    },
                  ),
                )
              ],
            ),
            SizedBox(height: 25.toHeight),
            Text(AllText().OCCURS_ON, style: CustomTextStyles().greyLabel14),
            SizedBox(height: 6.toHeight),
            isRepeatEveryWeek
                ? Container(
                    color: AllColors().INPUT_GREY_BACKGROUND,
                    width: 350.toWidth,
                    padding: const EdgeInsets.only(left: 10, right: 10),
                    child: DropdownButton(
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down),
                      underline: const SizedBox(),
                      elevation: 0,
                      dropdownColor: AllColors().INPUT_GREY_BACKGROUND,
                      value: eventData!.event!.occursOn != null
                          ? getWeekString(eventData!.event!.occursOn)
                          : null,
                      hint: Text(AllText().OCCURS_ON),
                      items: occursOnOptions.map((String option) {
                        return DropdownMenuItem<String>(
                          value: option,
                          child: Text(option),
                        );
                      }).toList(),
                      onChanged: (String? selectedOption) {
                        var weekday = getWeekEnum(selectedOption);
                        // ignore: unnecessary_null_comparison
                        if (weekday != null) {
                          eventData!.event!.occursOn = weekday;
                        }

                        setState(() {});
                      },
                    ),
                  )
                : CustomInputField(
                    width: 350.toWidth,
                    height: 50.toHeight,
                    isReadOnly: true,
                    hintText: AllText().OCCURS_ON,
                    icon: Icons.access_time,
                    initialValue: eventData!.event!.date != null
                        ? dateToString(eventData!.event!.date!)
                        : '',
                    onTap: () async {
                      final datePicked = await showDatePicker(
                        context: context,
                        initialDate: (eventData!.event!.date != null)
                            ? eventData!.event!.date!
                            : DateTime.now(),
                        firstDate: DateTime(2015, 8),
                        lastDate: DateTime(2101),
                      );

                      if (datePicked != null) {
                        eventData!.event!.date = datePicked;
                        setState(() {});
                      }
                    },
                    value: (val) {},
                  ),
            SizedBox(height: 25.toHeight),
            Text(AllText().SELECT_TIME, style: CustomTextStyles().greyLabel14),
            SizedBox(height: 6.toHeight),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                CustomInputField(
                  width: 155.toWidth,
                  height: 50.toHeight,
                  isReadOnly: true,
                  hintText: AllText().START,
                  icon: Icons.access_time,
                  initialValue: eventData!.event!.startTime != null
                      ? timeOfDayToString(eventData!.event!.startTime!)
                      : '',
                  onTap: () async {
                    final timePicked = await showTimePicker(
                        context: context,
                        initialTime: eventData!.event!.startTime != null
                            ? TimeOfDay.fromDateTime(
                                eventData!.event!.startTime!)
                            : TimeOfDay.now(),
                        initialEntryMode: TimePickerEntryMode.input);

                    if (eventData!.event!.date == null) {
                      eventData!.event!.date = DateTime.now();
                      eventData!.event!.endDate = DateTime.now();
                    }

                    if (timePicked != null) {
                      eventData!.event!.startTime = DateTime(
                          eventData!.event!.date!.year,
                          eventData!.event!.date!.month,
                          eventData!.event!.date!.day,
                          timePicked.hour,
                          timePicked.minute);
                      setState(() {});
                    }
                  },
                ),
                CustomInputField(
                  width: 155.toWidth,
                  height: 50.toHeight,
                  isReadOnly: true,
                  hintText: AllText().STOP,
                  icon: Icons.access_time,
                  initialValue: eventData!.event!.endTime != null
                      ? timeOfDayToString(eventData!.event!.endTime!)
                      : '',
                  onTap: () async {
                    final timePicked = await showTimePicker(
                        context: context,
                        initialTime: eventData!.event!.endTime != null
                            ? TimeOfDay.fromDateTime(eventData!.event!.endTime!)
                            : TimeOfDay.now(),
                        initialEntryMode: TimePickerEntryMode.input);

                    if (eventData!.event!.endDate == null) {
                      CustomToast().show(
                          AllText().SELECT_START_TIME_FIRST, context,
                          isError: true);
                      return;
                    }

                    if (timePicked != null) {
                      eventData!.event!.endTime = DateTime(
                          eventData!.event!.date!.year,
                          eventData!.event!.date!.month,
                          eventData!.event!.date!.day,
                          timePicked.hour,
                          timePicked.minute);
                      setState(() {});
                    }
                  },
                ),
              ],
            ),
            SizedBox(height: 25.toHeight),
            Text(AllText().ENDS_ON, style: CustomTextStyles().greyLabel14),
            SizedBox(height: 25.toHeight),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(AllText().NEVER, style: CustomTextStyles().greyLabel12),
                Radio(
                  groupValue: eventData!.event!.endsOn,
                  toggleable: true,
                  value: EndsOn.NEVER,
                  onChanged: (dynamic value) {
                    eventData!.event!.endsOn = value;
                    setState(() {});
                  },
                )
              ],
            ),
            SizedBox(height: 6.toHeight),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(AllText().ON, style: CustomTextStyles().greyLabel12),
                Radio(
                  groupValue: eventData!.event!.endsOn,
                  toggleable: true,
                  value: EndsOn.ON,
                  onChanged: (dynamic value) {
                    eventData!.event!.endsOn = value;

                    setState(() {});
                  },
                )
              ],
            ),
            SizedBox(height: 6.toHeight),
            CustomInputField(
              width: 350.toWidth,
              height: 50.toHeight,
              isReadOnly: true,
              hintText: AllText().SELECT_DATE,
              icon: Icons.date_range,
              initialValue: (eventData!.event!.endEventOnDate != null)
                  ? dateToString(eventData!.event!.endEventOnDate!)
                  : '',
              onTap: () async {
                final datePicked = await showDatePicker(
                  context: context,
                  initialDate:
                      eventData!.event!.endEventOnDate ?? DateTime.now(),
                  firstDate: DateTime(2015, 8),
                  lastDate: DateTime(2101),
                );

                if (datePicked != null) {
                  eventData!.event!.endEventOnDate = datePicked;
                  setState(() {});
                }
              },
              value: (value) {},
            ),
            SizedBox(height: 6.toHeight),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(AllText().AFTER, style: CustomTextStyles().greyLabel12),
                Radio(
                  groupValue: eventData!.event!.endsOn,
                  toggleable: true,
                  value: EndsOn.AFTER,
                  onChanged: (dynamic value) {
                    eventData!.event!.endsOn = value;

                    setState(() {});
                  },
                )
              ],
            ),
            SizedBox(height: 6.toHeight),
            CustomInputField(
              width: 350.toWidth,
              height: 50.toHeight,
              hintText: AllText().START,
              // icon: Icons.keyboard_arrow_down,
              initialValue: eventData!.event!.endEventAfterOccurance != null
                  ? eventData!.event!.endEventAfterOccurance.toString()
                  : '',
              value: (val) {
                if (val.trim().isNotEmpty) {
                  var occurance = int.parse(val);
                  eventData!.event!.endEventAfterOccurance = occurance;
                }
              },
            ),
            const SizedBox(height: 20),
            Center(
              child: CustomButton(
                onPressed: () {
                  var formValid = EventService()
                      .checForRecurringeDayEventFormValidation(eventData!);
                  if (formValid is String) {
                    CustomToast().show(formValid, context, isError: true);
                    return;
                  }
                  EventService().eventNotificationModel!.event!.isRecurring =
                      true;
                  EventService().update(eventData: eventData);
                  Navigator.of(context).pop();
                },
                buttonText: AllText().DONE,
                width: 164.toWidth,
                height: 48.toHeight,
                buttonColor: Theme.of(context).brightness == Brightness.light
                    ? AllColors().Black
                    : AllColors().WHITE,
                fontColor: Theme.of(context).brightness == Brightness.light
                    ? AllColors().WHITE
                    : AllColors().Black,
              ),
            )
          ],
        ),
      ),
    );
  }
}
