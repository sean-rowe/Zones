import AppKit
import ZonesCore

// Thin entry point. Everything that could be tested lives in ZonesCore;
// nothing but process startup belongs here.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
