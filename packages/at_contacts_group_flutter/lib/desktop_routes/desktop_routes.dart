import 'package:at_contact/at_contact.dart';
import 'package:at_contacts_group_flutter/desktop_screens/desktop_empty_group.dart';
import 'package:at_contacts_group_flutter/desktop_screens/desktop_group_detail.dart';
import 'package:at_contacts_group_flutter/desktop_screens/desktop_group_list.dart';
import 'package:at_contacts_group_flutter/desktop_screens/desktop_new_group.dart';
import 'package:at_contacts_group_flutter/screens/group_contact_view/group_contact_view.dart';
import 'package:at_contacts_group_flutter/services/group_service.dart';
import 'package:at_contacts_group_flutter/services/navigation_service.dart';
import 'package:flutter/material.dart';

import 'desktop_route_names.dart';

class DesktopGroupSetupRoutes {
  static late Function exitGroupPackage;

  static void setExitFunction(Function _exitGroupPackage) {
    exitGroupPackage = _exitGroupPackage;
  }

  static Map<String, WidgetBuilder> groupLeftRouteBuilders(
      BuildContext context, RouteSettings routeSettings, List<AtGroup> _data,
      {int? expandIndex}) {
    return {
      DesktopRoutes.DESKTOP_GROUP_LEFT_INITIAL: (context) {
        if (_data.isEmpty) {
          return const DesktopEmptyGroup(true);
        } else {
          return DesktopGroupList(
            _data,
            key: UniqueKey(),
            expandIndex: expandIndex ?? 0,
          );
        }
      },
      DesktopRoutes.DESKTOP_GROUP_LIST: (context) {
        var args = routeSettings.arguments as Map<String, dynamic>;
        return DesktopGroupList(
          args['groups'],
          expandIndex: args['expandIndex'],
          key: UniqueKey(),
        );
      },
    };
  }

  static Map<String, WidgetBuilder> groupRightRouteBuilders(
      BuildContext context, RouteSettings routeSettings, var _data,
      {required Function initialRouteOnArrowBackTap,
      required Function initialRouteOnDoneTap,
      int? expandIndex}) {
    return {
      DesktopRoutes.DESKTOP_GROUP_RIGHT_INITIAL: (context) {
        if (_data.length == 0) {
          return GroupContactView(
              asSelectionScreen: true,
              singleSelection: false,
              showGroups: false,
              showContacts: true,
              isDesktop: true,
              selectedList: (selectedContactList) {
                GroupService().setSelectedContacts(
                    selectedContactList.map((e) => e?.contact).toList());
              },
              onBackArrowTap: (selectedGroupContacts) {
                initialRouteOnArrowBackTap();
              },
              onDoneTap: () {
                initialRouteOnDoneTap();
              });
        } else {
          return DesktopGroupDetail(_data[expandIndex ?? 0], expandIndex ?? 0);
        }
      },
      DesktopRoutes.DESKTOP_NEW_GROUP: (context) {
        var args = routeSettings.arguments as Map<String, dynamic>;
        return DesktopNewGroup(
          onPop: args['onPop'],
          onDone: args['onDone'],
        );
      },
      DesktopRoutes.DESKTOP_GROUP_DETAIL: (context) {
        var args = routeSettings.arguments as Map<String, dynamic>;
        return DesktopGroupDetail(args['group'], args['currentIndex']);
      },
      DesktopRoutes.DESKTOP_GROUP_CONTACT_VIEW: (context) {
        var args = routeSettings.arguments as Map<String, dynamic>;
        return GroupContactView(
          asSelectionScreen: true,
          singleSelection: false,
          showGroups: false,
          showContacts: true,
          isDesktop: true,
          selectedList: (selectedContactList) {
            GroupService().setSelectedContacts(
                selectedContactList.map((e) => e?.contact).toList());
          },
          onBackArrowTap: args['onBackArrowTap'],
          onDoneTap: args['onDoneTap'],
          contactSelectedHistory: args['contactSelectedHistory'],
        );
      }
    };
  }

  static navigator(String _route, {arguments}) {
    switch (_route) {
      case DesktopRoutes.DESKTOP_GROUP_RIGHT_INITIAL:
        return () {
          Navigator.of(NavService.groupPckgRightHalfNavKey.currentContext!)
              .pushNamed(DesktopRoutes.DESKTOP_GROUP_RIGHT_INITIAL);
        };
      case DesktopRoutes.DESKTOP_GROUP_LIST:
        return () {
          Navigator.of(NavService.groupPckgLeftHalfNavKey.currentContext!)
              .pushReplacementNamed(DesktopRoutes.DESKTOP_GROUP_LIST,
                  arguments: {
                ...arguments,
                'onDone': navigator(DesktopRoutes.DESKTOP_GROUP_RIGHT_INITIAL),
              });
        };
      case DesktopRoutes.DESKTOP_GROUP_DETAIL:
        return () {
          Navigator.of(NavService.groupPckgRightHalfNavKey.currentContext!)
              .pushReplacementNamed(DesktopRoutes.DESKTOP_GROUP_DETAIL,
                  arguments: arguments);
        };

      case DesktopRoutes.DESKTOP_NEW_GROUP:
        return () {
          Navigator.of(NavService.groupPckgRightHalfNavKey.currentContext!)
              .pushNamed(DesktopRoutes.DESKTOP_NEW_GROUP, arguments: {
            'onPop': () {
              Navigator.of(NavService.groupPckgRightHalfNavKey.currentContext!)
                  .pop();
            },
            'onDone': () {
              Navigator.of(NavService.groupPckgLeftHalfNavKey.currentContext!)
                  .pushReplacementNamed(DesktopRoutes.DESKTOP_GROUP_LIST,
                      arguments: {
                    'onDone':
                        navigator(DesktopRoutes.DESKTOP_GROUP_RIGHT_INITIAL),
                  });
              Navigator.of(NavService.groupPckgRightHalfNavKey.currentContext!)
                  .pushReplacementNamed(DesktopRoutes.DESKTOP_GROUP_DETAIL,
                      arguments: arguments);
            }
          });
        };
    }
  }
}
