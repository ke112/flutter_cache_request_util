import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_request_util/api_response.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 缓存请求工具类
/// 支持"先缓存后网络"的请求模式，提供统一的缓存管理
class CacheRequestUtil {
  static const String _logTag = 'CacheRequestUtil';
  static const String _cacheDirName = 'cache_request_data';

  /// 缓存请求方法
  ///
  /// [cacheKey] 缓存键
  /// [cacheKeyBindUserId] 缓存键是否绑定用户ID，默认false
  /// [apiCall] API调用函数
  /// [fromJson] 从JSON数据解析对象的函数
  /// [onSuccess] 成功回调，参数为(数据, 是否来自缓存)
  /// [onError] 错误回调，仅当缓存和网络都失败时触发
  /// [cacheDuration] 缓存时长，默认为null表示永久有效，设置具体时间才检查有效期
  static Future<void> request<T>({
    required String cacheKey,
    bool cacheKeyBindUserId = false,
    Future<ApiResponse> Function()? apiCall,
    required T Function(Map<String, dynamic>) fromJson,
    void Function(T data, bool isFromCache)? onSuccess,
    void Function(String error)? onError,
    Duration? cacheDuration,
  }) async {
    /// 缓存的数据（用于比较和判断是否有缓存）
    dynamic cachedJsonData;

    /// 生成最终缓存键
    final String finalCacheKey = await _getFinalCacheKey(cacheKey, cacheKeyBindUserId);

    /// 第一步：尝试加载缓存
    final cachedData = await _loadFromCache<T>(finalCacheKey, fromJson, cacheDuration);
    if (cachedData != null) {
      // 保存缓存的原始JSON数据用于比较
      cachedJsonData = await _getCachedJsonData(finalCacheKey);
      onSuccess?.call(cachedData, true);
    }

    /// 第二步：发起网络请求（如果提供了apiCall）
    if (apiCall != null) {
      try {
        final response = await apiCall();
        if (response.isSucceed) {
          final data = fromJson(response.content as Map<String, dynamic>);
          await _saveToCache(finalCacheKey, response.content);

          // 如果缓存存在且数据相同，跳过网络回调
          if (cachedJsonData != null && _isDataEqual(cachedJsonData, response.content)) {
            // 数据相同，不触发重复回调
            return;
          }

          onSuccess?.call(data, false);
        } else {
          // 网络请求失败，如果没有缓存数据则触发错误回调
          if (cachedJsonData == null && onError != null) {
            onError(response.message ?? 'request failed');
          }
        }
      } catch (e) {
        // 网络异常，如果没有缓存数据则触发错误回调
        if (cachedJsonData == null && onError != null) {
          onError(e.toString());
        }
      }
    } else {
      // 如果没有提供apiCall且没有缓存数据，触发错误回调
      if (cachedJsonData == null && onError != null) {
        onError('cache not exists or expired');
      }
    }
  }

  /// 从缓存加载数据
  /// [cacheKey] 缓存键
  /// [fromJson] JSON解析函数
  /// [cacheDuration] 缓存有效期，为null时表示永久有效
  static Future<T?> _loadFromCache<T>(
    String cacheKey,
    T Function(Map<String, dynamic>) fromJson,
    Duration? cacheDuration,
  ) async {
    try {
      final String filePath = await _getCacheFilePath(cacheKey);
      final File cacheFile = File(filePath);

      if (!await cacheFile.exists()) {
        ALog.d(_logTag, 'cache not exists: $cacheKey');
        return null;
      }

      final String cachedString = await cacheFile.readAsString();
      if (cachedString.isEmpty) {
        ALog.d(_logTag, 'cache file empty: $cacheKey');
        return null;
      }

      final Map<String, dynamic> cachedData = jsonDecode(cachedString);

      // 检查缓存是否过期（仅当设置了cacheDuration时才检查）
      if (cacheDuration != null) {
        final int? timestamp = cachedData['timestamp'];
        if (timestamp != null) {
          final DateTime cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
          final Duration age = DateTime.now().difference(cacheTime);
          if (age > cacheDuration) {
            ALog.d(_logTag, 'cache expired: $cacheKey, expired time: ${age.inMinutes} minutes');
            await _clearCache(cacheKey);
            return null;
          }
        }
      }

      // 解析缓存数据（缓存统一存储JSON格式）
      final dynamic content = cachedData['content'];
      if (content != null && content is Map<String, dynamic>) {
        return fromJson(content);
      }

      return null;
    } catch (e) {
      ALog.d(_logTag, 'cache parse failed: $cacheKey, error: ${e.toString()}');
      // 缓存数据损坏，清除缓存
      await _clearCache(cacheKey);
      return null;
    }
  }

  /// 保存数据到缓存
  ///
  /// [cacheKey] 缓存键
  /// [content] 要缓存的内容（通常是API响应的content字段）
  static Future<void> _saveToCache(String cacheKey, dynamic content) async {
    try {
      final Map<String, dynamic> cacheData = {'timestamp': DateTime.now().millisecondsSinceEpoch, 'content': content};

      final String jsonString = jsonEncode(cacheData);
      final String filePath = await _getCacheFilePath(cacheKey);
      final File cacheFile = File(filePath);
      await cacheFile.writeAsString(jsonString);
      ALog.d(_logTag, 'cache saved: $cacheKey');
    } catch (e) {
      ALog.d(_logTag, 'cache save failed: $cacheKey, error: ${e.toString()}');
    }
  }

  /// 清除指定缓存
  ///
  /// [cacheKey] 要清除的缓存键
  static Future<void> _clearCache(String cacheKey) async {
    try {
      final String filePath = await _getCacheFilePath(cacheKey);
      final File cacheFile = File(filePath);
      if (await cacheFile.exists()) {
        await cacheFile.delete();
        ALog.d(_logTag, 'cache cleared: $cacheKey');
      }
    } catch (e) {
      ALog.d(_logTag, 'cache clear failed: $cacheKey, error: ${e.toString()}');
    }
  }

  /// 手动移除缓存
  static Future<void> removeCache(String cacheKey, {bool isUserIdCache = false}) async {
    final String finalCacheKey = await _getFinalCacheKey(cacheKey, isUserIdCache);
    await _clearCache(finalCacheKey);
  }

  /// 获取缓存的原始JSON数据
  /// [cacheKey] 缓存键
  static Future<dynamic> _getCachedJsonData(String cacheKey) async {
    try {
      final String filePath = await _getCacheFilePath(cacheKey);
      final File cacheFile = File(filePath);
      if (!await cacheFile.exists()) {
        return null;
      }

      final String cachedString = await cacheFile.readAsString();
      if (cachedString.isEmpty) {
        return null;
      }

      final Map<String, dynamic> cachedData = jsonDecode(cachedString);
      return cachedData['content'];
    } catch (e) {
      return null;
    }
  }

  /// 比较两个数据是否相同
  /// [data1] 第一个数据
  /// [data2] 第二个数据
  static bool _isDataEqual(dynamic data1, dynamic data2) {
    if (data1 == null && data2 == null) return true;
    if (data1 == null || data2 == null) return false;

    try {
      // 将数据序列化为JSON字符串进行比较
      final String json1 = jsonEncode(data1);
      final String json2 = jsonEncode(data2);
      return json1 == json2;
    } catch (e) {
      // 如果序列化失败，认为是不同的
      return false;
    }
  }

  /// 生成最终的缓存键
  /// [cacheKey] 基础缓存键
  /// [cacheKeyBindUserId] 缓存键是否绑定用户ID，默认false
  static Future<String> _getFinalCacheKey(String cacheKey, bool cacheKeyBindUserId) async {
    if (cacheKeyBindUserId) {
      // 替换为你的AccountService实现
      bool isLoggedIn = Random().nextBool();
      String userSuid = '1234567890';
      if (!isLoggedIn) {
        throw Exception('user not logged in');
      }
      return '${userSuid}_$cacheKey';
    } else {
      return cacheKey;
    }
  }

  /// 获取应用缓存目录路径
  static Future<Directory> _getCacheDirectory() async {
    final appDocDir = await getApplicationCacheDirectory();
    final cacheDir = Directory(path.join(appDocDir.path, _cacheDirName));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// 根据缓存键获取文件路径
  static Future<String> _getCacheFilePath(String cacheKey) async {
    final cacheDir = await _getCacheDirectory();
    // 使用MD5哈希生成固定长度的文件名，避免文件名非法字符问题
    final safeKey = md5.convert(utf8.encode(cacheKey)).toString();
    String filePath = path.join(cacheDir.path, '$safeKey.json');
    return filePath;
  }
}

class ALog {
  static void d(String tag, String message) {
    if (kDebugMode) {
      debugPrint('$tag: $message');
    }
  }
}
