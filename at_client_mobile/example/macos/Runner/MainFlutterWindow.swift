import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
    final let screenWidth: Int = 1024
    final let screenHeight: Int = 576
    
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    let x: Int = (Int(self.screen?.frame.width ?? 0) - screenWidth) / 2
    let y: Int = (Int(self.screen?.frame.height ?? 0) - screenHeight) / 2
    let windowFrame = NSRect(x: x, y: y, width: screenWidth, height: screenHeight)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
