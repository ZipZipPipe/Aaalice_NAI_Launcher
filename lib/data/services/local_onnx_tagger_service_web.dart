import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_onnx_model_service.dart';
import 'local_onnx_tagger_service_types.dart';

export 'local_onnx_tagger_service_types.dart';

/// Web 版桩：浏览器编译图不包含本地 ONNX 运行时（onnxruntime_v2 / dart:ffi）。
///
/// [LocalOnnxTaggerService.tagImage] 统一抛出 [UnsupportedError]；
/// [LocalOnnxTaggerService.loadLabels] 返回空列表。上层界面应在 Web 下隐藏
/// ONNX 打标入口（P2 起由能力开关统一处理）。
final localOnnxTaggerServiceProvider = Provider<LocalOnnxTaggerService>((ref) {
  return const LocalOnnxTaggerService();
});

class LocalOnnxTaggerService {
  const LocalOnnxTaggerService();

  Future<OnnxTaggerResult> tagImage({
    required Uint8List imageBytes,
    required LocalOnnxModelDescriptor model,
    double? threshold,
    double generalThreshold = 0.35,
    double characterThreshold = 0.35,
    bool includeRatings = false,
  }) async {
    throw UnsupportedError('本地 ONNX 打标在 Web 版暂不可用');
  }

  Future<List<OnnxTaggerLabel>> loadLabels(String labelsPath) async {
    return const <OnnxTaggerLabel>[];
  }
}
