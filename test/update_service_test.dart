import 'package:flutter_test/flutter_test.dart';
import 'package:focustimer/services/update_service.dart';

void main() {
  group('UpdateService.isVersionNewer', () {
    test('compares semantic versions with v prefix', () {
      expect(UpdateService.isVersionNewer('v1.0.1', '1.0.0'), isTrue);
      expect(UpdateService.isVersionNewer('v1.0.0', '1.0.0'), isFalse);
    });

    test('treats missing version parts as zero', () {
      expect(UpdateService.isVersionNewer('1.1', '1.0.9'), isTrue);
      expect(UpdateService.isVersionNewer('1.0.0', '1'), isFalse);
    });

    test('treats prerelease as older than stable', () {
      expect(UpdateService.isVersionNewer('1.0.0', '1.0.0-beta.1'), isTrue);
      expect(UpdateService.isVersionNewer('1.0.0-beta.1', '1.0.0'), isFalse);
    });
  });
}
