import 'dart:convert';

class ApiResponse<T> {
  final String? message;

  ///因为msg不支持变量 所以有变量提示的写到了err_msg
  final String? errMsg;

  final int code;

  T? content;

  // 核心构造函数
  ApiResponse(this.code, this.message, this.content, this.errMsg);

  // 判断请求是否成功
  bool get isSucceed => code == 0 || code == 200;

  // 空实例工厂方法
  factory ApiResponse.empty() => ApiResponse(0, null, null, null);

  // 手动实现JSON反序列化（替代代码生成的_$ApiResponseFromJson）
  factory ApiResponse.fromJson(Map<String, dynamic> json, T Function(dynamic json) fromJsonT) {
    // 保留原有核心逻辑：非成功状态时将data置为null
    // 先复制JSON对象，避免修改原始数据
    final processedJson = Map<String, dynamic>.from(json);
    if (processedJson['code'] != 200 && processedJson['code'] != 0) {
      processedJson['data'] = null;
    }

    // 手动映射JSON字段（对应原@JsonKey的name映射规则）
    final int code = processedJson['code'] as int? ?? 0; // 保留defaultValue: 0的逻辑
    final String? message = processedJson['message'] as String?;
    final String? errMsg = processedJson['err_msg'] as String?;
    final dynamic data = processedJson['data'];
    final T? content = data != null ? fromJsonT(data) : null;

    return ApiResponse<T>(code, message, content, errMsg);
  }

  // 手动实现JSON序列化（替代代码生成的_$ApiResponseToJson）
  Map<String, dynamic> toJson(Object? Function(T value) toJsonT) {
    final Map<String, dynamic> json = {};

    // 反向映射类属性到JSON字段
    if (message != null) json['message'] = message;
    if (errMsg != null) json['err_msg'] = errMsg;
    json['code'] = code;
    if (content != null) {
      json['data'] = toJsonT(content!);
    } else {
      json['data'] = null;
    }

    return json;
  }

  // 【可选】便捷方法：直接从JSON字符串解析
  factory ApiResponse.fromJsonString(String jsonString, T Function(dynamic json) fromJsonT) {
    final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
    return ApiResponse.fromJson(jsonMap, fromJsonT);
  }

  // 【可选】便捷方法：直接转为JSON字符串
  String toJsonString(Object? Function(T value) toJsonT) {
    return jsonEncode(toJson(toJsonT));
  }
}
