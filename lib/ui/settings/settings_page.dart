import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/similarity_grouper.dart';
import '../../core/utils/formatters.dart';
import '../../state/library_controller.dart';
import '../../state/settings_controller.dart';

/// 设置页。
///
/// 只放真正会影响结果的参数：判定松紧、模糊阈值、大文件门槛。
/// 改完立刻重算分类，不需要手动「保存」。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final library = context.watch<LibraryController>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          const _SectionHeader('相似照片判定'),
          _OptionTile(
            title: '严格',
            subtitle: '只有几乎完全一样的照片才会归为一组，最不容易误判',
            selected: settings.similarity == SimilarityOptions.strict,
            onTap: () => settings.setSimilarity(SimilarityOptions.strict),
          ),
          _OptionTile(
            title: '均衡（推荐）',
            subtitle: '同一场景的连拍会被识别为相似，兼顾准确与效果',
            selected: settings.similarity == SimilarityOptions.balanced,
            onTap: () => settings.setSimilarity(SimilarityOptions.balanced),
          ),
          _OptionTile(
            title: '宽松',
            subtitle: '构图相近的照片也会归为一组，清理得更彻底',
            selected: settings.similarity == SimilarityOptions.loose,
            onTap: () => settings.setSimilarity(SimilarityOptions.loose),
          ),

          const _SectionHeader('模糊照片判定'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '清晰度阈值 ${settings.blurThreshold.round()}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      settings.blurThreshold <= 60
                          ? '严格'
                          : settings.blurThreshold <= 150
                              ? '均衡'
                              : '宽松',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withAlpha(150),
                          ),
                    ),
                  ],
                ),
                Slider(
                  value: settings.blurThreshold.clamp(20.0, 400.0),
                  min: 20,
                  max: 400,
                  divisions: 38,
                  label: '${settings.blurThreshold.round()}',
                  onChanged: (value) => settings.setBlurThreshold(value),
                ),
                Text(
                  '数值越小判定越严格。拉普拉斯方差的绝对值因设备而异，'
                  '如果误判较多，往右调一格更保险。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withAlpha(140),
                        height: 1.5,
                      ),
                ),
              ],
            ),
          ),

          const _SectionHeader('大文件门槛'),
          _ThresholdTile(
            label: '超大视频',
            value: settings.largeVideoMb,
            options: const <int>[50, 100, 200, 500, 1000],
            format: (value) =>
                value >= 1000 ? '${value ~/ 1000} GB' : '$value MB',
            onChanged: settings.setLargeVideoMb,
          ),
          _ThresholdTile(
            label: '超大照片',
            value: settings.largePhotoMb,
            options: const <int>[2, 5, 8, 15, 30, 60],
            format: (value) => '$value MB',
            onChanged: settings.setLargePhotoMb,
          ),

          const _SectionHeader('扫描'),
          SwitchListTile(
            value: settings.autoAnalyze,
            onChanged: settings.setAutoAnalyze,
            title: const Text('打开应用后自动分析'),
            subtitle: const Text('自动找出重复、相似和模糊的照片'),
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('重新分析照片内容'),
            subtitle: const Text('重新计算指纹，用于重复 / 相似 / 模糊判定'),
            enabled: library.items.isNotEmpty && library.imageProgress == null,
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              await library.runImageAnalysis(force: true);
              messenger.showSnackBar(
                const SnackBar(content: Text('分析完成')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.straighten),
            title: const Text('重新统计文件大小'),
            subtitle: const Text('只扫描体积较大的项目，可能需要一会儿'),
            enabled: library.items.isNotEmpty && library.sizeProgress == null,
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              await library.scanFileSizes();
              messenger.showSnackBar(
                const SnackBar(content: Text('统计完成')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('清空扫描缓存'),
            subtitle: const Text('分析结果会被记下来，下次打开直接复用。清空后下次要重算一遍'),
            enabled: !library.isBusy,
            onTap: () => _confirmClearCache(context, library),
          ),
          if (library.sizeProgress != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(
                value: library.sizeProgress!.isIndeterminate
                    ? null
                    : library.sizeProgress!.ratio,
              ),
            ),

          const _SectionHeader('关于'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              '相册清理在你的手机上完成全部分析，照片不会被上传到任何服务器。\n'
              '删除操作会调用系统相册接口，系统仍会再确认一次；'
              '删除的照片进入「最近删除」，30 天内可以恢复。\n'
              '已收藏的照片永远不会被建议删除。',
              style: TextStyle(height: 1.6, fontSize: 13),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              '相册内共 ${formatCount(library.totalCount)} 项，'
              '已读取 ${formatCount(library.items.length)} 项',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(130),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 清缓存要确认一下：下次打开会重新分析几分钟，得让人知道自己在点什么。
Future<void> _confirmClearCache(
  BuildContext context,
  LibraryController library,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text('清空扫描缓存？'),
      content: const Text('已经算好的指纹和文件大小都会被丢掉，下次打开要重新分析一遍。'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('清空'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  await library.clearScanCaches();
  messenger.showSnackBar(const SnackBar(content: Text('扫描缓存已清空')));
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface.withAlpha(90),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : null,
        ),
      ),
      subtitle: Text(subtitle, style: const TextStyle(height: 1.4)),
    );
  }
}

class _ThresholdTile extends StatelessWidget {
  const _ThresholdTile({
    required this.label,
    required this.value,
    required this.options,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final int value;
  final List<int> options;
  final String Function(int) format;
  final Future<void> Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final option in options)
                ChoiceChip(
                  label: Text(format(option)),
                  selected: option == value,
                  onSelected: (_) => onChanged(option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
