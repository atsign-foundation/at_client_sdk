import 'package:at_common_flutter/services/size_config.dart';
import 'package:at_common_flutter/widgets/custom_button.dart';
import 'package:at_common_flutter/widgets/custom_input_field.dart';
import 'package:at_events_flutter/common_components/custom_toast.dart';
import 'package:at_events_flutter/common_components/floating_icon.dart';
import 'package:at_events_flutter/services/event_services.dart';
import 'package:at_events_flutter/utils/colors.dart';
import 'package:at_events_flutter/utils/text_styles.dart';
import 'package:at_events_flutter/utils/texts.dart';
import 'package:at_location_flutter/at_location_flutter.dart';
import 'package:flutter/material.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:latlong2/latlong.dart';

class SelectedLocation extends StatefulWidget {
  final LatLng point;
  final String displayName;
  final String? label;
  const SelectedLocation(this.displayName, this.point, {Key? key, this.label})
      : super(key: key);
  @override
  _SelectedLocationState createState() => _SelectedLocationState();
}

class _SelectedLocationState extends State<SelectedLocation> {
  var mapController = MapController();

  @override
  void initState() {
    if (widget.label != null) {
      EventService().eventNotificationModel!.venue!.label = widget.label;
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            showLocation(UniqueKey(), null, location: widget.point),
            Positioned(
              top: 0,
              left: 0,
              child: FloatingIcon(
                bgColor: AllColors().WHITE,
                icon: Icons.arrow_back,
                iconColor: AllColors().Black,
                isTopLeft: true,
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ),
            Positioned(
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.grey,
                      offset: Offset(0.0, 1.0), //(x,y)
                      blurRadius: 10.0,
                    ),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(
                    28.toWidth, 20.toHeight, 28.toHeight, 0),
                height: SizeConfig().screenHeight * 0.4,
                width: SizeConfig().screenWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.location_on,
                                      color: AllColors().ORANGE,
                                    ),
                                    Text('', style: CustomTextStyles().black16)
                                  ],
                                ),
                              ),
                              InkWell(
                                  onTap: () => Navigator.pop(context),
                                  child: Text(AllText().CANCEL,
                                      style: CustomTextStyles().orange16))
                            ],
                          ),
                          SizedBox(height: 10.toHeight),
                          Flexible(
                            child: Text(widget.displayName,
                                style: CustomTextStyles().greyLabel14),
                          ),
                          SizedBox(height: 20.toHeight),
                          Text(AllText().LABEL,
                              style: CustomTextStyles().greyLabel14),
                          SizedBox(height: 5.toHeight),
                          CustomInputField(
                            width: 321.toWidth,
                            hintText: AllText().SAVE_THIS_ADDRESS_AS,
                            initialValue: EventService()
                                    .eventNotificationModel!
                                    .venue!
                                    .label ??
                                '',
                            value: (String val) {
                              EventService()
                                  .eventNotificationModel!
                                  .venue!
                                  .label = val;
                            },
                          ),
                        ],
                      ),
                    ),
                    Center(
                      child: Container(
                        padding: EdgeInsets.only(bottom: 20.toHeight),
                        child: CustomButton(
                          buttonText: AllText().SAVE,
                          onPressed: () {
                            if ((EventService()
                                        .eventNotificationModel!
                                        .venue!
                                        .label !=
                                    null) &&
                                (EventService()
                                    .eventNotificationModel!
                                    .venue!
                                    .label!
                                    .isNotEmpty)) {
                              EventService()
                                  .eventNotificationModel!
                                  .venue!
                                  .latitude = widget.point.latitude;

                              EventService()
                                  .eventNotificationModel!
                                  .venue!
                                  .longitude = widget.point.longitude;

                              EventService().update(
                                  eventData:
                                      EventService().eventNotificationModel);
                              Navigator.of(context).pop();
                              Navigator.of(context).pop();
                            } else {
                              CustomToast().show(
                                  AllText().CANNOT_LEAVE_LABEL_EMPTY, context,
                                  isError: true);
                            }
                          },
                          width: 165.toWidth,
                          height: 48.toHeight,
                          buttonColor:
                              Theme.of(context).brightness == Brightness.light
                                  ? AllColors().Black
                                  : AllColors().WHITE,
                          fontColor:
                              Theme.of(context).brightness == Brightness.light
                                  ? AllColors().WHITE
                                  : AllColors().Black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
