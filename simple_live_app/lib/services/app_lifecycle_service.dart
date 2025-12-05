import 'dart:io';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';

/// 应用生命周期服务
/// 用于处理应用退出时的资源清理，特别是播放器资源
class AppLifecycleService extends GetxService {
  static const _channel = MethodChannel('com.xycz.simplelive/app_lifecycle');

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
    }
  }

  /// 准备退出应用
  /// 停止所有播放器实例，确保 MPV 线程安全退出
  Future<void> _prepareForTermination() async {
    Log.i('收到应用退出通知，开始清理播放器资源...');

    try {
      // 查找并停止所有 LiveRoomController 实例
      // LiveRoomController 继承了 PlayerMixin，包含播放器实例
      if (Get.isRegistered<LiveRoomController>()) {
        final controller = Get.find<LiveRoomController>();
        Log.i('正在停止播放器...');
        
        // 先停止播放
        await controller.player.stop();
        
        // 等待一小段时间让 MPV 线程处理停止命令
        await Future.delayed(const Duration(milliseconds: 200));
        
        // 释放播放器资源
        await controller.player.dispose();
        
        Log.i('播放器资源已清理');
      }
    } catch (e) {
      Log.e('清理播放器资源时出错: $e', StackTrace.current);
    }

    // 通知原生层清理完成
    try {
      await _channel.invokeMethod('cleanupComplete');
    } catch (e) {
      Log.e('通知原生层清理完成时出错: $e', StackTrace.current);
    }
  }
}

