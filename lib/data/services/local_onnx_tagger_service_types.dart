/// 本地 ONNX 打标器的共享值对象与会话加载模式（原生 / Web 共用）。
///
/// 推理实现见 `local_onnx_tagger_service_io.dart`；
/// Web 桩见 `local_onnx_tagger_service_web.dart`。
library;

import 'local_onnx_model_service.dart';

enum OnnxTaggerLabelCategory { rating, general, character, other }

class OnnxTaggerLabel {
  const OnnxTaggerLabel({required this.name, this.category});

  final String name;
  final String? category;

  OnnxTaggerLabelCategory get labelCategory {
    final normalizedCategory = category?.trim().toLowerCase();
    if (normalizedCategory == '9' ||
        normalizedCategory == 'rating' ||
        name.startsWith('rating:')) {
      return OnnxTaggerLabelCategory.rating;
    }
    if (normalizedCategory == '0' ||
        normalizedCategory == 'general' ||
        normalizedCategory == 'tag' ||
        normalizedCategory == 'tags') {
      return OnnxTaggerLabelCategory.general;
    }
    if (normalizedCategory == '4' ||
        normalizedCategory == 'character' ||
        normalizedCategory == 'characters') {
      return OnnxTaggerLabelCategory.character;
    }
    return OnnxTaggerLabelCategory.other;
  }

  bool get isRating {
    return labelCategory == OnnxTaggerLabelCategory.rating;
  }

  bool get isGeneral => labelCategory == OnnxTaggerLabelCategory.general;

  bool get isCharacter => labelCategory == OnnxTaggerLabelCategory.character;
}

class OnnxTaggerTag {
  const OnnxTaggerTag({required this.name, required this.score, this.category});

  final String name;
  final double score;
  final String? category;
}

class OnnxTaggerResult {
  const OnnxTaggerResult({required this.model, required this.tags});

  final LocalOnnxModelDescriptor model;
  final List<OnnxTaggerTag> tags;

  String get prompt => tags.map((tag) => tag.name).join(', ');
}

enum OnnxSessionLoadMode { externalDataFile, patchedSingleFile }
