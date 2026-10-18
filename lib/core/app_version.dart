/// 应用版本信息
///
/// 通过 [String.fromEnvironment] 在构建时注入，避免引入 `package_info_plus` 插件
/// （该插件仍使用 Kotlin Gradle Plugin，会触发 Flutter 的 Built-in Kotlin 迁移警告）。
///
/// 构建命令示例：
/// ```bash
/// flutter build apk --dart-define=APP_VERSION=1.0.2 --dart-define=APP_BUILD=3
/// ```
/// 未传 --dart-define 时回退到 pubspec.yaml 中声明的默认版本。
class AppVersion {
    /// 显示版本号（如 "1.0.8+13"），构建时通过 --dart-define 覆盖
    static const String label = String.fromEnvironment(
        'APP_VERSION_LABEL',
        defaultValue: '1.0.8+13',
    );

    /// 纯版本名（如 "1.0.8"）
    static const String version = String.fromEnvironment(
        'APP_VERSION',
        defaultValue: '1.0.8',
    );

    /// 构建号（如 "13"）
    static const String build = String.fromEnvironment(
        'APP_BUILD',
        defaultValue: '13',
    );

    /// 完整显示文本（version+build），如 "1.0.1+2"
    static String get displayLabel {
        if (build.isEmpty) return version;
        return '$version+$build';
    }
}
