import 'dart:typed_data';

import 'package:at_common_flutter/services/size_config.dart';
import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/utils/text_strings.dart';
import 'package:at_contacts_flutter/utils/text_styles.dart';
import 'package:at_contacts_flutter/widgets/contacts_initials.dart';
import 'package:at_contacts_flutter/widgets/custom_circle_avatar.dart';
import 'package:at_utils/at_logger.dart';
import 'package:flutter/material.dart';

/// A list tile to display the blocked contact
/// takes in a [AtContact] blocked user
/// and displays it's name, atsign, profile picture and option to unblock the user
class BlockedUserCard extends StatefulWidget {
  final AtContact? blockeduser;
  final Function? unblockAtsign;

  const BlockedUserCard({Key? key, this.blockeduser, this.unblockAtsign}) : super(key: key);
  @override
  _BlockedUserCardState createState() => _BlockedUserCardState();
}

class _BlockedUserCardState extends State<BlockedUserCard> {
  final AtSignLogger _logger = AtSignLogger('Blocked User Card');

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    Widget contactImage;
    if (widget.blockeduser!.tags != null && widget.blockeduser!.tags!['image'] != null) {
      Uint8List? image;
      try {
        List<int> intList = widget.blockeduser!.tags!['image'].cast<int>();
        image = Uint8List.fromList(intList);
      } catch (e) {
        _logger.severe('Error in image: $e');
      }

      contactImage = image != null
          ? CustomCircleAvatar(
              size: SizeConfig().isTablet(context) ? 32 : 45,
              byteImage: image,
              nonAsset: true,
            )
          : ContactInitial(
              size: SizeConfig().isTablet(context) ? 32 : 45,
              initials: widget.blockeduser!.atSign!,
            );
    } else {
      contactImage = ContactInitial(
        size: SizeConfig().isTablet(context) ? 32 : 45,
        initials: widget.blockeduser!.atSign!,
      );
    }
    return ListTile(
      leading: contactImage,
      title: SizedBox(
        width: 300.toWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.blockeduser!.atSign!.substring(1).toString(),
              style: CustomTextStyles.primaryRegular16,
            ),
            Text(
              widget.blockeduser!.atSign.toString(),
              style: CustomTextStyles.secondaryRegular12,
            ),
          ],
        ),
      ),
      trailing: GestureDetector(
        onTap: widget.unblockAtsign as void Function(),
        child: Text(
          TextStrings().unblock,
          style: CustomTextStyles.blueRegular14,
        ),
      ),
    );
  }
}
