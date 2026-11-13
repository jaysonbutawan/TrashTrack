import 'repositories.dart';

/// Route alerts (FCM) are not wired yet; this does nothing.
class NoopPushService implements PushService {
  @override
  Future<void> requestPermission() async {}
  @override
  Future<void> syncFollowedBarangays(List<String> barangays) async {}
  @override
  Future<void> clear() async {}
}
