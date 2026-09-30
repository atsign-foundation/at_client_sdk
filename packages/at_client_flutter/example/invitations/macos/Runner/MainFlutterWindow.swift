import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    #if DEBUG
    if ProcessInfo.processInfo.environment["DEMO_ROLE"] != nil {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.placeForDemo() }
      DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { self.placeForDemo() }
    }
    #endif
  }

  /// Places the window where demo/demo.sh asks, in DEMO_FRAME ("x,y,w,h" in
  /// points from the bottom left), titles it after DEMO_ROLE, and floats it
  /// above other windows so that nothing covers it during a demo.
  private func placeForDemo() {
    let env = ProcessInfo.processInfo.environment
    if let spec = env["DEMO_FRAME"] {
      let n = spec.split(separator: ",").compactMap { Double($0) }
      if n.count == 4 && n.allSatisfy({ $0.isFinite }) {
        self.setFrame(
          NSRect(x: n[0], y: n[1], width: n[2], height: n[3]),
          display: true, animate: false)
      }
    }
    if let role = env["DEMO_ROLE"] {
      self.title = role.prefix(1).uppercased() + role.dropFirst()
      self.level = .floating
    }
  }
}
