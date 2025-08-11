// ignore_for_file: avoid_function_literals_in_foreach_calls

import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_common_flutter/services/size_config.dart';
import 'package:at_common_flutter/widgets/custom_button.dart';
import 'package:at_common_flutter/widgets/custom_input_field.dart';
import 'package:at_contacts_group_flutter/models/group_contacts_model.dart';
import 'package:at_contacts_group_flutter/screens/group_contact_view/group_contact_view.dart';
import 'package:at_events_flutter/common_components/bottom_sheet.dart';
import 'package:at_events_flutter/common_components/custom_toast.dart';
import 'package:at_events_flutter/common_components/error_screen.dart';
import 'package:at_events_flutter/common_components/overlapping_contacts.dart';
import 'package:at_events_flutter/models/event_notification.dart';
import 'package:at_events_flutter/screens/one_day_event.dart';
import 'package:at_events_flutter/common_components/custom_heading.dart';
import 'package:at_events_flutter/screens/select_location.dart';
import 'package:at_events_flutter/services/venues_services.dart';
import 'package:at_events_flutter/utils/text_styles.dart';
import 'package:at_events_flutter/utils/texts.dart';
import 'package:flutter/material.dart';
import 'package:at_contact/at_contact.dart';
import 'package:latlong2/latlong.dart';

import '../at_events_flutter.dart';

class CreateEvent extends StatefulWidget {
  final AtClientManager atClientManager;
  final EventNotificationModel? eventData;
  final ValueChanged<EventNotificationModel>? onEventSaved;
  final List<EventNotificationModel>? createdEvents;
  // ignore: prefer_typing_uninitialized_variables
  final isUpdate;
  const CreateEvent(this.atClientManager,
      {Key? key,
      this.isUpdate = false,
      this.eventData,
      this.onEventSaved,
      this.createdEvents})
      : super(key: key);
  @override
  _CreateEventState createState() => _CreateEventState();
}

class _CreateEventState extends State<CreateEvent> {
  List<AtContact>? selectedContactList;
  late List<GroupContactsModel?> selectedGroupContact;
  late bool isLoading;

  @override
  void initState() {
    super.initState();
    isLoading = false;
    EventService().init(
        // ignore: prefer_if_null_operators
        widget.isUpdate != null ? widget.isUpdate : false,
        // ignore: prefer_if_null_operators
        widget.eventData != null ? widget.eventData : null);
    if (widget.createdEvents != null) {
      EventService().createdEvents = widget.createdEvents ?? [];
    } else {
      EventKeyStreamService().allEventNotifications.forEach((element) {
        if (element.eventNotificationModel != null) {
          EventService().createdEvents.add(element.eventNotificationModel!);
        }
      });
    }

    if (widget.onEventSaved != null) {
      EventService().onEventSaved = widget.onEventSaved;
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      body: SafeArea(
        child: Container(
          height: SizeConfig().screenHeight,
          padding: const EdgeInsets.fromLTRB(25, 25, 25, 10),
          child: SingleChildScrollView(
            child: SizedBox(
              height: SizeConfig().screenHeight * 0.85,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                      child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        StreamBuilder(
                            stream: EventService().eventStream,
                            builder: (BuildContext context, snapshot) {
                              var eventData =
                                  snapshot.data as EventNotificationModel?;

                              if (eventData != null && snapshot.hasData) {
                                // ignore: avoid_unnecessary_containers
                                return Container(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      CustomHeading(
                                        heading: AllText().CREATE_EVENT,
                                        action: AllText().CANCEL,
                                        onTap: () {
                                          Navigator.of(context).pop();
                                        },
                                      ),
                                      const SizedBox(height: 25),
                                      Text(AllText().SEND,
                                          style:
                                              CustomTextStyles().greyLabel14),
                                      SizedBox(height: 6.toHeight),
                                      CustomInputField(
                                        width: SizeConfig().screenWidth * 0.95,
                                        height: 50.toHeight,
                                        isReadOnly: true,
                                        hintText: AllText()
                                            .SELECT_AT_SIGN_FROM_CONTACT,
                                        icon: Icons.contacts_rounded,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  GroupContactView(
                                                asSelectionScreen: true,
                                                showGroups: true,
                                                showContacts: true,
                                                selectedList: (s) {
                                                  selectedGroupContact = s;

                                                  // ignore: prefer_is_empty
                                                  if (selectedGroupContact
                                                          .length >
                                                      0) {
                                                    EventService()
                                                        .addNewContactAndGroupMembers(
                                                            selectedGroupContact);
                                                    EventService().update();
                                                  }
                                                },
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 25),
                                      (EventService().selectedContacts !=
                                                  null &&
                                              // ignore: prefer_is_empty
                                              EventService()
                                                      .selectedContacts!
                                                      .length >
                                                  0)
                                          ? (OverlappingContacts(
                                              selectedList: EventService()
                                                  .selectedContacts))
                                          : const SizedBox(),
                                      (EventService().selectedContacts !=
                                                  null &&
                                              // ignore: prefer_is_empty
                                              EventService()
                                                      .selectedContacts!
                                                      .length >
                                                  0)
                                          ? const SizedBox(height: 25)
                                          : const SizedBox(),
                                      Text(
                                        AllText().TITLE,
                                        style: CustomTextStyles().greyLabel14,
                                      ),
                                      SizedBox(height: 6.toHeight),
                                      CustomInputField(
                                        width: SizeConfig().screenWidth * 0.95,
                                        height: 50.toHeight,
                                        hintText: AllText().TITLE_OF_THE_EVENT,
                                        initialValue: eventData.title != null
                                            ? EventService()
                                                .eventNotificationModel!
                                                .title!
                                            : '',
                                        value: (val) {
                                          EventService()
                                              .eventNotificationModel!
                                              .title = val;
                                        },
                                      ),
                                      const SizedBox(height: 25),
                                      Text(AllText().ADD_VENUE,
                                          style:
                                              CustomTextStyles().greyLabel14),
                                      SizedBox(height: 6.toHeight),
                                      CustomInputField(
                                        width: SizeConfig().screenWidth * 0.95,
                                        height: 50.toHeight,
                                        isReadOnly: true,
                                        hintText: AllText()
                                            .START_TYPING_OR_SEL_FRM_MAP,
                                        initialValue:
                                            eventData.venue!.label != null
                                                ? eventData.venue!.label!
                                                : '',
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const SelectLocation(),
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 25),
                                      Row(
                                        children: <Widget>[
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () {
                                                bottomSheet(
                                                    context,
                                                    const OneDayEvent(),
                                                    SizeConfig().screenHeight *
                                                        0.9);
                                              },
                                              child: Text(
                                                  AllText().SELECT_TIMES,
                                                  style: CustomTextStyles()
                                                      .greyLabel14),
                                            ),
                                          ),
                                          Checkbox(
                                            value: (EventService()
                                                            .eventNotificationModel!
                                                            .event!
                                                            .isRecurring !=
                                                        null &&
                                                    EventService()
                                                            .eventNotificationModel!
                                                            .event!
                                                            .isRecurring ==
                                                        false)
                                                ? true
                                                : false,
                                            onChanged: (value) {
                                              bottomSheet(
                                                  context,
                                                  const OneDayEvent(),
                                                  SizeConfig().screenHeight *
                                                      0.9);
                                            },
                                          )
                                        ],
                                      ),
                                      (EventService()
                                                  .eventNotificationModel!
                                                  .event!
                                                  .isRecurring ==
                                              false)
                                          ? (EventService()
                                                          .eventNotificationModel!
                                                          .event!
                                                          .date !=
                                                      null &&
                                                  EventService()
                                                          .eventNotificationModel!
                                                          .event!
                                                          .startTime !=
                                                      null &&
                                                  EventService()
                                                          .eventNotificationModel!
                                                          .event!
                                                          .endTime !=
                                                      null)
                                              ? Text(
                                                  ((dateToString(eventData
                                                                  .event!
                                                                  .date!) ==
                                                              dateToString(
                                                                  DateTime
                                                                      .now()))
                                                          ? '${AllText().EVENT_TODAY} (${timeOfDayToString(eventData.event!.startTime!)})'
                                                          : '${AllText().EVENT_ON} ${(dateToString(eventData.event!.date!) != dateToString(DateTime.now()) ? dateToString(eventData.event!.date!) : dateToString(DateTime.now()))} (${timeOfDayToString(eventData.event!.startTime!)})') +
                                                      ((dateToString(eventData
                                                                  .event!
                                                                  .endDate!) ==
                                                              dateToString(
                                                                  eventData
                                                                      .event!
                                                                      .date!))
                                                          ? AllText().TO
                                                          : '${AllText().TO} ${dateToString(eventData.event!.endDate!)}') +
                                                      (' (${timeOfDayToString(eventData.event!.endTime!)})'),

                                                  ///
                                                  // 'Event on ${dateToString(eventData.event.date)} (${timeOfDayToString(eventData.event.startTime)}- ${timeOfDayToString(eventData.event.endTime)})',
                                                  style: CustomTextStyles()
                                                      .greyLabel12,
                                                )
                                              : const SizedBox()
                                          : const SizedBox(),
                                      SizedBox(height: 20.toHeight),
                                      (EventService()
                                                      .eventNotificationModel!
                                                      .event!
                                                      .isRecurring !=
                                                  null &&
                                              EventService()
                                                      .eventNotificationModel!
                                                      .event!
                                                      .isRecurring ==
                                                  true)
                                          // ignore: avoid_unnecessary_containers
                                          ? Container(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: <Widget>[
                                                  (eventData.event!
                                                                  .repeatCycle ==
                                                              RepeatCycle
                                                                  .MONTH &&
                                                          eventData.event!
                                                                  .date !=
                                                              null &&
                                                          eventData.event!
                                                                  .repeatDuration !=
                                                              null)
                                                      ? Text(
                                                          '${AllText().REPEATS_EVERY} ${eventData.event!.repeatDuration} ${AllText().WEEK_ON} ${eventData.event!.date!.day} ${AllText().DAY}')
                                                      : (eventData.event!
                                                                      .repeatCycle ==
                                                                  RepeatCycle
                                                                      .WEEK &&
                                                              eventData.event!
                                                                      .occursOn !=
                                                                  null)
                                                          ? Text(
                                                              '${AllText().REPEATS_EVERY} ${eventData.event!.repeatDuration} ${AllText().WEEK_ON} ${getWeekString(eventData.event!.occursOn)} ')
                                                          : const SizedBox(),
                                                  EventService()
                                                                  .eventNotificationModel!
                                                                  .event!
                                                                  .endsOn !=
                                                              null &&
                                                          EventService()
                                                                  .eventNotificationModel!
                                                                  .event!
                                                                  .endsOn ==
                                                              EndsOn.AFTER
                                                      ? Text(
                                                          '${AllText().ENDS_AFTER} ${eventData.event!.endEventAfterOccurance} ${AllText().OCCURENCE}')
                                                      : const SizedBox(),
                                                ],
                                              ),
                                            )
                                          : const SizedBox(),
                                    ],
                                  ),
                                );
                              } else if (snapshot.hasError) {
                                return Center(
                                  child: ErrorScreen(
                                    onPressed: EventService().init(
                                        // ignore: prefer_if_null_operators
                                        widget.isUpdate != null
                                            ? widget.isUpdate
                                            : false,
                                        // ignore: prefer_if_null_operators
                                        widget.eventData != null
                                            ? widget.eventData
                                            : null),
                                  ),
                                );
                              } else {
                                return const SizedBox();
                              }
                            }),
                      ],
                    ),
                  )),
                  Center(
                    child: isLoading
                        ? const CircularProgressIndicator()
                        : CustomButton(
                            buttonText: widget.isUpdate
                                ? AllText().SAVE
                                : AllText().CREATE_AND_INVITE,
                            onPressed: onCreateEvent,
                            width: 160.toWidth,
                            height: 50.toHeight,
                            buttonColor: Theme.of(context).primaryColor,
                            fontColor:
                                Theme.of(context).scaffoldBackgroundColor,
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

  /// handles the event creation process
  // ignore: always_declare_return_types
  onCreateEvent() async {
    setState(() {
      isLoading = true;
    });

    var formValid = EventService().createEventFormValidation();
    if (formValid is String) {
      CustomToast().show(formValid, context, isError: true);
      setState(() {
        isLoading = false;
      });
      return;
    }

    var isOverlap = EventService().showConcurrentEventDialog(
        widget.createdEvents ??
            EventKeyStreamService()
                .allEventNotifications
                .map((e) => e.eventNotificationModel!)
                .toList(),
        EventService().eventNotificationModel,
        context)!;

    if (isOverlap) {
      VenuesServices().storeNewVenue(
        LatLng(EventService().eventNotificationModel!.venue!.latitude!,
            EventService().eventNotificationModel!.venue!.longitude!),
        EventService().eventNotificationModel!.venue!.label!,
      ); // store venue

      setState(() {
        isLoading = false;
      });
      return;
    }

    var result = await EventService().createEvent();

    if (result is bool && result == true) {
      VenuesServices().storeNewVenue(
        LatLng(EventService().eventNotificationModel!.venue!.latitude!,
            EventService().eventNotificationModel!.venue!.longitude!),
        EventService().eventNotificationModel!.venue!.label!,
      ); // store venue

      CustomToast().show(
          EventService().isEventUpdate
              ? AllText().EVENT_UPDATED
              : AllText().EVENT_ADDED,
          context,
          isSuccess: true);
      setState(() {
        isLoading = false;
      });
      Navigator.of(context).pop();
    } else {
      CustomToast().show(
          '${AllText().SOMETHING_WENT_WRONG} ${result.toString()}', context,
          isError: true);
      setState(() {
        isLoading = false;
      });
    }
  }
}
