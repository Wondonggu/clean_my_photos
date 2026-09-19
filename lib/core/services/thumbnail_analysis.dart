import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../models/asset_signature.dart';
import '../models/media_item.dart';
import '../utils/blur_analyzer.dart';
import '../utils/cancel_signal.dart';
import 'image_analyzer.dart';

/// 一张待分析的缩略图。
class ThumbnailJob {
  const ThumbnailJob({required this.id, required this.bytes});

  final String id;
  final Uint8List bytes;
}

/// 一批分析请求。设计成可跨 isolate 传递的纯数据。
class ThumbnailBatchRequest {
  const ThumbnailBatchRequest({
    required this.jobs,
    this.blurThreshold = BlurAnalyzer.defaultThreshold,
    this.maxSide = 256,
  });

  final List<ThumbnailJob> jobs;
  final double blurThreshold;
  final int maxSide;
}

/// 单张图的分析结果。
class ThumbnailAnalysis {
  const ThumbnailAnalysis({required this.id, this.fingerprint, this.error});

  final String id;
  final ImageFingerprint? fingerprint;
  final String? error;

  bool get isSuccess => fingerprint != null;
}

/// isolate 入口：一批缩略图一次算完，摊薄 isolate 启动开销。
///
/// 必须是顶层函数，参数与返回值都要能跨 isolate 传递。
List<ThumbnailAnalysis> analyzeThumbnailBatch(ThumbnailBatchRequest request) {
  final analyzer = ImageAnalyzer(
    blurThreshold: request.blurThreshold,
    maxSide: request.maxSide,
  );

  final results = <ThumbnailAnalysis>[];
  for (final job in request.jobs) {
    try {
      final fingerprint = analyzer.analyzeBytes(job.bytes);
      results.add(
        ThumbnailAnalysis(
          id: job.id,
          fingerprint: fingerprint,
          error: fingerprint == null ? '图片解码失败' : null,
        ),
      );
    } catch (error) {
      results.add(ThumbnailAnalysis(id: job.id, error: error.toString()));
    }
  }
  return results;
}

/// 把一批 [MediaItem] 变成带指纹的 [AssetSignature]。
///
/// 只有图片会被分析：视频的封面帧不足以判断「重复」，硬要分组误伤太大。
class SignatureAnalyzer {
  const SignatureAnalyzer({
    this.windowSize = 24,
    this.thumbnailSize = 256,
    this.thumbnailQuality = 75,
    this.blurThreshold = BlurAnalyzer.defaultThreshold,
    this.useIsolates,
  });

  /// 每一轮并发处理的图片数量。
  final int windowSize;

  /// 请求缩略图的边长。
  ///
  /// 256 足够算 9×8 的 dHash，也能让拉普拉斯方差落在可比区间。
  final int thumbnailSize;

  final int thumbnailQuality;
  final double blurThreshold;

  /// 是否放到后台 isolate 里计算。默认在移动端开启、Web 上关闭。
  final bool? useIsolates;

  bool get _isolatesEnabled => useIsolates ?? !kIsWeb;

  /// [loadThumbnail] 由数据层提供（通常是 [PhotoRepository.thumbnail]）。
  Future<List<AssetSignature>> analyze({
    required List<MediaItem> items,
    required Future<Uint8List?> Function(MediaItem item) loadThumbnail,
    void Function(int done, int total)? onProgress,
    CancelSignal? cancel,
  }) async {
    final targets = items
        .where((item) => item.kind == MediaKind.image)
        .toList(growable: false);

    // 视频与音频直接给出没有指纹的签名，保证 UI 上数量对得上。
    final results = <String, AssetSignature>{
      for (final item in items)
        if (item.kind != MediaKind.image) item.id: AssetSignature(item: item),
    };

    if (targets.isEmpty) {
      onProgress?.call(0, 0);
      return results.values.toList();
    }

    var done = 0;
    for (var start = 0; start < targets.length; start += windowSize) {
      if (cancel?.isCancelled ?? false) break;

      final end = (start + windowSize).clamp(0, targets.length);
      final window = targets.sublist(start, end);

      final jobs = <ThumbnailJob>[];
      final pending = <MediaItem>[];

      final bytesList = await Future.wait(
        window.map((item) async {
          try {
            return await loadThumbnail(item);
          } catch (_) {
            return null;
          }
        }),
      );

      for (var i = 0; i < window.length; i++) {
        final bytes = bytesList[i];
        if (bytes == null || bytes.isEmpty) {
          results[window[i].id] =
              AssetSignature(item: window[i], failure: '缩略图不可用');
          continue;
        }
        jobs.add(ThumbnailJob(id: window[i].id, bytes: bytes));
        pending.add(window[i]);
      }

      if (jobs.isNotEmpty) {
        final analyses = await _analyzeBatch(jobs);
        for (final analysis in analyses) {
          final index = pending.indexWhere((item) => item.id == analysis.id);
          if (index < 0) continue;
          final item = pending[index];
          final fingerprint = analysis.fingerprint;
          results[item.id] = fingerprint == null
              ? AssetSignature(item: item, failure: analysis.error)
              : AssetSignature(
                  item: item,
                  hash: fingerprint.hash,
                  sharpness: fingerprint.sharpness,
                  isBlurry: fingerprint.isBlurry,
                  failure: null,
                );
        }
      }

      done += window.length;
      onProgress?.call(done, targets.length);
    }

    return results.values.toList();
  }

  Future<List<ThumbnailAnalysis>> _analyzeBatch(List<ThumbnailJob> jobs) async {
    final request = ThumbnailBatchRequest(
      jobs: jobs,
      blurThreshold: blurThreshold,
      maxSide: thumbnailSize,
    );

    if (!_isolatesEnabled) {
      return analyzeThumbnailBatch(request);
    }

    try {
      return await Isolate.run(() => analyzeThumbnailBatch(request));
    } catch (_) {
      // isolate 在某些受限环境下不可用，退回主 isolate。
      return analyzeThumbnailBatch(request);
    }
  }
}
