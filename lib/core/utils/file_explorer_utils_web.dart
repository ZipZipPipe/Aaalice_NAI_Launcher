/// Web 版 [FileExplorerUtils]：浏览器无法唤起系统文件管理器。
///
/// 对应原生实现 `file_explorer_utils_io.dart`。字符串工具保留完整语义，
/// 文件定位操作统一抛出 [UnsupportedError]；上层入口应通过
/// `PlatformCapabilities.supportsOpenFolder` 在 Web 下隐藏。
typedef FileExplorerProcessLauncher =
    Future<void> Function(String executable, List<String> arguments);

class FileExplorerUtils {
  FileExplorerUtils._();

  static List<String> windowsRevealFileArguments(String filePath) {
    return ['/select,', filePath];
  }

  static String normalizeWindowsExplorerPath(String filePath) {
    final normalized = filePath.trim().replaceAll('/', r'\');
    if (normalized.startsWith(r'\\?\UNC\')) {
      return r'\\' + normalized.substring(r'\\?\UNC\'.length);
    }
    if (normalized.startsWith(r'\\?\')) {
      return normalized.substring(r'\\?\'.length);
    }
    return normalized;
  }

  static Future<void> openDirectory(
    String directoryPath, {
    FileExplorerProcessLauncher? startProcess,
  }) async {
    throw UnsupportedError('Web 版无法打开系统文件管理器：$directoryPath');
  }

  static Future<void> revealFile(
    String filePath, {
    FileExplorerProcessLauncher? startProcess,
  }) async {
    throw UnsupportedError('Web 版无法在系统文件管理器中定位文件：$filePath');
  }
}
