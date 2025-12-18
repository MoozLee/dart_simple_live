import 'dart:io';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';

/// 应用生命周期服务
/// 用于处理应用退出时的资源清理，特别是播放器资源
/// 以及处理音频设备变化事件（如蓝牙断开）
class AppLifecycleService extends GetxService {
  static const _channel = MethodChannel('com.xycz.simplelive/app_lifecycle');
  
  /// 标记是否已经清理过播放器资源
  static bool _playerCleanedUp = false;
  
  /// 获取播放器是否已被清理
  static bool get isPlayerCleanedUp => _playerCleanedUp;
  
  /// 标记播放器已被清理（供其他地方调用）
  static void markPlayerCleanedUp() {
    _playerCleanedUp = true;
  }

  Future<AppLifecycleService> init() async {
    // 只在 macOS 上设置
    if (Platform.isMacOS) {
      _channel.setMethodCallHandler(_handleMethodCall);
    }
    return this;
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'prepareForTermination':
        await _prepareForTermination();
        break;
      case 'onAudioDeviceDisconnected':
        await _onAudioDeviceDisconnected();
        break;
    }
  }
  
  /// 处理音频设备断开事件（如蓝牙耳机断开）
  /// 暂停播放器，避免音频从扬声器播放
  Future<void> _onAudioDeviceDisconnected() async {
    Log.i('检测到音频设备断开（蓝牙耳机断开），暂停播放...');
    
    try {
      if (Get.isRegistered<LiveRoomController>()) {
        final controller = Get.find<LiveRoomController>();
        
        // 检查播放器是否正在播放
        if (controller.player.state.playing) {
          await controller.player.pause();
          Log.i('播放器已暂停');
        }
      }
    } catch (e) {
      Log.e('暂停播放器时出错: $e', StackTrace.current);
    }
  }

  /// 准备退出应用
  /// 停止所有播放器实例，确保 MPV 线程安全退出
  Future<void> _prepareForTermination() async {
    Log.i('收到应用退出通知，开始清理播放器资源...');

    // 如果播放器已经被清理过，跳过
    if (_playerCleanedUp) {
      Log.i('播放器资源已被清理，跳过重复清理');
      _notifyCleanupComplete();
      return;
    }

    try {
      // 查找并停止所有 LiveRoomController 实例
      // LiveRoomController 继承了 PlayerMixin，包含播放器实例
      if (Get.isRegistered<LiveRoomController>()) {
        final controller = Get.find<LiveRoomController>();
        Log.i('正在停止播放器...');
        
        // 先停止播放
        await controller.player.stop();
        
        // 等待一小段时间让 MPV 线程处理停止命令
        await Future.delayed(const Duration(milliseconds: 300));
        
        // 释放播放器资源
        await controller.player.dispose();
        
        _playerCleanedUp = true;
        Log.i('播放器资源已清理');
      } else {
        Log.i('没有找到活跃的 LiveRoomController');
      }
    } catch (e) {
      Log.e('清理播放器资源时出错: $e', StackTrace.current);
    }

    _notifyCleanupComplete();
  }
  
  /// 通知原生层清理完成
  Future<void> _notifyCleanupComplete() async {
    try {
      await _channel.invokeMethod('cleanupComplete');
    } catch (e) {
      Log.e('通知原生层清理完成时出错: $e', StackTrace.current);
    }
  }
}

