import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'jm_config.dart';
import 'jm_crypto.dart';
import 'jm_domain_persistence.dart';
import 'jm_entity.dart';

part 'jm_domain_cache.dart';
part 'jm_client_core.dart';
part 'jm_api_client.dart';
part 'jm_image_downloader.dart';

/// 内部统一日志（输出到 IDE 控制台/Flutter DevTools，不污染业务日志）
void _log(String tag, String message)
{
    // 使用 dart:developer.log，可在 DevTools 中按 tag 过滤
    developer.log(message, name: 'jmcomic.$tag');
}

/// 禁漫 API 客户端
///
/// 由三个内部类分层实现：
///   - [_JmClientCore]：Dio、域名管理、通用工具
///   - [_JmApiClient]：业务 API（搜索/详情/登录等）
///   - [_JmImageDownloader]：图片下载与文件续传
class JmClient extends _JmImageDownloader
{
    JmClient({super.proxyUrl, super.useProxy = false});
}
