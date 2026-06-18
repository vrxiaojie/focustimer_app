import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    required this.latestVersion,
    required this.hasUpdate,
    required this.releaseUrl,
    this.releaseName,
  });

  final String currentVersion;
  final String latestVersion;
  final bool hasUpdate;
  final String releaseUrl;
  final String? releaseName;
}

class UpdateService {
  UpdateService._();

  static const String releasesPageUrl =
      'https://github.com/vrxiaojie/focustimer_app/releases';

  static final Uri _latestReleaseUri = Uri.https(
    'api.github.com',
    '/repos/vrxiaojie/focustimer_app/releases/latest',
  );

  static Future<UpdateCheckResult> checkLatestRelease({
    required String currentVersion,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    final shouldCloseClient = client == null;

    try {
      final response = await httpClient.get(
        _latestReleaseUri,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': 'FocusTimer-App',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw UpdateCheckException(
          'GitHub 返回 ${response.statusCode}，请稍后再试',
        );
      }

      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) {
        throw const UpdateCheckException('更新信息格式不正确');
      }

      final tagName = json['tag_name']?.toString().trim();
      if (tagName == null || tagName.isEmpty) {
        throw const UpdateCheckException('发布页没有版本标签');
      }

      final releaseUrl = json['html_url']?.toString().trim();
      final releaseName = json['name']?.toString().trim();
      final latestVersion = normalizeVersionTag(tagName);

      return UpdateCheckResult(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        hasUpdate: isVersionNewer(latestVersion, currentVersion),
        releaseUrl: releaseUrl == null || releaseUrl.isEmpty
            ? releasesPageUrl
            : releaseUrl,
        releaseName:
            releaseName == null || releaseName.isEmpty ? null : releaseName,
      );
    } on TimeoutException {
      throw const UpdateCheckException('检查更新超时，请检查网络后重试');
    } on FormatException {
      throw const UpdateCheckException('更新信息解析失败');
    } finally {
      if (shouldCloseClient) {
        httpClient.close();
      }
    }
  }

  static String normalizeVersionTag(String tagName) {
    return tagName.trim().replaceFirst(RegExp(r'^[vV]'), '');
  }

  static bool isVersionNewer(String latestVersion, String currentVersion) {
    final latest = _ParsedVersion.parse(latestVersion);
    final current = _ParsedVersion.parse(currentVersion);
    return latest.compareTo(current) > 0;
  }
}

class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ParsedVersion implements Comparable<_ParsedVersion> {
  const _ParsedVersion({
    required this.numbers,
    required this.hasPrerelease,
  });

  final List<int> numbers;
  final bool hasPrerelease;

  static _ParsedVersion parse(String input) {
    final normalized = UpdateService.normalizeVersionTag(input);
    final withoutBuild = normalized.split('+').first;
    final prereleaseParts = withoutBuild.split('-');
    final numberParts = prereleaseParts.first
        .split('.')
        .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')))
        .map((value) => value ?? 0)
        .toList();

    return _ParsedVersion(
      numbers: numberParts,
      hasPrerelease: prereleaseParts.length > 1,
    );
  }

  @override
  int compareTo(_ParsedVersion other) {
    final maxLength = numbers.length > other.numbers.length
        ? numbers.length
        : other.numbers.length;

    for (var i = 0; i < maxLength; i++) {
      final left = i < numbers.length ? numbers[i] : 0;
      final right = i < other.numbers.length ? other.numbers[i] : 0;
      if (left != right) {
        return left.compareTo(right);
      }
    }

    if (hasPrerelease == other.hasPrerelease) {
      return 0;
    }
    return hasPrerelease ? -1 : 1;
  }
}
