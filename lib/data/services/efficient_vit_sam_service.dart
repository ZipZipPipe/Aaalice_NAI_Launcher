/// 平台条件导出：原生构建使用 `efficient_vit_sam_service_io.dart`
/// （onnxruntime_v2 FFI 实现），Web 构建使用
/// `efficient_vit_sam_service_web.dart`（桩实现）。
library;

export 'efficient_vit_sam_service_io.dart'
    if (dart.library.js_interop) 'efficient_vit_sam_service_web.dart';
