// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:ledger_client/src/models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.code = 'network_error'});

  final String message;
  final String code;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({
    String baseUrl = const String.fromEnvironment('LEDGER_API_BASE'),
    http.Client? httpClient,
  }) : _baseUrl = baseUrl,
       _client = httpClient ?? http.Client();

  String _baseUrl;
  final http.Client _client;

  String get baseUrl => _baseUrl;

  void setBaseUrl(String baseUrl) {
    _baseUrl = normalizeServiceBaseUrl(baseUrl);
  }

  String get displayBaseUrl {
    if (_baseUrl.isNotEmpty) {
      return _baseUrl;
    }
    if (Uri.base.scheme != 'http' && Uri.base.scheme != 'https') {
      return '未设置';
    }
    final origin = Uri.base.origin;
    return origin == 'null' ? '同源服务' : origin;
  }

  String get displayHost {
    if (_baseUrl.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(_baseUrl);
    if (uri == null || uri.host.isEmpty) {
      return '';
    }
    if (uri.scheme == 'https') {
      return 'https://${uri.host}';
    }
    return uri.host;
  }

  String get displayPort {
    if (_baseUrl.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(_baseUrl);
    if (uri == null || uri.port == 0) {
      return '';
    }
    return uri.port.toString();
  }

  static String normalizeServiceBaseUrl(String raw) {
    final trimmed = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) {
      return '';
    }
    final withScheme =
        RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)
        ? trimmed
        : 'http://$trimmed';
    final parsed = Uri.tryParse(withScheme);
    if (parsed == null || parsed.host.isEmpty) {
      throw ApiException('服务地址格式不正确');
    }
    final host = parsed.host.contains(':') ? '[${parsed.host}]' : parsed.host;
    final port = parsed.hasPort ? ':${parsed.port}' : '';
    return '${parsed.scheme}://$host$port';
  }

  static String buildServiceBaseUrl({
    required String host,
    required String port,
  }) {
    final cleanHost = host.trim().replaceAll(RegExp(r'/+$'), '');
    final cleanPort = port.trim();
    if (cleanHost.isEmpty || cleanPort.isEmpty) {
      throw ApiException('请输入服务 IP 和端口');
    }
    final parsedPort = int.tryParse(cleanPort);
    if (parsedPort == null || parsedPort <= 0 || parsedPort > 65535) {
      throw ApiException('端口必须是 1 到 65535');
    }
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(cleanHost)) {
      final uri = Uri.parse(cleanHost);
      return normalizeServiceBaseUrl(
        uri
            .replace(port: parsedPort, path: '', query: '', fragment: '')
            .toString(),
      );
    }
    final inferredScheme = parsedPort == 443 ? 'https' : 'http';
    return normalizeServiceBaseUrl('$inferredScheme://$cleanHost:$parsedPort');
  }

  Uri _uri(String path, [Map<String, String?> query = const {}]) {
    final cleanQuery = <String, String>{};
    query.forEach((key, value) {
      if (value != null && value.isNotEmpty) {
        cleanQuery[key] = value;
      }
    });
    if (_baseUrl.isEmpty) {
      return Uri(
        path: path,
        queryParameters: cleanQuery.isEmpty ? null : cleanQuery,
      );
    }
    final base = Uri.parse(_baseUrl);
    return base.replace(
      path: path,
      queryParameters: cleanQuery.isEmpty ? null : cleanQuery,
    );
  }

  Map<String, String> _headers(String? token) {
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    String? token,
    Object? body,
    Map<String, String?> query = const {},
  }) async {
    final request = http.Request(method, _uri(path, query));
    request.headers.addAll(_headers(token));
    if (body != null) {
      request.body = jsonEncode(body);
    }
    http.StreamedResponse streamed;
    try {
      streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      throw ApiException('当前无网络，请联网后重试');
    }
    final text = await streamed.stream.bytesToString();
    final decoded = text.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(text) as Map<String, dynamic>;
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final error = decoded['error'] as Map<String, dynamic>?;
      throw ApiException(
        error?['message'] as String? ?? '请求失败',
        code: error?['code'] as String? ?? 'http_${streamed.statusCode}',
      );
    }
    return decoded;
  }

  Future<Map<String, dynamic>> pairStart({String? token}) {
    return _json('POST', '/api/pair/start', token: token);
  }

  Future<Map<String, dynamic>> pairConfirm({
    required String pairingCode,
    required String deviceName,
    required String platform,
  }) {
    return _json(
      'POST',
      '/api/pair/confirm',
      body: {
        'pairing_code': pairingCode,
        'device_name': deviceName,
        'platform': platform,
      },
    );
  }

  Future<BootstrapData> bootstrap(String token) async {
    final json = await _json('GET', '/api/bootstrap', token: token);
    return BootstrapData.fromJson(json);
  }

  Future<Device> updateCurrentDevice(String token, String name) async {
    final json = await _json(
      'PATCH',
      '/api/devices/current',
      token: token,
      body: {'name': name},
    );
    return Device.fromJson(json);
  }

  Future<List<AuditLogEntry>> listAuditLogs(
    String token, {
    int limit = 50,
  }) async {
    final json = await _json(
      'GET',
      '/api/admin/audit-logs',
      token: token,
      query: {'limit': limit.toString()},
    );
    return (json['items'] as List<dynamic>? ?? const [])
        .map((e) => AuditLogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Category> createCategory(
    String token,
    Map<String, dynamic> body,
  ) async {
    final json = await _json(
      'POST',
      '/api/categories',
      token: token,
      body: body,
    );
    return Category.fromJson(json);
  }

  Future<Category> patchCategory(
    String token,
    String id,
    Map<String, dynamic> body,
  ) async {
    final json = await _json(
      'PATCH',
      '/api/categories/$id',
      token: token,
      body: body,
    );
    return Category.fromJson(json);
  }

  Future<void> deleteCategory(String token, String id) async {
    await _json('DELETE', '/api/categories/$id', token: token);
  }

  Future<void> reorderCategories(
    String token, {
    required String type,
    required String? parentId,
    required List<String> orderedIds,
  }) async {
    await _json(
      'POST',
      '/api/categories/reorder',
      token: token,
      body: {'type': type, 'parent_id': parentId, 'ordered_ids': orderedIds},
    );
  }

  Future<Member> createMember(String token, Map<String, dynamic> body) async {
    final json = await _json('POST', '/api/members', token: token, body: body);
    return Member.fromJson(json);
  }

  Future<Member> patchMember(
    String token,
    String id,
    Map<String, dynamic> body,
  ) async {
    final json = await _json(
      'PATCH',
      '/api/members/$id',
      token: token,
      body: body,
    );
    return Member.fromJson(json);
  }

  Future<void> deleteMember(String token, String id) async {
    await _json('DELETE', '/api/members/$id', token: token);
  }

  Future<void> reorderMembers(String token, List<String> orderedIds) async {
    await _json(
      'POST',
      '/api/members/reorder',
      token: token,
      body: {'ordered_ids': orderedIds},
    );
  }

  Future<LedgerAccount> createAccount(
    String token,
    Map<String, dynamic> body,
  ) async {
    final json = await _json('POST', '/api/accounts', token: token, body: body);
    return LedgerAccount.fromJson(json);
  }

  Future<LedgerAccount> patchAccount(
    String token,
    String id,
    Map<String, dynamic> body,
  ) async {
    final json = await _json(
      'PATCH',
      '/api/accounts/$id',
      token: token,
      body: body,
    );
    return LedgerAccount.fromJson(json);
  }

  Future<void> deleteAccount(String token, String id) async {
    await _json('DELETE', '/api/accounts/$id', token: token);
  }

  Future<void> reorderAccounts(String token, List<String> orderedIds) async {
    await _json(
      'POST',
      '/api/accounts/reorder',
      token: token,
      body: {'ordered_ids': orderedIds},
    );
  }

  Future<TransactionPage> listTransactions(
    String token, {
    String? direction,
    String? categoryL1Id,
    String? memberId,
    String? accountId,
    String? keyword,
    int? from,
    int? to,
  }) async {
    final json = await _json(
      'GET',
      '/api/transactions',
      token: token,
      query: {
        'direction': direction,
        'category_l1_id': categoryL1Id,
        'member_id': memberId,
        'account_id': accountId,
        'keyword': keyword,
        'from': from?.toString(),
        'to': to?.toString(),
      },
    );
    return TransactionPage.fromJson(json);
  }

  Future<LedgerTransaction> createTransaction(
    String token,
    Map<String, dynamic> body,
  ) async {
    final json = await _json(
      'POST',
      '/api/transactions',
      token: token,
      body: body,
    );
    return LedgerTransaction.fromJson(json);
  }

  Future<LedgerTransaction> patchTransaction(
    String token,
    String id,
    Map<String, dynamic> body,
  ) async {
    final json = await _json(
      'PATCH',
      '/api/transactions/$id',
      token: token,
      body: body,
    );
    return LedgerTransaction.fromJson(json);
  }

  Future<void> deleteTransaction(String token, String id) async {
    await _json('DELETE', '/api/transactions/$id', token: token);
  }

  Future<void> deleteAttachment(String token, String id) async {
    await _json('DELETE', '/api/attachments/$id', token: token);
  }

  Future<List<AttachmentMeta>> listAttachments(
    String token,
    String transactionId,
  ) async {
    final json = await _json(
      'GET',
      '/api/transactions/$transactionId/attachments',
      token: token,
    );
    return (json['items'] as List<dynamic>? ?? const [])
        .map((e) => AttachmentMeta.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AttachmentMeta> uploadAttachment(
    String token, {
    required String transactionId,
    required List<int> bytes,
    required String fileName,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/api/attachments'));
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['transaction_id'] = transactionId;
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: fileName),
    );
    http.StreamedResponse streamed;
    try {
      streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 45));
    } catch (_) {
      throw ApiException('当前无网络，请联网后重试');
    }
    final text = await streamed.stream.bytesToString();
    final decoded = text.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(text) as Map<String, dynamic>;
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final error = decoded['error'] as Map<String, dynamic>?;
      throw ApiException(
        error?['message'] as String? ?? '上传失败',
        code: error?['code'] as String? ?? 'http_${streamed.statusCode}',
      );
    }
    return AttachmentMeta.fromJson(decoded);
  }

  Future<Uint8List> attachmentBytes(
    String token,
    String attachmentId, {
    bool thumbnail = false,
  }) async {
    final path = thumbnail
        ? '/api/attachments/$attachmentId/thumbnail'
        : '/api/attachments/$attachmentId';
    http.Response response;
    try {
      response = await _client
          .get(_uri(path), headers: _headers(token))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw ApiException('当前无网络，请联网后重试');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('图片读取失败', code: 'http_${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Future<LedgerTransaction> importSms(
    String token,
    Map<String, dynamic> body,
  ) async {
    final json = await _json(
      'POST',
      '/api/sms/imports',
      token: token,
      body: body,
    );
    return LedgerTransaction.fromJson(
      json['transaction'] as Map<String, dynamic>,
    );
  }

  Future<List<CategorySuggestion>> suggestCategories(
    String token,
    List<Map<String, dynamic>> items,
  ) async {
    final json = await _json(
      'POST',
      '/api/category-suggestions',
      token: token,
      body: {'items': items},
    );
    return (json['items'] as List<dynamic>? ?? const [])
        .map((e) => CategorySuggestion.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<CategoryStat>> categoryStats(
    String token, {
    String direction = 'expense',
    String? compareBy,
    String level = 'l1',
    String? memberId,
    String? categoryL1Id,
    String? categoryL2Id,
    String? accountId,
    String? bankName,
    int? from,
    int? to,
  }) async {
    final json = await _json(
      'GET',
      '/api/stats/category',
      token: token,
      query: {
        'direction': direction,
        'compare_by': compareBy,
        'level': level,
        'member_id': memberId,
        'category_l1_id': categoryL1Id,
        'category_l2_id': categoryL2Id,
        'account_id': accountId,
        'bank_name': bankName,
        'from': from?.toString(),
        'to': to?.toString(),
      },
    );
    return (json['items'] as List<dynamic>? ?? const [])
        .map((e) => CategoryStat.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TimelineStats> timelineStats(
    String token, {
    String direction = 'expense',
    String? compareBy,
    String bucket = 'day',
    String? memberId,
    String? categoryL1Id,
    String? categoryL2Id,
    String? accountId,
    String? bankName,
    int? from,
    int? to,
  }) async {
    final json = await _json(
      'GET',
      '/api/stats/timeline',
      token: token,
      query: {
        'direction': direction,
        'compare_by': compareBy,
        'bucket': bucket,
        'member_id': memberId,
        'category_l1_id': categoryL1Id,
        'category_l2_id': categoryL2Id,
        'account_id': accountId,
        'bank_name': bankName,
        'from': from?.toString(),
        'to': to?.toString(),
      },
    );
    return TimelineStats.fromJson(json);
  }
}
