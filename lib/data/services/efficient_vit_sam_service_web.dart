import 'dart:typed_data';

import '../../core/utils/contiguous_region_selector.dart';
import 'efficient_vit_sam_service_types.dart';

export 'efficient_vit_sam_service_types.dart';

/// Web 版桩：浏览器编译图不包含本地 ONNX 运行时（onnxruntime_v2 / dart:ffi）。
///
/// 魔法棒选区在 Web 下不可用，[selectRgba] 统一抛出 [UnsupportedError]。
class EfficientVitSamService {
  Future<ContiguousRegionSelection> selectRgba({
    required Uint8List rgba,
    required int width,
    required int height,
    required int startX,
    required int startY,
    required bool invert,
    EfficientVitSamProgressCallback? onProgress,
  }) async {
    throw UnsupportedError('魔法棒选区在 Web 版暂不可用（需要本地 ONNX 运行时）');
  }

  void dispose() {}
}
