import 'package:at_app_flutter/at_app_flutter.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_common_flutter/services/size_config.dart';
import 'package:at_theme_flutter/at_theme_flutter.dart';
import 'package:at_theme_flutter_example/main.dart';
import 'package:at_theme_flutter_example/src/utils/color_constants.dart';
import 'package:at_theme_flutter_example/src/utils/text_styles.dart';
import 'package:flutter/material.dart';

class ProfilePage extends StatefulWidget {
  final String title;

  const ProfilePage({
    Key? key,
    this.title = 'My Profile',
  }) : super(key: key);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with SingleTickerProviderStateMixin {
  late TabController tabController;
  String? activeAtSign;

  /// Get the AtClientManager instance
  var atClientManager = AtClientManager.getInstance();

  @override
  void initState() {
    super.initState();
    getAtSignAndInitialize();
    initializeThemeService(rootDomain: AtEnv.rootDomain);
    tabController = TabController(length: 3, vsync: this);
    getSavedTheme();
  }

  /// getting saved theme
  getSavedTheme() async {
    AppTheme? appTheme = await getThemeData();
    if (appTheme != null) appThemeController.sink.add(appTheme);
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final appTheme = AppTheme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: appTheme.primaryColor,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _onOpenSettingPressed,
            icon: Icon(Icons.settings_outlined, size: 18.toFont),
          ),
        ],
      ),
      body: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: appTheme.primaryColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Atsign",
                        style: TextStyle(fontSize: 15.toFont),
                      ),
                      Text(
                        activeAtSign ?? 'Atsign',
                        style: TextStyle(color: appTheme.secondaryColor, fontSize: 15.toFont),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Container(
              height: 56.toHeight,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                // color: appTheme.primary,
                borderRadius: BorderRadius.circular(28.toHeight),
                border: Border.all(width: 1, color: Colors.grey),
              ),
              child: TabBar(
                controller: tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    28.0.toHeight,
                  ),
                  color: appTheme.primaryColor,
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey,
                enableFeedback: false,
                tabs: <Widget>[
                  Center(
                    child: Text(
                      "Tab One",
                      style: TextStyles.text15,
                    ),
                  ),
                  Center(
                    child: Text(
                      "Tab Two",
                      style: TextStyles.text15,
                    ),
                  ),
                  Center(
                    child: Text(
                      "Tab Three",
                      style: TextStyles.text15,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              "Basic Details",
              style: TextStyle(
                fontSize: 18.toFont,
                fontWeight: FontWeight.bold,
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: appTheme.primaryColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Phone number",
                    style: TextStyle(
                      fontSize: 16.toFont,
                      color: const Color(0xFF707070),
                    ),
                  ),
                  Text(
                    "+1 408 432 9012",
                    style: TextStyle(
                      fontSize: 18.toFont,
                      color: appTheme.primaryColor,
                    ),
                  ),
                  SizedBox(height: 8.toHeight),
                  const Divider(height: 1),
                  SizedBox(height: 8.toHeight),
                  Text(
                    "Email Address",
                    style: TextStyle(
                      fontSize: 16.toFont,
                      color: const Color(0xFF707070),
                    ),
                  ),
                  Text(
                    "atsign@atsign.com",
                    style: TextStyle(
                      fontSize: 18.toFont,
                      color: appTheme.primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  void _onOpenSettingPressed() {
    showModalBottomSheet<void>(
        context: context,
        builder: (BuildContext context) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text("Default theme setting", style: TextStyles.text15),
                  trailing: Icon(Icons.chevron_right, size: 15.toFont),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openDefaultThemSetting();
                  },
                ),
                ListTile(
                  title: Text("Custom theme setting", style: TextStyles.text15),
                  trailing: Icon(Icons.chevron_right, size: 15.toFont),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openCustomThemSetting();
                  },
                ),

                /// we can save theme data without using package ui by using setAppTheme function.
                ListTile(
                  title: Text("Set theme without using package UI", style: TextStyles.text15),
                  trailing: Icon(Icons.chevron_right, size: 15.toFont),
                  onTap: () async {
                    var appTheme = AppTheme.from();
                    var res = await setAppTheme(appTheme);
                    if (res && context.mounted) {
                      Navigator.of(context).pop();
                      appThemeController.sink.add(appTheme);
                    }
                  },
                ),
              ],
            ),
          );
        });
  }

  void _openDefaultThemSetting() {
    final appTheme = AppTheme.of(context);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ThemeSettingPage(
          currentAppTheme: appTheme,
          primaryColors: ColorConstants.primaryColors,
          onApplyPressed: (appTheme) {
            appThemeController.sink.add(appTheme);
          },
          onPreviewPressed: (appTheme) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => Theme(
                  data: appTheme.toThemeData(),
                  child: InheritedAppTheme(
                    theme: appTheme,
                    child: const ProfilePage(
                      title: "Preview",
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void getAtSignAndInitialize() async {
    var currentAtSign = atClientManager.atClient.getCurrentAtSign();
    setState(() {
      activeAtSign = currentAtSign;
    });
  }

  void _openCustomThemSetting() {
    final appTheme = AppTheme.of(context);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ThemeSettingPage(
          currentAppTheme: appTheme,
          primaryColors: const [
            Colors.red,
            Colors.redAccent,
            Colors.green,
            Colors.greenAccent,
            Colors.lightGreen,
            Colors.lightGreenAccent,
            Colors.blue,
            Colors.blueAccent,
            Colors.lightBlue,
            Colors.lightBlueAccent,
            Colors.purple,
            Colors.purpleAccent,
            Colors.orange,
            Colors.orangeAccent,
            Colors.deepOrange,
            Colors.deepOrangeAccent,
            Colors.yellow,
            Colors.yellowAccent,
            Colors.teal,
            Colors.tealAccent,
          ],
          onApplyPressed: (appTheme) {
            appThemeController.sink.add(appTheme);
          },
          onPreviewPressed: (appTheme) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => Theme(
                  data: appTheme.toThemeData(),
                  child: InheritedAppTheme(
                    theme: appTheme,
                    child: const ProfilePage(
                      title: "Preview",
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
