import 'dart:typed_data';

import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/widgets/contacts_initials.dart';
import 'package:at_contacts_flutter/widgets/custom_circle_avatar.dart';
import 'package:at_utils/at_logger.dart';

///

import 'package:flutter/material.dart';

import 'package:at_common_flutter/services/size_config.dart';

class CircularContacts extends StatelessWidget {
  final Function? onCrossPressed;

  final AtContact? contact;

  const CircularContacts({Key? key, this.onCrossPressed, this.contact})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    final AtSignLogger logger = AtSignLogger('Circular Contacts');
    Uint8List? image;
    if (contact!.tags != null && contact!.tags!['image'] != null) {
      try {
        List<int> intList = contact!.tags!['image'].cast<int>();
        image = Uint8List.fromList(intList);
      } catch (e) {
        logger.severe('Error in image: $e');
      }
    }
    return Container(
      padding:
          EdgeInsets.symmetric(vertical: 9.toHeight, horizontal: 20.toWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            alignment: AlignmentDirectional.topCenter,
            children: [
              SizedBox(
                height: 50.toHeight,
                width: 50.toHeight,
                child: (image != null)
                    ? CustomCircleAvatar(
                        byteImage: image,
                        nonAsset: true,
                      )
                    : ContactInitial(
                        initials: contact!.atSign!,
                      ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: onCrossPressed as void Function()?,
                  child: Container(
                    height: 15.toHeight,
                    width: 15.toHeight,
                    decoration: const BoxDecoration(
                        color: Colors.black, shape: BoxShape.circle),
                    child: Icon(
                      Icons.close,
                      size: 15.toHeight,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.toHeight),
          SizedBox(
            width: 80.toWidth,
            child: Text(
              contact!.tags != null && contact!.tags!['name'] != null
                  ? contact!.tags!['name']
                  : contact!.atSign!.substring(1),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15.toFont,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
          SizedBox(height: 10.toHeight),
          SizedBox(
            width: 60.toWidth,
            child: Text(
              contact!.atSign!,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15.toFont,
                fontWeight: FontWeight.normal,
              ),
            ),
          )
        ],
      ),
    );
  }
}
