import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Launch the window full-height on the active screen, anchored at the
    // top-right (cosmetic, leaves room for Terminal etc. on the left while
    // demoing). Width is the storyboard's natural value.
    if let screen = NSScreen.main {
      let visible = screen.visibleFrame
      let width = self.frame.width > 0 ? self.frame.width : 1100
      let frame = NSRect(
        x: visible.maxX - width,
        y: visible.minY,
        width: width,
        height: visible.height
      )
      self.setFrame(frame, display: true)
    } else {
      self.setFrame(self.frame, display: true)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
