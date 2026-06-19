import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:focustimer/services/update_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('UpdateService.checkLatestRelease', () {
    test('parses release body and metadata from GitHub response', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'api.github.com');
        return http.Response(
          jsonEncode({
            'tag_name': 'v1.2.0',
            'html_url': 'https://github.com/example/repo/releases/tag/v1.2.0',
            'name': 'FocusTimer 1.2.0',
            'body': '## 更新内容\n- 新增更新弹窗',
          }),
          200,
        );
      });

      final result = await UpdateService.checkLatestRelease(
        currentVersion: '1.1.0',
        client: client,
      );

      expect(result.hasUpdate, isTrue);
      expect(result.latestVersion, '1.2.0');
      expect(
        result.releaseUrl,
        'https://github.com/example/repo/releases/tag/v1.2.0',
      );
      expect(result.releaseName, 'FocusTimer 1.2.0');
      expect(result.releaseBody, '## 更新内容\n- 新增更新弹窗');
    });
  });

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
