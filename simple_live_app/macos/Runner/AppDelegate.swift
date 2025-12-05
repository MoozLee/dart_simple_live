import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var methodChannel: FlutterMethodChannel?
  private var isCleanupComplete = false
  
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
  
  override func applicationDidFinishLaunching(_ notification: Notification) {
    // 设置 MethodChannel 用于与 Flutter 通信
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      methodChannel = FlutterMethodChannel(
        name: "com.xycz.simplelive/app_lifecycle",
        binaryMessenger: controller.engine.binaryMessenger
      )
      
      // 监听 Flutter 端的清理完成回调
      methodChannel?.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "cleanupComplete" {
          self?.isCleanupComplete = true
          result(nil)
          // 清理完成后，延迟一小段时间再退出，确保 MPV 线程完全停止
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
          }
        }
      }
    }
  }
  
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // 如果清理已完成，直接退出
    if isCleanupComplete {
      return .terminateNow
    }
    
    // 通知 Flutter 层进行清理
    methodChannel?.invokeMethod("prepareForTermination", arguments: nil)
    
    // 设置超时，防止清理过程卡住
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
      if !(self?.isCleanupComplete ?? true) {
        // 超时后强制退出
        NSApplication.shared.reply(toApplicationShouldTerminate: true)
      }
    }
    
    return .terminateLater
  }
}
