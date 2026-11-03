import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../constants.dart';

/// Route alerts use one FCM topic per barangay. Households subscribe to the
/// topics of the barangays they follow; the Cloud Function publishes to them.
class NotificationService {
  NotificationService({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  Future<void> requestPermission() async {
    try {
      await _messaging.requestPermission();
    } catch (e) {
      debugPrint('Notification permission failed: $e');
    }
  }

  /// Subscribes to [now] and unsubscribes from barangays that were dropped.
  Future<void> syncBarangayTopics({
    required List<String> previous,
    required List<String> now,
  }) async {
    for (final b in previous.where((b) => !now.contains(b))) {
      await _safe(() => _messaging.unsubscribeFromTopic(barangayTopic(b)));
    }
    for (final b in now) {
      await _safe(() => _messaging.subscribeToTopic(barangayTopic(b)));
    }
  }

  Future<void> unsubscribeAll(List<String> barangays) async {
    for (final b in barangays) {
      await _safe(() => _messaging.unsubscribeFromTopic(barangayTopic(b)));
    }
  }

  Stream<RemoteMessage> get foregroundMessages => FirebaseMessaging.onMessage;

  Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      debugPrint('FCM topic update failed: $e');
    }
  }
}
