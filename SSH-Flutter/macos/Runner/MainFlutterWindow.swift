import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    super.awakeFromNib()

    let flutterViewController = FlutterViewController()
    let windowFrame = NSRect(
      origin: self.frame.origin,
      size: NSSize(width: 1020, height: 880)
    )
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.title = "SSH Túnel"
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
  }
}
