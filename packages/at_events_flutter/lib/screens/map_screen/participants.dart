import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_common_flutter/services/size_config.dart';
import 'package:at_events_flutter/at_events_flutter.dart';
import 'package:at_events_flutter/common_components/custom_heading.dart';
import 'package:at_events_flutter/common_components/draggable_symbol.dart';
import 'package:at_events_flutter/models/event_notification.dart';
import 'package:at_events_flutter/utils/text_styles.dart';
import 'package:at_events_flutter/utils/texts.dart';
import 'package:at_location_flutter/location_modal/hybrid_model.dart';
import 'package:at_location_flutter/service/location_service.dart';
import 'package:at_location_flutter/utils/constants/init_location_service.dart';
import 'package:flutter/material.dart';

// ignore: must_be_immutable
class Participants extends StatefulWidget {
  late EventNotificationModel eventListenerKeyword;
  Participants(this.eventListenerKeyword, {Key? key}) : super(key: key);

  @override
  _ParticipantsState createState() => _ParticipantsState();
}

class _ParticipantsState extends State<Participants> {
  List<String> _allAtsigns = [];
  late EventNotificationModel _event;
  bool isPastEvent = false;

  @override
  void initState() {
    _event = widget.eventListenerKeyword;

    if (_event.event!.endTime!.isBefore(DateTime.now())) {
      isPastEvent = true;
    }
    _allAtsigns = EventKeyStreamService().getAtsignsFromEvent(_event);
    _allAtsigns.add(AtClientManager.getInstance().atClient.getCurrentAtSign()!);

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: LocationService().atHybridUsersStream,
      builder: (context, AsyncSnapshot<List<HybridModel?>> snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          return builder();
        } else {
          return builder();
        }
      },
    );
  }

  /// builds a container widget that displays a list of participants
  Widget builder() {
    return Container(
      height: 422.toHeight,
      padding:
          EdgeInsets.fromLTRB(15.toWidth, 5.toHeight, 15.toWidth, 10.toHeight),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DraggableSymbol(),
            CustomHeading(
                heading: AllText().PARTICIPANTS, action: AllText().CLOSE),
            SizedBox(
              height: 10.toHeight,
            ),
            ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: _allAtsigns.length,
              itemBuilder: (BuildContext context, int index) {
                return DisplayTile(
                  title: _allAtsigns[index],
                  atsignCreator: _allAtsigns[index],
                  subTitle: null,
                  action: isPastEvent
                      ? const SizedBox()
                      : getStatus(_allAtsigns[index]),
                );
              },
              separatorBuilder: (BuildContext context, int index) {
                return const Divider();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// status: accepted/rejected/action required
  /// sharing from: startsSharingFrom
  /// eta: Location Not Receied / eta / ?
  Widget getStatus(String _atsign) {
    if (compareAtSign(
        _atsign, AtClientManager.getInstance().atClient.getCurrentAtSign()!)) {
      ////// Uncomment if we have to show logged in user's eta
      // var _hybridModel = LocationService().hybridUsersList.where((element) =>
      //     compareAtSign(element!.displayName!,
      //         AtClientManager.getInstance().atClient.getCurrentAtSign()!));

      // if (_hybridModel.isNotEmpty) {
      //   return Text(
      //     _hybridModel.first?.eta ?? '',
      //     style: CustomTextStyles().darkGrey14,
      //   );
      // }

      return Text(
        '',
        style: CustomTextStyles().darkGrey14,
      );
    }

    var _eventInfo =
        HomeEventService().getOtherMemberEventInfo(_event.key!, _atsign);

    String _status = '', _eta = '';

    /// action required
    if (_eventInfo == null) {
      /// for event creator
      if (!compareAtSign(_atsign, _event.atsignCreator!)) {
        _status = AllText().ACTION_REQUIRED;
      }
    }

    /// exited
    if (_eventInfo != null) {
      if (_eventInfo.isExited) {
        _status = AllText().EXITED;
      } else {
        _status = AllText().ACCEPTED;
      }
    }

    /// sharing
    if (!(_eventInfo?.isSharing ?? true)) {
      _eta = AllText().LOC_NOT_RECIEVED;
    }

    var _hybridModel = LocationService()
        .hybridUsersList
        .where((element) => compareAtSign(element!.displayName!, _atsign));

    /// eta
    if (_hybridModel.isNotEmpty) {
      _eta = _hybridModel.first?.eta ?? '?';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _status == ''
            ? const SizedBox()
            : RichText(
                text: TextSpan(
                  text: 'Status: ',
                  style: CustomTextStyles().grey12,
                  children: [
                    TextSpan(
                      text: ' $_status',
                      style: CustomTextStyles().orange12,
                    )
                  ],
                ),
              ),
        _eventInfo?.from == null
            ? const SizedBox()
            : RichText(
                text: TextSpan(
                  text: 'Sharing from: ',
                  style: CustomTextStyles().grey12,
                  children: [
                    TextSpan(
                      text: ' ${timeOfDayToString(_eventInfo!.from!)}',
                      style: CustomTextStyles().orange12,
                    )
                  ],
                ),
              ),
        _eta == ''
            ? const SizedBox()
            : RichText(
                text: TextSpan(
                  text: 'ETA: ',
                  style: CustomTextStyles().grey12,
                  children: [
                    TextSpan(
                      text: ' $_eta',
                      style: CustomTextStyles().orange12,
                    )
                  ],
                ),
              ),
      ],
    );
  }
}
