/// Web 版桩：浏览器环境没有 Windows 注册表。
///
/// 对应原生实现 `app_installation_registry_io.dart`；始终返回 `null`，
/// 让调用方落回“非安装版/不支持”的判定路径。
String? readWindowsInstallLocationFromRegistry(String registryPath) => null;
