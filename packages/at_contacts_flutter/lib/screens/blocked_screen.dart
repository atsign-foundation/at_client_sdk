import 'package:at_common_flutter/widgets/custom_app_bar.dart';
import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_flutter/models/contact_base_model.dart';
import 'package:at_contacts_flutter/services/contact_service.dart';
import 'package:at_contacts_flutter/utils/colors.dart';
import 'package:at_contacts_flutter/utils/text_strings.dart';
import 'package:at_contacts_flutter/widgets/blocked_user_card.dart';
import 'package:at_contacts_flutter/widgets/circular_contacts.dart';
import 'package:at_contacts_flutter/widgets/error_screen.dart';
import 'package:flutter/material.dart';

import 'package:at_common_flutter/services/size_config.dart';

/// Screen exposed to see blocked contacts and unblock them
class BlockedScreen extends StatefulWidget {
  const BlockedScreen({Key? key}) : super(key: key);

  @override
  _BlockedScreenState createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<BlockedScreen> {
  late ContactService _contactService;
  bool errorOcurred = false;

  /// Boolean indicator of unblock action
  bool unblockingAtsign = false;
  @override
  void initState() {
    _contactService = ContactService();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      var result = await _contactService.fetchBlockContactList();
      if (result == null) {
        if (mounted) {
          setState(() {
            errorOcurred = true;
          });
        }
      }
    });

    super.initState();
  }

  /// boolean flag to indicate if blocking flow is in progress
  bool isBlocking = false;
  bool toggleList = false;
  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      backgroundColor: ColorConstants.scaffoldColor,
      appBar: CustomAppBar(
        showBackButton: true,
        showTitle: true,
        showLeadingIcon: true,
        titleText: TextStrings().blockedContacts,
      ),
      body: errorOcurred
          ? const ErrorScreen()
          : RefreshIndicator(
              color: Colors.transparent,
              strokeWidth: 0,
              backgroundColor: Colors.transparent,
              onRefresh: () async {
                await _contactService.fetchBlockContactList();
              },
              child: Container(
                color: ColorConstants.appBarColor,
                child: Column(
                  children: [
                    _contactService.blockContactList.isEmpty
                        ? Container()
                        : Container(
                            padding: EdgeInsets.only(right: 20.toWidth),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                const Icon(
                                  Icons.view_module,
                                  color: ColorConstants.greyText,
                                ),
                                Switch(
                                    value: toggleList,
                                    activeColor: Colors.white,
                                    activeTrackColor:
                                        ColorConstants.fadedGreyBackground,
                                    onChanged: (s) {
                                      setState(() {
                                        toggleList = !toggleList;
                                      });
                                    }),
                                const Icon(Icons.view_list,
                                    color: ColorConstants.greyText),
                              ],
                            ),
                          ),
                    Expanded(
                      child: StreamBuilder(
                        initialData: _contactService.baseBlockedList,
                        stream: _contactService.blockedContactStream,
                        builder: (context,
                            AsyncSnapshot<List<BaseContact?>> snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.active) {
                            return (snapshot.data!.isEmpty)
                                ? Center(
                                    child: Text(
                                      TextStrings().emptyBlockedList,
                                      style: TextStyle(
                                        fontSize: 16.toFont,
                                        color: ColorConstants.greyText,
                                        fontWeight: FontWeight.normal,
                                      ),
                                    ),
                                  )
                                : (toggleList)
                                    ? ListView.separated(
                                        padding: EdgeInsets.symmetric(
                                            vertical: 40.toHeight),
                                        itemCount: _contactService
                                            .blockContactList.length,
                                        separatorBuilder: (context, index) =>
                                            Divider(
                                          indent: 16.toWidth,
                                        ),
                                        itemBuilder: (context, index) {
                                          return BlockedUserCard(
                                              blockeduser: snapshot
                                                  .data?[index]?.contact,
                                              unblockAtsign: () async {
                                                await unblockAtsign(snapshot
                                                        .data?[index]
                                                        ?.contact ??
                                                    AtContact());
                                              });
                                        },
                                      )
                                    : GridView.builder(
                                        physics:
                                            const AlwaysScrollableScrollPhysics(),
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                                crossAxisCount: SizeConfig()
                                                        .isTablet(context)
                                                    ? 5
                                                    : 3,
                                                childAspectRatio: 1 /
                                                    (SizeConfig()
                                                            .isTablet(context)
                                                        ? 1.2
                                                        : 1.1)),
                                        shrinkWrap: true,
                                        itemCount: _contactService
                                            .blockContactList.length,
                                        itemBuilder: (context, index) {
                                          return CircularContacts(
                                              contact: snapshot
                                                  .data?[index]?.contact,
                                              onCrossPressed: () async {
                                                await unblockAtsign(snapshot
                                                        .data?[index]
                                                        ?.contact ??
                                                    AtContact());
                                              });
                                        },
                                      );
                          } else {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> unblockAtsign(AtContact atsign) async {
    setState(() {
      unblockingAtsign = true;
    });
    // ignore: unawaited_futures
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Center(
          child: Text(TextStrings().unblockContact),
        ),
        content: SizedBox(
          height: 100.toHeight,
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );
    await _contactService.blockUnblockContact(
        contact: atsign, blockAction: false);

    setState(() {
      unblockingAtsign = false;
      Navigator.pop(context);
    });
  }
}
