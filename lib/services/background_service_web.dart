// Mock implementation for web platforms
import 'dart:async';
import 'dart:developer' as developer;

// Mock FlutterBackgroundService class for web
class FlutterBackgroundService {
  // Mock configure method
  Future<void> configure({
    required dynamic androidConfiguration,
    required dynamic iosConfiguration,
  }) async {
    // Do nothing on web
    developer.log('Background service not supported on web platform');
    return;
  }

  // Mock on method
  Stream<Map<String, dynamic>?> on(String event) {
    // Return an empty stream
    return Stream<Map<String, dynamic>?>.empty();
  }

  // Mock invoke method
  Future<bool> invoke(String method, [Map<String, dynamic>? args]) async {
    // Do nothing on web
    return true;
  }
}

// Mock ServiceInstance class for web
class ServiceInstance {
  // Mock setAsForegroundService method
  void setAsForegroundService() {
    // Do nothing on web
  }

  // Mock setForegroundNotificationInfo method
  Future<void> setForegroundNotificationInfo({
    required String title,
    required String content,
  }) async {
    // Do nothing on web
    return;
  }

  // Mock invoke method
  void invoke(String method, [Map<String, dynamic>? args]) {
    // Do nothing on web
  }

  // Mock on method
  Stream<Map<String, dynamic>?> on(String event) {
    // Return an empty stream
    return Stream<Map<String, dynamic>?>.empty();
  }

  // Mock stopSelf method
  Future<void> stopSelf() async {
    // Do nothing on web
    return;
  }
}

// Mock AndroidServiceInstance class for web
class AndroidServiceInstance extends ServiceInstance {
  // All methods inherited from ServiceInstance
}

// Mock AndroidConfiguration class for web
class AndroidConfiguration {
  AndroidConfiguration({
    required Function onStart,
    required bool autoStart,
    required bool isForegroundMode,
    required String notificationChannelId,
    required String initialNotificationTitle,
    required String initialNotificationContent,
    required int foregroundServiceNotificationId,
  });
}

// Mock IosConfiguration class for web
class IosConfiguration {
  IosConfiguration({
    required bool autoStart,
    required Function onForeground,
    required Function onBackground,
  });
}
