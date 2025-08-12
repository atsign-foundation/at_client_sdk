import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_theme_flutter/at_theme_flutter.dart';
import 'package:at_theme_flutter/services/theme_service.dart';
import 'package:at_theme_flutter/src/widgets/color_card.dart';
import 'package:at_theme_flutter/src/widgets/custom_toast.dart';
import 'package:at_theme_flutter/src/widgets/theme_mode_card.dart';
import 'package:flutter/material.dart';

class ThemeSettingPage extends StatefulWidget {
  final String title;
  final AppTheme currentAppTheme;
  final List<Color> primaryColors;
  final ValueChanged<AppTheme>? onPreviewPressed;
  final ValueChanged<AppTheme>? onApplyPressed;

  const ThemeSettingPage({
    Key? key,
    this.title = 'Theme settings',
    required this.currentAppTheme,
    required this.primaryColors,
    this.onPreviewPressed,
    this.onApplyPressed,
  })  : assert(primaryColors.length > 0),
        super(key: key);

  @override
  _ThemeSettingPageState createState() => _ThemeSettingPageState();
}

class _ThemeSettingPageState extends State<ThemeSettingPage> {
  late AppTheme _appTheme;
  bool isLoader = false;

  @override
  void initState() {
    _appTheme = widget.currentAppTheme.copyWith();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Theme(
      data: _appTheme.toThemeData(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          elevation: 0,
        ),
        body: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Theme",
                style: const TextStyle()
                    .copyWith(fontWeight: FontWeight.bold, fontSize: 15.toFont),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    flex: 1,
                    child: ThemeModeCard(
                      primaryColor: _appTheme.primaryColor,
                      brightness: Brightness.light,
                      isSelected: _appTheme.brightness == Brightness.light,
                      onPressed: () {
                        setState(() {
                          _appTheme = AppTheme.from(
                            primaryColor: _appTheme.primaryColor,
                            brightness: Brightness.light,
                          );
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 1,
                    child: ThemeModeCard(
                      primaryColor: _appTheme.primaryColor,
                      brightness: Brightness.dark,
                      isSelected: _appTheme.brightness == Brightness.dark,
                      onPressed: () {
                        setState(() {
                          _appTheme = AppTheme.from(
                            primaryColor: _appTheme.primaryColor,
                            brightness: Brightness.dark,
                          );
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                "Colour",
                style: const TextStyle()
                    .copyWith(fontWeight: FontWeight.bold, fontSize: 15.toFont),
              ),
              Expanded(
                // ignore: avoid_unnecessary_containers
                child: Container(
                  child: GridView.count(
                    crossAxisCount: 4,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    children: List.generate(
                      widget.primaryColors.length,
                      (index) {
                        return ColorCard(
                          color: widget.primaryColors[index],
                          isSelected: widget.primaryColors[index] ==
                              _appTheme.primaryColor,
                          onPressed: () {
                            setState(() {
                              _appTheme = AppTheme.from(
                                primaryColor: widget.primaryColors[index],
                                brightness: _appTheme.brightness,
                              );
                            });
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (widget.onPreviewPressed != null)
                    ElevatedButton(
                      onPressed: () {
                        widget.onPreviewPressed?.call(_appTheme);
                      },
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.all<Color>(
                            _appTheme.primaryColor),
                      ),
                      child: Container(
                        width: 80.toWidth,
                        padding: const EdgeInsets.all(10),
                        child: Center(
                          child: Text(
                            "Preview",
                            style: TextStyle(
                                color: Colors.white, fontSize: 15.toFont),
                          ),
                        ),
                      ),
                    ),
                  ElevatedButton(
                    onPressed: applyTheme,
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all<Color>(
                          _appTheme.primaryColor),
                    ),
                    child: Container(
                      width: 80.toWidth,
                      padding: const EdgeInsets.all(10),
                      child: Center(
                        child: isLoader
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white),
                              )
                            : Text(
                                "Apply",
                                style: TextStyle(
                                    color: Colors.white, fontSize: 15.toFont),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  applyTheme() async {
    setState(() {
      isLoader = true;
    });

    var res = await ThemeService().updateThemeData(_appTheme);

    if (mounted) {
      setState(() {
        isLoader = false;
      });
    }

    if (res) widget.onApplyPressed?.call(_appTheme);

    if (Navigator.of(context).canPop() && res) {
      Navigator.pop(context);
    }

    if (!res) {
      CustomToast().show('Something went wrong', context);
    }
  }
}
