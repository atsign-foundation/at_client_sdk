import 'package:at_app_flutter/at_app_flutter.dart';
import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
// import 'package:at_utils/at_logger.dart' show AtSignLogger;

import 'package:flutter/material.dart';

import 'contact_initial.dart';
import 'main.dart';

class AtSignBottomSheet extends StatefulWidget {
  final List<String> atSignList;
  final Function? showLoader;

  const AtSignBottomSheet(
      {Key key = const Key('atsign'),
      this.atSignList = const [],
      this.showLoader})
      : super(key: key);

  @override
  AtSignBottomSheetState createState() => AtSignBottomSheetState();
}

class AtSignBottomSheetState extends State<AtSignBottomSheet> {
//  var atClientManager = AtClientManager.getInstance();
  bool isLoading = false;
  late AtClientPreference atClientPreferenceLocal;
  // final AtSignLogger _logger = AtSignLogger(AtEnv.appNamespace);

  @override
  Widget build(BuildContext context) {
    var screenSize = MediaQuery.of(context).size;
    loadAtClientPreference().then((value) => atClientPreferenceLocal = value);
    return Stack(
      children: [
        Positioned(
          bottom: 0,
          child: BottomSheet(
            onClosing: () {},
            backgroundColor: Colors.transparent,
            builder: (context) => ClipRRect(
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10), topRight: Radius.circular(10)),
              child: Container(
                height: 100,
                width: screenSize.width,
                color: Theme.of(context).canvasColor,
                child: Row(
                  children: [
                    Expanded(
                        child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.atSignList.length,
                      itemBuilder: (context, index) => GestureDetector(
                        onTap: isLoading
                            ? () {}
                            : () async {
                                if (mounted) {
                                  setState(() {
                                    isLoading = true;
                                  });
                                }
                                final result =
                                    await AtOnboarding.changePrimaryAtsign(
                                        atsign: widget.atSignList[index]);
                                if (result && context.mounted) {
                                  await AtOnboarding.onboard(
                                    context: context,
                                    config: AtOnboardingConfig(
                                      atClientPreference:
                                          atClientPreferenceLocal,
                                      domain: AtEnv.rootDomain,
                                      rootEnvironment: AtEnv.rootEnvironment,
                                      appAPIKey: AtEnv.appApiKey,
                                    ),
                                  );
                                    setState(() {
                                      isLoading = false;
                                    });
                                  if(!context.mounted) return;
                                  Navigator.pop(context);
                                } else {
                                  //Failure
                                  if (mounted) {
                                    setState(() {
                                      isLoading = false;
                                    });
                                  }
                                }
                              },
                        child: Padding(
                          padding: const EdgeInsets.only(
                              left: 10, right: 10, top: 20),
                          child: Column(
                            children: [
                              ContactInitial(
                                initials: widget.atSignList[index],
                              ),
                              Text(
                                widget.atSignList[index],
                                // ignore: deprecated_member_use
                                style: Theme.of(context).textTheme.bodyMedium,
                              )
                            ],
                          ),
                        ),
                      ),
                    )),
                    const SizedBox(
                      width: 20,
                    ),
                    GestureDetector(
                      onTap: () async {
                        setState(() {
                          isLoading = true;
                        });
                        final result = await AtOnboarding.onboard(
                          context: context,
                          config: AtOnboardingConfig(
                            atClientPreference: atClientPreferenceLocal,
                            domain: AtEnv.rootDomain,
                            rootEnvironment: AtEnv.rootEnvironment,
                            appAPIKey: AtEnv.appApiKey,
                          ),
                          isSwitchingAtsign: true,
                        );
                        switch (result.status) {
                          case AtOnboardingResultStatus.success:
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const HomeScreen()));
                            break;
                          case AtOnboardingResultStatus.error:
                            // TODO: Handle this case.
                            break;
                          case AtOnboardingResultStatus.cancel:
                            // TODO: Handle this case.
                            break;
                        }

                        if (mounted) {
                          setState(() {
                            isLoading = false;
                          });
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 10),
                        height: 40,
                        width: 40,
                        child: const Icon(
                          Icons.add_circle_outline_outlined,
                          color: Colors.orange,
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
        isLoading
            ? const Center(
                child: Column(
                  children: [
                    Text(
                      'Switching atsign...',
                      style: TextStyle(
                        color: Color(0xffF05E3F),
                        fontSize: 16,
                        letterSpacing: 0.1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 10),
                    CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFFF05E3E))),
                  ],
                ),
              )
            : const SizedBox(
                height: 100,
              ),
      ],
    );
  }
}
