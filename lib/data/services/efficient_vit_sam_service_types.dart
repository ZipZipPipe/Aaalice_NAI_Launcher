/// EfficientViT-SAM 魔法棒的共享类型与进度回调（原生 / Web 共用）。
///
/// 推理实现见 `efficient_vit_sam_service_io.dart`；
/// Web 桩见 `efficient_vit_sam_service_web.dart`。
library;

import 'dart:typed_data';

import '../../core/utils/contiguous_region_selector.dart';

enum EfficientVitSamProgressStage {
  checkingModels,
  downloadingModels,
  loadingModels,
  encodingImage,
  decodingMask,
  postprocessingMask,
}

class EfficientVitSamProgress {
  const EfficientVitSamProgress(this.stage, {this.fraction});

  final EfficientVitSamProgressStage stage;
  final double? fraction;
}

typedef EfficientVitSamProgressCallback =
    void Function(EfficientVitSamProgress progress);
typedef EfficientVitSamSelector =
    Future<ContiguousRegionSelection> Function({
      required Uint8List rgba,
      required int width,
      required int height,
      required int startX,
      required int startY,
      required bool invert,
      EfficientVitSamProgressCallback? onProgress,
    });
