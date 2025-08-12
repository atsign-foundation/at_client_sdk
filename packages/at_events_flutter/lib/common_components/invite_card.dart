import 'dart:typed_data';

// ignore: unused_import
import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/utils/init_contacts_service.dart';
import 'package:at_events_flutter/common_components/custom_circle_avatar.dart';
import 'package:at_events_flutter/common_components/pop_button.dart';
import 'package:at_events_flutter/utils/colors.dart';
import 'package:at_events_flutter/utils/text_styles.dart';
import 'package:at_events_flutter/utils/texts.dart';
import 'package:flutter/material.dart';
import 'package:at_common_flutter/services/size_config.dart';

class InviteCard extends StatefulWidget {
  final String? event, invitedPeopleCount, timeAndDate, atSign, memberCount;
  final bool isStartTime;

  const InviteCard(
      {Key? key,
      this.event,
      this.invitedPeopleCount,
      this.timeAndDate,
      this.atSign,
      this.memberCount,
      this.isStartTime = false})
      : super(key: key);

  @override
  _InviteCardState createState() => _InviteCardState();
}

class _InviteCardState extends State<InviteCard> {
  Uint8List? memoryImage;

  @override
  void initState() {
    super.initState();
    if (widget.atSign != null) getAtsignDetails();
  }

  /// retrieves the contact details of the provided atsign, specifically the image if available, and updates the state with the image data
  // ignore: always_declare_return_types
  getAtsignDetails() async {
    var contact = await getAtSignDetails(widget.atSign!);
    if (contact.tags != null && contact.tags!['image'] != null) {
      List<int>? intList = contact.tags!['image'].cast<int>();
      setState(() {
        memoryImage = Uint8List.fromList(intList!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // ignore: avoid_unnecessary_containers
    return Container(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Stack(
            children: [
              CustomCircleAvatar(
                size: 50,
                isMemoryImage: true,
                contactInitial: widget.atSign,
                memoryImage: memoryImage,
              ),
              widget.memberCount != null
                  ? Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 25.toFont,
                        height: 25.toFont,
                        decoration: BoxDecoration(
                          color: AllColors().BLUE,
                          borderRadius: BorderRadius.circular(20.toFont),
                        ),
                        child: Center(
                            child: Text(
                          '${widget.memberCount}',
                          style: CustomTextStyles().black10,
                        )),
                      ),
                    )
                  : const SizedBox()
            ],
          ),
          SizedBox(width: 10.toWidth),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                widget.event != null
                    ? Text(widget.event!, style: CustomTextStyles().black18)
                    : const SizedBox(),
                SizedBox(height: 5.toHeight),
                widget.invitedPeopleCount != null
                    ? Text(widget.invitedPeopleCount!,
                        style: CustomTextStyles().grey14)
                    : const SizedBox(),
                SizedBox(height: 10.toHeight),
                widget.timeAndDate != null
                    ? Text(widget.timeAndDate!,
                        style: CustomTextStyles().black14)
                    : const SizedBox(),
              ],
            ),
          ),
          PopButton(
            label: AllText().DECIDE_LATER,
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();

              // when decide later is pressed , we are closing start and end time selection sheet and event dialog.
              if (!widget.isStartTime) Navigator.of(context).pop();
            },
          )
        ],
      ),
    );
  }
}
