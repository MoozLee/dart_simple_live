import Cocoa
import FlutterMacOS
import CoreAudio

@main
class AppDelegate: FlutterAppDelegate {
  private var methodChannel: FlutterMethodChannel?
  private var isCleanupComplete = false
  private var previousDeviceID: AudioDeviceID = 0
  
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
      
      // 设置音频设备变化监听
      setupAudioDeviceListener()
    }
  }
  
  /// 设置音频输出设备变化监听
  private func setupAudioDeviceListener() {
    // 获取当前默认输出设备
    previousDeviceID = getDefaultOutputDevice()
    
    // 监听默认输出设备变化
    var propertyAddress = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    
    let status = AudioObjectAddPropertyListener(
      AudioObjectID(kAudioObjectSystemObject),
      &propertyAddress,
      audioDeviceChangeListener,
      Unmanaged.passUnretained(self).toOpaque()
    )
    
    if status != noErr {
      print("Failed to add audio device listener: \(status)")
    }
  }
  
  /// 获取默认输出设备 ID
  private func getDefaultOutputDevice() -> AudioDeviceID {
    var deviceID: AudioDeviceID = 0
    var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
    
    var propertyAddress = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    
    AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &propertyAddress,
      0,
      nil,
      &propertySize,
      &deviceID
    )
    
    return deviceID
  }
  
  /// 检查设备是否为蓝牙设备
  private func isBluetoothDevice(_ deviceID: AudioDeviceID) -> Bool {
    var transportType: UInt32 = 0
    var propertySize = UInt32(MemoryLayout<UInt32>.size)
    
    var propertyAddress = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    
    let status = AudioObjectGetPropertyData(
      deviceID,
      &propertyAddress,
      0,
      nil,
      &propertySize,
      &transportType
    )
    
    if status == noErr {
      // kAudioDeviceTransportTypeBluetooth = 'blue' = 0x626C7565
      // kAudioDeviceTransportTypeBluetoothLE = 'blea' = 0x626C6561
      return transportType == 0x626C7565 || transportType == 0x626C6561
    }
    
    return false
  }
  
  /// 处理音频设备变化
  fileprivate func handleAudioDeviceChange() {
    let currentDeviceID = getDefaultOutputDevice()
    
    // 检查是否从蓝牙设备切换到了其他设备
    if previousDeviceID != currentDeviceID {
      let wasBluetoothDevice = isBluetoothDevice(previousDeviceID)
      let isNowBluetoothDevice = isBluetoothDevice(currentDeviceID)
      
      // 如果之前是蓝牙设备，现在不是蓝牙设备，说明蓝牙断开了
      if wasBluetoothDevice && !isNowBluetoothDevice {
        print("Bluetooth audio device disconnected, notifying Flutter to pause")
        DispatchQueue.main.async { [weak self] in
          self?.methodChannel?.invokeMethod("onAudioDeviceDisconnected", arguments: nil)
        }
      }
      
      previousDeviceID = currentDeviceID
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

/// 音频设备变化回调函数
private func audioDeviceChangeListener(
  objectID: AudioObjectID,
  numberAddresses: UInt32,
  addresses: UnsafePointer<AudioObjectPropertyAddress>,
  clientData: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let clientData = clientData else { return noErr }
  
  let appDelegate = Unmanaged<AppDelegate>.fromOpaque(clientData).takeUnretainedValue()
  appDelegate.handleAudioDeviceChange()
  
  return noErr
}
