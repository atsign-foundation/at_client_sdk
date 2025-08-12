#import "AtNotifyFlutterPlugin.h"
#if __has_include(<at_notify_flutter/at_notify_flutter-Swift.h>)
#import <at_notify_flutter/at_notify_flutter-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "at_notify_flutter-Swift.h"
#endif

@implementation AtNotifyFlutterPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftAtNotifyFlutterPlugin registerWithRegistrar:registrar];
}
@end
