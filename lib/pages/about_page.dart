import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String _appName = '专注时钟';
  static const String _description = '用于连接 FocusTimer 设备，同步专注与休息数据。';

  static const String _authorName = 'VRxiaojie';

  static const String _bilibiliUrl = 'https://space.bilibili.com/11526854';
  static const String _githubUrl = 'https://github.com/vrxiaojie';
  static const String _OshwhubUrl = 'https://oshwhub.com/vrxiaojie/works';

  static const String _bilibiliLogoAsset = 'assets/logos/bilibili.png';
  static const String _githubLogoAsset = 'assets/logos/github.png';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const Text(
              _appName,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              _description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            const _AboutLineCard(
              title: '作者',
              value: _authorName,
              leading: Icon(Icons.person_outline, color: Colors.grey, size: 22),
            ),
            _buildVersionCard(),
            _AboutLineCard(
              title: 'B站',
              value: _bilibiliUrl,
              leading: const _AssetLogo(assetPath: _bilibiliLogoAsset),
              valueMaxLines: 2,
              onTap: () => _openUrl(context, _bilibiliUrl),
            ),
            _AboutLineCard(
              title: 'GitHub',
              value: _githubUrl,
              leading: const _AssetLogo(assetPath: _githubLogoAsset),
              valueMaxLines: 2,
              onTap: () => _openUrl(context, _githubUrl),
            ),
            _AboutLineCard(
              title: '立创开源广场',
              value: _OshwhubUrl,
              leading: const _NetworkIcon(),
              valueMaxLines: 2,
              onTap: () => _openUrl(context, _OshwhubUrl),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionCard() {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final versionText = info == null
            ? '--'
            : '${info.version}${info.buildNumber.isNotEmpty ? '+${info.buildNumber}' : ''}';
        return _AboutLineCard(
          title: '版本',
          value: versionText,
          leading: const Icon(
            Icons.info_outline,
            color: Colors.grey,
            size: 22,
          ),
        );
      },
    );
  }

  static Future<void> _openUrl(BuildContext context, String urlString) async {
    final uri = Uri.tryParse(urlString);
    if (uri == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('链接格式不正确')),
        );
      }
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开链接')),
      );
    }
  }
}

class _AboutLineCard extends StatelessWidget {
  const _AboutLineCard({
    required this.title,
    required this.value,
    required this.leading,
    this.valueMaxLines = 1,
    this.onTap,
  });

  final String title;
  final String value;
  final Widget leading;
  final int valueMaxLines;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Center(child: leading),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: valueMaxLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetLogo extends StatelessWidget {
  const _AssetLogo({required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.asset(
        assetPath,
        width: 24,
        height: 24,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) {
          return Container(
            width: 24,
            height: 24,
            color: Colors.grey[200],
            alignment: Alignment.center,
            child: const Text(
              'Logo',
              style: TextStyle(fontSize: 8),
            ),
          );
        },
      ),
    );
  }
}

class _NetworkIcon extends StatelessWidget {
  const _NetworkIcon();

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.language,
      size: 22,
      color: Colors.lightBlueAccent,
    );
  }
}
