import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import 'jm_image_file_service.dart';

/// 禁漫图片缓存管理器
/// 使用自定义 FileService 提供完整的请求头和重试机制
class JmImageCacheManager
{
    static CacheManager? _instance;
    static String? _currentProxyUrl;
    static List<String> Function()? _imageDomainProvider;

    /// 重新初始化（代理配置变更或域名 provider 变更时调用）
    static void reset({
        String? proxyUrl,
        List<String> Function()? imageDomainProvider,
    })
    {
        _instance?.dispose();
        _instance = null;
        _currentProxyUrl = proxyUrl;
        _imageDomainProvider = imageDomainProvider;
    }

    /// 获取单例实例
    /// [proxyUrl] 可选；与上次不同则重建
    static CacheManager get instance
    {
        _instance ??= CacheManager(
            Config(
                'jmcomic_image_cache',
                stalePeriod: const Duration(days: 7),
                maxNrOfCacheObjects: 200,
                fileService: JmImageFileService(
                    proxyUrl: _currentProxyUrl,
                    imageDomainProvider: _imageDomainProvider,
                ),
            ),
        );
        return _instance!;
    }

    // 私有构造函数，防止实例化
    JmImageCacheManager._();

    // ===== 解密结果缓存（在线观看专用） =====

    static const String _decodedDirName = 'jm_decoded_cache';

    /// 缓存版本号。
    /// 修改解密算法/参数（如 aid 字段修正、filename 去后缀）时必须 +1，使旧版缓存自动失效。
    /// 旧版缓存因为是用错 aid/filename 解密的，留着会继续返回错位图，必须清掉。
    /// v1: 初始版本（aid 误用 albumId）
    /// v2: 修复 aid=photoId；旧 v1 缓存全部失效
    /// v3: 修复 filename 必须去后缀（'00001.webp' → '00001'）；旧 v2 缓存全部失效
    /// v4: 修正 getSegmentationNum 内部统一去后缀（与 Python 库对齐）；旧 v3 缓存全部失效
    /// v5: 新增 scramble_id <= 220980 → return 0（jm 服务端默认值 fallback）
    ///     旧 v4 缓存会错误缓存 num=14 解密结果，必须失效
    static const int _cacheVersion = 5;

    /// 缓存目录（惰性创建）
    static Future<Directory> _getDecodedDir() async
    {
        final base = await getTemporaryDirectory();
        final dir = Directory('${base.path}${Platform.pathSeparator}$_decodedDirName');
        if (!await dir.exists())
        {
            await dir.create(recursive: true);
        }
        return dir;
    }

    /// 生成缓存文件名（用 md5 避免特殊字符）
    /// 包含 [_cacheVersion]，确保算法变更后旧缓存不再命中
    static String _decodedFileName(String photoId, String filename)
    {
        final key = 'v$_cacheVersion|${photoId}_$filename';
        final hash = md5.convert(utf8.encode(key)).toString();
        return '$hash.jpg';
    }

    /// 读取缓存的解密结果
    /// 返回 null 表示未命中
    static Future<Uint8List?> getDecoded(String photoId, String filename) async
    {
        try
        {
            final dir = await _getDecodedDir();
            final file = File('${dir.path}${Platform.pathSeparator}${_decodedFileName(photoId, filename)}');
            if (await file.exists())
            {
                return await file.readAsBytes();
            }
        }
        catch (_)
        {
            // 读取失败视作未命中
        }
        return null;
    }

    /// 写入解密结果到缓存
    static Future<void> putDecoded(
        String photoId,
        String filename,
        Uint8List bytes,
    ) async
    {
        try
        {
            final dir = await _getDecodedDir();
            final file = File('${dir.path}${Platform.pathSeparator}${_decodedFileName(photoId, filename)}');
            await file.writeAsBytes(bytes, flush: true);
        }
        catch (_)
        {
            // 写入失败不影响主流程
        }
    }

    /// 清理解密缓存（设置页用）
    static Future<void> clearDecoded() async
    {
        try
        {
            final dir = await _getDecodedDir();
            if (await dir.exists())
            {
                await dir.delete(recursive: true);
            }
        }
        catch (_)
        {
            // 忽略
        }
    }
}
