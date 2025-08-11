#import "AtEventsFlutterPlugin.h"
#if __has_include(<at_events_flutter/at_events_flutter-Swift.h>)
#import <at_events_flutter/at_events_flutter-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "at_events_flutter-Swift.h"
#endif

@implementation AtEventsFlutterPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftAtEventsFlutterPlugin registerWithRegistrar:registrar];
}
@end
