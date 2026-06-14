import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ledger_client/src/models.dart';

class SmsTemplate {
  SmsTemplate({
    required this.id,
    required this.sender,
    required this.accountId,
    required this.pattern,
    required this.slots,
    required this.enabled,
    required this.sampleCount,
    required this.updatedAt,
  });

  final String id;
  final String sender;
  final String accountId;
  final String pattern;
  final List<String> slots;
  final bool enabled;
  final int sampleCount;
  final int updatedAt;

  SmsTemplate copyWith({bool? enabled, int? sampleCount, int? updatedAt}) {
    return SmsTemplate(
      id: id,
      sender: sender,
      accountId: accountId,
      pattern: pattern,
      slots: slots,
      enabled: enabled ?? this.enabled,
      sampleCount: sampleCount ?? this.sampleCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sender': sender,
    'account_id': accountId,
    'pattern': pattern,
    'slots': slots,
    'enabled': enabled,
    'sample_count': sampleCount,
    'updated_at': updatedAt,
  };

  factory SmsTemplate.fromJson(Map<String, dynamic> json) {
    return SmsTemplate(
      id: json['id'] as String,
      sender: json['sender'] as String,
      accountId: json['account_id'] as String,
      pattern: json['pattern'] as String,
      slots: (json['slots'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      enabled: json['enabled'] as bool? ?? false,
      sampleCount: json['sample_count'] as int? ?? 0,
      updatedAt: json['updated_at'] as int? ?? 0,
    );
  }
}

class SmsTemplateMatch {
  SmsTemplateMatch({required this.template, required this.values});

  final SmsTemplate template;
  final Map<String, String> values;
}

const smsTemplateSlotWords = <String>[
  'amount',
  'balance',
  'date_time',
  'merchant',
  'counterparty',
  'card_tail',
  'bank',
  'direction',
];

class SmsTemplateStore {
  SmsTemplateStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'sms_templates_v1';
  final FlutterSecureStorage _storage;

  Future<List<SmsTemplate>> load() async {
    final text = await _storage.read(key: _key);
    if (text == null || text.trim().isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(text);
    if (decoded is! List) {
      return const [];
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(SmsTemplate.fromJson)
        .toList();
  }

  Future<void> save(List<SmsTemplate> templates) {
    return _storage.write(
      key: _key,
      value: jsonEncode(templates.map((item) => item.toJson()).toList()),
    );
  }
}

class SmsImportedHashStore {
  SmsImportedHashStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'sms_imported_hashes_v1';
  static const _maxHashes = 2000;
  final FlutterSecureStorage _storage;

  Future<Set<String>> load() async {
    final text = await _storage.read(key: _key);
    if (text == null || text.trim().isEmpty) {
      return <String>{};
    }
    final decoded = jsonDecode(text);
    if (decoded is! List) {
      return <String>{};
    }
    return decoded
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet();
  }

  Future<void> addAll(Iterable<String> hashes) async {
    final merged = await load();
    merged.addAll(
      hashes.map((item) => item.trim()).where((item) => item.isNotEmpty),
    );
    final values = merged.toList();
    final trimmed = values.length <= _maxHashes
        ? values
        : values.sublist(values.length - _maxHashes);
    await _storage.write(key: _key, value: jsonEncode(trimmed));
  }

  Future<void> clear() {
    return _storage.write(key: _key, value: jsonEncode(const <String>[]));
  }
}

String encodeSmsTemplates(List<SmsTemplate> templates) {
  return jsonEncode(templates.map((item) => item.toJson()).toList());
}

String normalizeSmsSender(String raw) {
  var value = raw.trim().replaceAll(RegExp(r'[\s-]+'), '');
  if (value.startsWith('+86')) {
    value = value.substring(3);
  } else if (value.startsWith('0086')) {
    value = value.substring(4);
  }
  return value;
}

String normalizeSmsBody(String raw) {
  return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String? validateManualSmsTemplatePattern(String pattern) {
  final normalized = normalizeSmsBody(pattern);
  if (normalized.isEmpty) {
    return '请输入模板内容';
  }
  if (_hasInvalidTemplateBraces(normalized)) {
    return '模板字段必须写成 {amount} 这样的格式';
  }
  final slots = _slotsInPattern(normalized);
  if (slots.isEmpty) {
    return '模板至少需要一个大括号字段';
  }
  if (!slots.contains('amount')) {
    return '模板必须包含 {amount} 才能生成交易金额';
  }
  final unsupported = slots
      .where((slot) => !smsTemplateSlotWords.contains(slot))
      .toList();
  if (unsupported.isNotEmpty) {
    return '不支持的模板字段：${unsupported.join(', ')}';
  }
  return null;
}

SmsTemplate createManualSmsTemplate({
  required LedgerAccount account,
  required String sender,
  required String pattern,
  SmsTemplate? prior,
  bool enabled = true,
}) {
  final normalizedSender = normalizeSmsSender(sender);
  final normalizedPattern = normalizeSmsBody(pattern);
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return SmsTemplate(
    id: _templateId(normalizedSender, account.id, normalizedPattern),
    sender: normalizedSender,
    accountId: account.id,
    pattern: normalizedPattern,
    slots: _slotsInPattern(normalizedPattern),
    enabled: prior?.enabled ?? enabled,
    sampleCount: 0,
    updatedAt: now,
  );
}

List<SmsTemplate> learnSmsTemplatesFromRows(
  List<dynamic> rows, {
  required LedgerAccount account,
  required String sender,
  required DateTime fromDate,
  required DateTime toDate,
  List<SmsTemplate> existing = const [],
}) {
  final normalizedSender = normalizeSmsSender(sender);
  final grouped = <String, int>{};
  final fromMillis = DateTime(
    fromDate.year,
    fromDate.month,
    fromDate.day,
  ).millisecondsSinceEpoch;
  final toMillis = DateTime(
    toDate.year,
    toDate.month,
    toDate.day,
    23,
    59,
    59,
  ).millisecondsSinceEpoch;

  for (final row in rows) {
    if (row is! Map) {
      continue;
    }
    final rowSender = normalizeSmsSender(row['sender']?.toString() ?? '');
    if (rowSender != normalizedSender) {
      continue;
    }
    final dateMillis = (row['dateMillis'] as num?)?.toInt() ?? 0;
    if (dateMillis < fromMillis || dateMillis > toMillis) {
      continue;
    }
    final body = row['body']?.toString() ?? '';
    if (!_bodyMatchesAccount(body, account)) {
      continue;
    }
    final pattern = smsTemplatePattern(body);
    if (!_hasMinimumTemplateSlots(pattern)) {
      continue;
    }
    grouped[pattern] = (grouped[pattern] ?? 0) + 1;
  }

  final existingById = {for (final template in existing) template.id: template};
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final entries = grouped.entries.toList()
    ..sort((a, b) {
      final count = b.value.compareTo(a.value);
      return count != 0 ? count : a.key.compareTo(b.key);
    });
  return entries.map((entry) {
    final id = _templateId(normalizedSender, account.id, entry.key);
    final prior = existingById[id];
    return SmsTemplate(
      id: id,
      sender: normalizedSender,
      accountId: account.id,
      pattern: entry.key,
      slots: _slotsInPattern(entry.key),
      enabled: prior?.enabled ?? false,
      sampleCount: entry.value,
      updatedAt: now,
    );
  }).toList();
}

List<SmsTemplate> replaceSmsTemplatesForScope(
  List<SmsTemplate> all,
  List<SmsTemplate> learned, {
  required String sender,
  required String accountId,
}) {
  final normalizedSender = normalizeSmsSender(sender);
  return [
    ...all.where(
      (item) => item.sender != normalizedSender || item.accountId != accountId,
    ),
    ...learned,
  ];
}

SmsTemplate? matchEnabledSmsTemplate({
  required String body,
  required String sender,
  required List<SmsTemplate> templates,
}) {
  return matchEnabledSmsTemplateWithValues(
    body: body,
    sender: sender,
    templates: templates,
  )?.template;
}

SmsTemplateMatch? matchEnabledSmsTemplateWithValues({
  required String body,
  required String sender,
  required List<SmsTemplate> templates,
}) {
  final normalizedSender = normalizeSmsSender(sender);
  final normalizedBody = normalizeSmsBody(body);
  for (final template in templates) {
    if (!template.enabled) {
      continue;
    }
    if (template.sender != normalizedSender) {
      continue;
    }
    final values = _extractTemplateValues(normalizedBody, template.pattern);
    if (values != null) {
      return SmsTemplateMatch(template: template, values: values);
    }
  }
  return null;
}

String smsTemplatePattern(String body) {
  var value = normalizeSmsBody(body);
  value = value.replaceFirst(RegExp(r'^【[^您】]*银行[^您】]*(?:】)?(?=您)'), '{bank}');
  value = value.replaceAll(RegExp(r'【[^】]*银行[^】]*】'), '{bank}');
  value = value.replaceAll(RegExp(r'尾号\s*\d{3,4}'), '尾号{card_tail}');
  value = value.replaceAll(RegExp(r'尾数\s*\d{3,4}'), '尾数{card_tail}');
  value = value.replaceAll(RegExp(r'卡尾号\s*\d{3,4}'), '卡尾号{card_tail}');
  value = value.replaceAll(RegExp(r'银行卡尾号\s*\d{3,4}'), '银行卡尾号{card_tail}');
  value = value.replaceAll(RegExp(r'付款卡尾号\s*\d{3,4}'), '付款卡尾号{card_tail}');
  value = value.replaceAll(
    RegExp(r'\d{4}年\d{1,2}月\d{1,2}日\s*\d{1,2}[:：]\d{2}'),
    '{date_time}',
  );
  value = value.replaceAll(
    RegExp(r'\d{4}[-/]\d{1,2}[-/]\d{1,2}\s*\d{1,2}[:：]\d{2}'),
    '{date_time}',
  );
  value = value.replaceAll(
    RegExp(r'\d{1,2}月\d{1,2}日\s*\d{1,2}[:：]\d{2}'),
    '{date_time}',
  );
  value = value.replaceAll(RegExp(r'\d{1,2}月\d{1,2}日'), '{date_time}');
  value = value.replaceAllMapped(
    RegExp(
      r'((?:账户|当前|可用)?余额\s*(?:为|：|:)?)\s*(?:人民币|RMB|CNY|￥|¥)?\s*\d[\d,]*(?:\.\d{1,2})?\s*元?',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}{balance}',
  );
  value = value.replaceAllMapped(
    RegExp(r'(交易商户|交易地点|交易摘要|付款方|收款方|对方户名|交易对象)[:：]\s*[^,，。；;]+'),
    (match) => '${match.group(1)}：{merchant}',
  );
  value = value.replaceAll(RegExp(r'交易类型为[^,，。；;]+'), '交易类型为{direction}');
  value = value.replaceAll(RegExp(r'收到转入|发起转出'), '{direction}');
  value = value.replaceAll(
    RegExp(r'(收入|支出)[（(][^）)]*[）)]'),
    '{direction}({merchant})',
  );
  value = value.replaceAll(
    RegExp(r'通过.+?(消费|支出|出账|扣款|付款|支付)'),
    '通过{merchant}{direction}',
  );
  value = value.replaceAll(
    RegExp(r'，(?![^，。；;]*尾号)[^，。；;]+?(?:代扣)?(出账|支出|消费|扣款|付款|支付)'),
    '，{merchant}{direction}',
  );
  value = value.replaceAllMapped(
    RegExp(
      r'((?:人民币|RMB|CNY|￥|¥)\s*)[+-]?\d[\d,]*(?:\.\d{1,2})?(\s*元?)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}{amount}${match.group(2)}',
  );
  value = value.replaceAll(
    RegExp(r'[+-]?\d[\d,]*(?:\.\d{1,2})?\s*元'),
    '{amount}元',
  );
  value = value.replaceAll(
    RegExp(r'收入|支出|出账|入账|到账|转入|转出|消费|退款|扣款|付款|支付|代扣'),
    '{direction}',
  );
  return value.replaceAll(RegExp(r'\s+'), '');
}

int? extractSmsAmountCent(String body) {
  final yuanPattern = RegExp(r'([+-]?\d[\d,]*(?:\.\d{1,2})?)\s*元');
  for (final match in yuanPattern.allMatches(body)) {
    final prefixStart = match.start - 18 < 0 ? 0 : match.start - 18;
    final prefix = body.substring(prefixStart, match.start);
    if (RegExp(r'余额|剩余|可用|可用余额').hasMatch(prefix)) {
      continue;
    }
    final parsed = parseAmountCent(
      match.group(1)!.replaceAll(',', '').replaceAll(RegExp(r'^[+-]'), ''),
    );
    if (parsed != null) {
      return parsed;
    }
  }
  final currencyMatch = RegExp(
    r'(?:RMB|CNY|￥|¥)\s*(\d[\d,]*(?:\.\d{1,2})?)',
    caseSensitive: false,
  ).firstMatch(body);
  return currencyMatch == null
      ? null
      : parseAmountCent(currencyMatch.group(1)!.replaceAll(',', ''));
}

int? parseSmsMoneyCent(String raw) {
  final normalized = raw.replaceAll('，', ',');
  final match = RegExp(r'[+-]?\d[\d,]*(?:\.\d{1,2})?').firstMatch(normalized);
  if (match == null) {
    return null;
  }
  return parseAmountCent(
    match.group(0)!.replaceAll(',', '').replaceAll(RegExp(r'^[+-]'), ''),
  );
}

int? extractSmsBalanceCent(String body) {
  final match = RegExp(
    r'(?:账户|当前|可用)?余额\s*(?:为|：|:)?\s*(?:人民币|RMB|CNY|￥|¥)?\s*(\d[\d,]*(?:\.\d{1,2})?)\s*元?',
    caseSensitive: false,
  ).firstMatch(body);
  return match == null
      ? null
      : parseAmountCent(match.group(1)!.replaceAll(',', ''));
}

String? guessSmsDirection(String body) {
  if (RegExp(r'收入|入账|到账|转入|工资|退款|收款|收到').hasMatch(body)) {
    return 'income';
  }
  if (RegExp(r'支出|消费|扣款|付款|转出|支付|交易|出账|代扣|发起').hasMatch(body)) {
    return 'expense';
  }
  return null;
}

String extractSmsCounterparty(String body) {
  for (final pattern in [
    RegExp(r'(?:交易商户|商户|交易地点|交易摘要|付款方|收款方|对方户名|交易对象)[:：]\s*([^,，。；;]+)'),
    RegExp(r'通过(.+?)(?:消费|支出|出账|扣款|付款|支付)'),
    RegExp(r'，(.+?)(?:代扣)?(?:出账|支出|消费|扣款|付款|支付)'),
    RegExp(r'(?:收入|支出)[（(]\s*([^）)]+)'),
    RegExp(r'来自([^,，。；;]+?)的转账'),
    RegExp(r'交易成功：在([^,，。；;]+?)(?:消费|支出|付款|支付)'),
    RegExp(r'扣款成功：([^,，。；;]+?)(?:人民币|RMB|CNY|￥|¥|\d)'),
    RegExp(r'向([^,，。；;]+?)(?:支付|付款)'),
    RegExp(r'在([^,，。；;]+?)(?:消费|支出)'),
    RegExp(r'在([^,，。；;]+?)(?:支付|付款)(?:人民币|RMB|CNY|￥|¥|\d)'),
    RegExp(r'(?:支出|消费|付款|支付)[（(]?\s*(.+?)(?:\d[\d,]*(?:\.\d{1,2})?\s*元)'),
  ]) {
    final match = pattern.firstMatch(body);
    if (match != null) {
      return cleanSmsCounterparty(match.group(1)!);
    }
  }
  return '';
}

String cleanSmsCounterparty(String raw) {
  var value = raw
      .replaceAll(RegExp(r'^[（(]+'), '')
      .replaceAll(RegExp(r'[）),，。；;]+$'), '')
      .trim();
  value = value
      .replaceFirst(RegExp(r'^(?:支出|消费|付款|支付|交易|转出|转入|收入|退款)\s*'), '')
      .replaceFirst(RegExp(r'代扣$'), '')
      .trim();
  if (value.length > 60) {
    value = value.substring(0, 60);
  }
  return value;
}

String extractSmsAccountHint(String body) {
  final tail = extractSmsCardTail(body);
  return tail.isEmpty ? '' : '尾号$tail';
}

String extractSmsCardTail(String body) {
  final match = RegExp(
    r'(?:尾号|尾数|卡尾号|付款卡尾号|银行卡尾号|卡号后四位)\s*(\d{3,4})',
  ).firstMatch(body);
  return match == null ? '' : match.group(1)!;
}

String extractSmsBankName(String body) {
  final bracket = RegExp(r'【([^】]+银行[^】]*)】').firstMatch(body);
  if (bracket != null) {
    return bracket.group(1)!.trim();
  }
  final plain = RegExp(r'([\u4e00-\u9fa5]{2,12}银行)').firstMatch(body);
  return plain == null ? '' : plain.group(1)!.trim();
}

bool _bodyMatchesAccount(String body, LedgerAccount account) {
  final tail = account.cardTail;
  if (tail.isNotEmpty && extractSmsCardTail(body) != tail) {
    return false;
  }
  if (tail.isNotEmpty) {
    return true;
  }
  final bankName = extractSmsBankName(body);
  if (bankName.isNotEmpty && !bankNameMatches(account.name, bankName)) {
    return false;
  }
  if (tail.isEmpty && bankName.isEmpty) {
    return normalizeSmsBody(body).contains(account.name);
  }
  return true;
}

bool _hasMinimumTemplateSlots(String pattern) {
  return pattern.contains('{amount}') &&
      pattern.contains('{card_tail}') &&
      pattern.contains('{date_time}');
}

List<String> _slotsInPattern(String pattern) {
  final slots = <String>{};
  for (final match in RegExp(r'\{([a-z][a-z0-9_]*)\}').allMatches(pattern)) {
    slots.add(match.group(1)!);
  }
  return slots.toList()..sort();
}

String _templateId(String sender, String accountId, String pattern) {
  final input = 'ledger-sms-template-v1|$sender|$accountId|$pattern';
  return sha256.convert(input.codeUnits).toString().substring(0, 16);
}

Map<String, String>? _extractTemplateValues(String body, String pattern) {
  final normalizedPattern = normalizeSmsBody(pattern);
  if (_hasInvalidTemplateBraces(normalizedPattern)) {
    return null;
  }
  final slotPattern = RegExp(r'\{([a-z][a-z0-9_]*)\}');
  final names = <String>[];
  final regex = StringBuffer('^');
  var cursor = 0;
  for (final match in slotPattern.allMatches(normalizedPattern)) {
    regex.write(
      _escapeRegExp(normalizedPattern.substring(cursor, match.start)),
    );
    regex.write(r'([\s\S]+?)');
    names.add(match.group(1)!);
    cursor = match.end;
  }
  regex.write(_escapeRegExp(normalizedPattern.substring(cursor)));
  regex.write(r'$');
  if (names.isEmpty) {
    return null;
  }
  final matched = RegExp(
    regex.toString(),
    caseSensitive: false,
  ).firstMatch(body);
  if (matched == null) {
    return null;
  }
  final values = <String, String>{};
  for (var i = 0; i < names.length; i++) {
    final value = matched.group(i + 1)?.trim() ?? '';
    if (value.isEmpty) {
      return null;
    }
    values.update(
      names[i],
      (old) => '$old $value'.trim(),
      ifAbsent: () => value,
    );
  }
  return values;
}

bool _hasInvalidTemplateBraces(String pattern) {
  final slotPattern = RegExp(r'\{[a-z][a-z0-9_]*\}');
  var cursor = 0;
  for (final match in slotPattern.allMatches(pattern)) {
    if (pattern.substring(cursor, match.start).contains(RegExp(r'[{}]'))) {
      return true;
    }
    cursor = match.end;
  }
  return pattern.substring(cursor).contains(RegExp(r'[{}]'));
}

String _escapeRegExp(String input) {
  const special = r'\^$.*+?()[]{}|';
  final out = StringBuffer();
  for (final unit in input.codeUnits) {
    final char = String.fromCharCode(unit);
    if (special.contains(char)) {
      out.write(r'\');
    }
    out.write(char);
  }
  return out.toString();
}
