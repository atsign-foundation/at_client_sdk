import 'package:at_common_flutter/at_common_flutter.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_group_flutter/desktop_screens/desktop_empty_group.dart';
import 'package:at_contacts_group_flutter/services/group_service.dart';
import 'package:at_contacts_group_flutter/services/navigation_service.dart';
import 'package:at_contacts_group_flutter/utils/text_constants.dart';
import 'package:at_contacts_group_flutter/widgets/error_screen.dart';
import 'package:at_utils/at_logger.dart';
import 'package:flutter/material.dart';
import 'package:at_contacts_group_flutter/desktop_routes/desktop_route_names.dart';
import 'package:at_contacts_group_flutter/desktop_routes/desktop_routes.dart';
import 'package:collection/collection.dart';

class DesktopGroupInitialScreen extends StatefulWidget {
  final bool showBackButton;
  const DesktopGroupInitialScreen({Key? key, this.showBackButton = true})
      : super(key: key);

  @override
  State<DesktopGroupInitialScreen> createState() =>
      _DesktopGroupInitialScreenState();
}

class _DesktopGroupInitialScreenState extends State<DesktopGroupInitialScreen> {
  bool createBtnTapped = false;
  List<AtContact?> selectedContactList = [];
  bool shouldUpdate = false;
  List<AtGroup>? previousData;

  AtSignLogger atSignLogger = AtSignLogger('DesktopGroupInitialScreen');
  @override
  void initState() {
    try {
      super.initState();
      GroupService().groupPreferece.showBackButton = widget.showBackButton;
      GroupService().getAllGroupsDetails();
    } catch (e) {
      atSignLogger.severe('Error in init of Group_list $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Container(
      width: SizeConfig().screenWidth - TextConstants.SIDEBAR_WIDTH,
      color: const Color(0xFFF7F7FF),
      child: StreamBuilder(
        stream: GroupService().atGroupStream,
        builder: (BuildContext context, AsyncSnapshot<List<AtGroup>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else {
            if (snapshot.hasError) {
              return ErrorScreen(onPressed: () {
                GroupService().getAllGroupsDetails();
              });
            } else {
              if (snapshot.hasData) {
                if ((previousData == null) ||
                    (!areListsEqual(previousData, snapshot.data))) {
                  shouldUpdate = true;
                  previousData = snapshot.data;
                } else {
                  shouldUpdate = false;
                }

                if (snapshot.data!.isEmpty) {
                  return createBtnTapped
                      ? NestedNavigators(
                          snapshot.data!,
                          () {
                            setState(() {
                              createBtnTapped = false;
                            });
                          },
                          shouldUpdate: shouldUpdate,
                          key: UniqueKey(),
                          expandIndex: 0,
                        )
                      : DesktopEmptyGroup(createBtnTapped, onCreateBtnTap: () {
                          setState(() {
                            createBtnTapped = true;
                          });
                        });
                } else {
                  return NestedNavigators(
                    snapshot.data!,
                    () {
                      setState(() {
                        createBtnTapped = false;
                      });
                    },
                    shouldUpdate: shouldUpdate,
                    key: UniqueKey(),
                    expandIndex: GroupService().expandIndex ?? 0,
                  );
                }
              } else {
                return DesktopEmptyGroup(createBtnTapped, onCreateBtnTap: () {
                  setState(() {
                    createBtnTapped = true;
                  });
                });
              }
            }
          }
        },
      ),
    );
  }
}

class NestedNavigators extends StatefulWidget {
  final List<AtGroup> data;
  final Function initialRouteOnArrowBackTap;
  final bool shouldUpdate;
  final int expandIndex;
  const NestedNavigators(this.data, this.initialRouteOnArrowBackTap,
      {Key? key, this.shouldUpdate = false, required this.expandIndex})
      : super(key: key);

  @override
  _NestedNavigatorsState createState() => _NestedNavigatorsState();
}

class _NestedNavigatorsState extends State<NestedNavigators> {
  @override
  void initState() {
    if (widget.shouldUpdate) {
      NavService.resetKeys();
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: SizeConfig().screenWidth - TextConstants.SIDEBAR_WIDTH,
      child: Row(
        children: [
          Expanded(
            child: Navigator(
              key: NavService.groupPckgLeftHalfNavKey,
              initialRoute: DesktopRoutes.DESKTOP_GROUP_LEFT_INITIAL,
              onGenerateRoute: (routeSettings) {
                var routeBuilders =
                    DesktopGroupSetupRoutes.groupLeftRouteBuilders(
                        context, routeSettings, widget.data,
                        expandIndex: widget.expandIndex);
                return MaterialPageRoute(builder: (context) {
                  return routeBuilders[routeSettings.name]!(context);
                });
              },
            ),
          ),
          Expanded(
            child: Navigator(
              key: NavService.groupPckgRightHalfNavKey,
              initialRoute: DesktopRoutes.DESKTOP_GROUP_RIGHT_INITIAL,
              onGenerateRoute: (routeSettings) {
                var routeBuilders =
                    DesktopGroupSetupRoutes.groupRightRouteBuilders(
                        context, routeSettings, widget.data,
                        initialRouteOnArrowBackTap:
                            widget.initialRouteOnArrowBackTap,
                        initialRouteOnDoneTap: DesktopGroupSetupRoutes
                            .navigator(DesktopRoutes.DESKTOP_NEW_GROUP),
                        expandIndex: widget.expandIndex);
                return MaterialPageRoute(builder: (context) {
                  return routeBuilders[routeSettings.name]!(context);
                });
              },
            ),
          )
        ],
      ),
    );
  }
}

Function areListsEqual = const DeepCollectionEquality.unordered().equals;
