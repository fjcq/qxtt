import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import 'jm_config.dart';

/// 禁漫加解密工具
class JmCrypto
{
    /// 计算 token 和 tokenparam
    /// token = md5("{ts}{secret}")
    /// tokenparam = "{ts},{ver}"
    static ({String token, String tokenparam}) generateToken(
        int ts,
        String ver,
        String secret,
    )
    {
        final tokenparam = '$ts,$ver';
        final token = md5.convert(utf8.encode('$ts$secret')).toString();
        return (token: token, tokenparam: tokenparam);
    }

    /// 生成默认请求 token（使用 appTokenSecret）
    static ({String token, String tokenparam}) generateDefaultToken(int ts)
    {
        return generateToken(ts, JmConfig.appVersion, JmConfig.appTokenSecret);
    }

    /// 生成章节视图 token（使用 appTokenSecret2）
    static ({String token, String tokenparam}) generateChapterViewToken(int ts)
    {
        return generateToken(ts, JmConfig.appVersion, JmConfig.appTokenSecret2);
    }

    /// 解密 API 返回值
    /// 步骤:
    /// 1. base64 解码 data
    /// 2. AES-ECB 解密，key = md5hex("{ts}{secret}").encode('utf-8') (32字节)
    /// 3. 移除 PKCS7 padding
    /// 4. UTF-8 解码为 JSON 字符串
    static String decodeRespData(String data, dynamic ts, String secret)
    {
        // 1. base64 解码
        final dataBytes = base64.decode(data);

        // 2. AES-ECB 解密
        // 注意: key 是 md5hex 的十六进制字符串的 UTF-8 编码，不是原始摘要字节
        final md5hex = md5.convert(utf8.encode('$ts$secret')).toString();
        final key = Uint8List.fromList(utf8.encode(md5hex));

        final cipher = ECBBlockCipher(AESEngine())
            ..init(false, KeyParameter(key));

        // 分块解密（每块 16 字节）
        final output = Uint8List(dataBytes.length);
        var offset = 0;
        while (offset < dataBytes.length)
        {
            offset += cipher.processBlock(dataBytes, offset, output, offset);
        }

        // 3. 移除 PKCS7 padding
        final paddingLen = output.last;
        final unpadded = output.sublist(0, output.length - paddingLen);

        // 4. UTF-8 解码
        return utf8.decode(unpadded);
    }

    /// 使用默认密钥解密响应
    static String decodeDefaultRespData(String data, int ts)
    {
        return decodeRespData(data, ts, JmConfig.appDataSecret);
    }

    /// 使用域名服务器密钥解密
    /// 注意: ts 为空字符串，不是 0
    static String decodeDomainServerData(String data)
    {
        return decodeRespData(data, '', JmConfig.apiDomainServerSecret);
    }

    // 私有构造函数，防止实例化
    JmCrypto._();
}
