/// 平台条件导出：原生构建使用 `windows_proxy_helper_io.dart`（注册表实现），
/// Web 构建使用 `windows_proxy_helper_web.dart`（桩实现）。
library;

export 'windows_proxy_helper_io.dart'
    if (dart.library.js_interop) 'windows_proxy_helper_web.dart';
