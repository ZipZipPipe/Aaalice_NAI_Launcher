/// 平台条件导出：原生构建使用 `file_explorer_utils_io.dart`（FFI/进程实现），
/// Web 构建使用 `file_explorer_utils_web.dart`（桩实现，文件定位操作抛出
/// [UnsupportedError]）。
library;

export 'file_explorer_utils_io.dart'
    if (dart.library.js_interop) 'file_explorer_utils_web.dart';
