import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/services.dart';
import 'package:ledger_client/src/models.dart';
import 'package:ledger_client/src/sms/sms_templates.dart';

const Object _smsCandidateNoChange = Object();

class SmsPlatformAdapter {
  static const MethodChannel _channel = MethodChannel('ledger/sms');

  Future<bool> isSupported() async {
    if (kIsWeb) {
      return false;
    }
    return await _channel.invokeMethod<bool>('isSupported') ?? false;
  }

  Future<bool> checkPermissions() async {
    if (kIsWeb) {
      return false;
    }
    return await _channel.invokeMethod<bool>('checkPermissions') ?? false;
  }

  Future<bool> requestPermissions() async {
    if (kIsWeb) {
      return false;
    }
    return await _channel.invokeMethod<bool>('requestPermissions') ?? false;
  }

  Future<List<SmsCandidate>> scanRecent({
    required BootstrapData bootstrap,
    required DateTime fromDate,
    required DateTime toDate,
    String? bankName,
    List<SmsTemplate> templates = const [],
    bool requireTemplate = false,
    int limit = 80,
  }) async {
    if (kIsWeb) {
      return const [];
    }
    final sinceMillis = DateTime(
      fromDate.year,
      fromDate.month,
      fromDate.day,
    ).millisecondsSinceEpoch;
    final rows =
        await _channel.invokeMethod<List<dynamic>>('scanSms', {
          'sinceMillis': sinceMillis,
          'limit': limit,
        }) ??
        const [];
    return parseSmsRows(
      rows,
      bootstrap,
      fromDate: fromDate,
      toDate: toDate,
      bankName: bankName,
      templates: templates,
      requireTemplate: requireTemplate,
    );
  }

  Future<List<Map<String, dynamic>>> readRecentRows({
    required DateTime fromDate,
    int limit = 200,
  }) async {
    if (kIsWeb) {
      return const [];
    }
    final sinceMillis = DateTime(
      fromDate.year,
      fromDate.month,
      fromDate.day,
    ).millisecondsSinceEpoch;
    final rows =
        await _channel.invokeMethod<List<dynamic>>('scanSms', {
          'sinceMillis': sinceMillis,
          'limit': limit,
        }) ??
        const [];
    return rows
        .whereType<Map>()
        .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }

  Future<List<SmsCandidate>> pollBroadcasts({
    required BootstrapData bootstrap,
    DateTime? fromDate,
    DateTime? toDate,
    String? bankName,
    List<SmsTemplate> templates = const [],
    bool requireTemplate = false,
  }) async {
    if (kIsWeb) {
      return const [];
    }
    final rows =
        await _channel.invokeMethod<List<dynamic>>('pollBroadcasts') ??
        const [];
    return parseSmsRows(
      rows,
      bootstrap,
      fromDate: fromDate,
      toDate: toDate,
      bankName: bankName,
      templates: templates,
      requireTemplate: requireTemplate,
    );
  }
}

class SmsCandidate {
  SmsCandidate({
    required this.smsHash,
    required this.senderMasked,
    required this.smsReceivedAtMs,
    required this.smsTime,
    required this.amountCent,
    required this.direction,
    required this.counterparty,
    required this.accountHint,
    required this.bankName,
    required this.accountId,
    required this.categoryL1Id,
    required this.categoryL2Id,
    required this.memberId,
    required this.description,
    required this.rawBody,
    this.templateId = '',
    this.templateLabel = '',
    this.balanceCent,
  });

  final String smsHash;
  final String senderMasked;
  final int smsReceivedAtMs;
  final int smsTime;
  final int amountCent;
  final String direction;
  final String counterparty;
  final String accountHint;
  final String bankName;
  final String accountId;
  final String categoryL1Id;
  final String? categoryL2Id;
  final String memberId;
  final String description;
  final String rawBody;
  final String templateId;
  final String templateLabel;
  final int? balanceCent;

  SmsCandidate copyWith({
    String? categoryL1Id,
    Object? categoryL2Id = _smsCandidateNoChange,
  }) {
    return SmsCandidate(
      smsHash: smsHash,
      senderMasked: senderMasked,
      smsReceivedAtMs: smsReceivedAtMs,
      smsTime: smsTime,
      amountCent: amountCent,
      direction: direction,
      counterparty: counterparty,
      accountHint: accountHint,
      bankName: bankName,
      accountId: accountId,
      categoryL1Id: categoryL1Id ?? this.categoryL1Id,
      categoryL2Id: identical(categoryL2Id, _smsCandidateNoChange)
          ? this.categoryL2Id
          : categoryL2Id as String?,
      memberId: memberId,
      description: description,
      rawBody: rawBody,
      templateId: templateId,
      templateLabel: templateLabel,
      balanceCent: balanceCent,
    );
  }
}

List<SmsCandidate> parseSmsRows(
  List<dynamic> rows,
  BootstrapData bootstrap, {
  DateTime? fromDate,
  DateTime? toDate,
  String? bankName,
  List<SmsTemplate> templates = const [],
  bool requireTemplate = false,
}) {
  final out = <SmsCandidate>[];
  final seen = <String>{};
  final fromSeconds = fromDate == null
      ? null
      : DateTime(
              fromDate.year,
              fromDate.month,
              fromDate.day,
            ).millisecondsSinceEpoch ~/
            1000;
  final toSeconds = toDate == null
      ? null
      : DateTime(
              toDate.year,
              toDate.month,
              toDate.day,
              23,
              59,
              59,
            ).millisecondsSinceEpoch ~/
            1000;
  for (final row in rows) {
    if (row is! Map) {
      continue;
    }
    final body = row['body']?.toString() ?? '';
    final sender = row['sender']?.toString() ?? '';
    final dateMillis = (row['dateMillis'] as num?)?.toInt() ?? 0;
    final parsed = parseSmsBody(
      body: body,
      sender: sender,
      dateMillis: dateMillis,
      bootstrap: bootstrap,
      bankNameFilter: bankName,
      templates: templates,
      requireTemplate: requireTemplate,
    );
    if (parsed != null && fromSeconds != null && parsed.smsTime < fromSeconds) {
      continue;
    }
    if (parsed != null && toSeconds != null && parsed.smsTime > toSeconds) {
      continue;
    }
    if (parsed != null && seen.add(parsed.smsHash)) {
      out.add(parsed);
    }
  }
  return out;
}

SmsCandidate? parseSmsBody({
  required String body,
  required String sender,
  required int dateMillis,
  required BootstrapData bootstrap,
  String? bankNameFilter,
  List<SmsTemplate> templates = const [],
  bool requireTemplate = false,
}) {
  final normalized = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty || dateMillis <= 0) {
    return null;
  }
  final templateMatch = matchEnabledSmsTemplateWithValues(
    body: normalized,
    sender: sender,
    templates: templates,
  );
  final matchedTemplate = templateMatch?.template;
  final templateValues = templateMatch?.values ?? const <String, String>{};
  if (requireTemplate && matchedTemplate == null) {
    return null;
  }
  final templateAmount = templateValues.containsKey('amount')
      ? parseSmsMoneyCent(templateValues['amount']!)
      : null;
  if (matchedTemplate != null &&
      templateValues.containsKey('amount') &&
      templateAmount == null) {
    return null;
  }
  final amount = templateAmount ?? _extractAmountCent(normalized);
  if (amount == null) {
    return null;
  }
  final directionValue = templateValues['direction'];
  final direction = directionValue == null
      ? _guessDirection(normalized)
      : (_guessDirection(directionValue) ?? _guessDirection(normalized));
  if (direction == null) {
    return null;
  }
  final category = _guessCategory(bootstrap, normalized, direction);
  final account = matchedTemplate == null
      ? _guessAccount(bootstrap, normalized, bankNameFilter)
      : _accountById(bootstrap, matchedTemplate.accountId);
  if (matchedTemplate != null &&
      bankNameFilter?.trim().isNotEmpty == true &&
      account != null &&
      !bankNameMatches(account.name, bankNameFilter!.trim())) {
    return null;
  }
  final member = bootstrap.members.firstOrNull;
  if (category == null || account == null || member == null) {
    return null;
  }
  final templateCounterparty =
      templateValues['merchant'] ?? templateValues['counterparty'];
  final counterparty = templateCounterparty == null
      ? _extractCounterparty(normalized)
      : cleanSmsCounterparty(templateCounterparty);
  final cardTail = _templateCardTail(templateValues['card_tail']);
  final accountHint = cardTail == null
      ? _extractAccountHint(normalized)
      : '尾号$cardTail';
  final bankName =
      _templateBankName(templateValues['bank']) ??
      _extractBankName(normalized).ifEmpty(account.name);
  final smsTime = dateMillis ~/ 1000;
  final balanceCent = templateValues.containsKey('balance')
      ? parseSmsMoneyCent(templateValues['balance']!)
      : extractSmsBalanceCent(normalized);
  final hashReceivedAtSecond = (dateMillis + 500) ~/ 1000;
  final hashInput =
      'ledger-sms-v2|${sender.trim()}|$hashReceivedAtSecond|$normalized';
  return SmsCandidate(
    smsHash: sha256.convert(hashInput.codeUnits).toString(),
    senderMasked: _maskSender(sender),
    smsReceivedAtMs: dateMillis,
    smsTime: smsTime,
    amountCent: amount,
    direction: direction,
    counterparty: counterparty,
    accountHint: accountHint,
    bankName: bankName,
    accountId: account.id,
    categoryL1Id: category.id,
    categoryL2Id: null,
    memberId: member.id,
    description: counterparty.isEmpty ? '短信导入' : '短信导入：$counterparty',
    rawBody: body,
    templateId: matchedTemplate?.id ?? '',
    templateLabel: matchedTemplate?.pattern ?? '',
    balanceCent: balanceCent,
  );
}

int? _extractAmountCent(String body) {
  return extractSmsAmountCent(body);
}

String? _guessDirection(String body) {
  return guessSmsDirection(body);
}

Category? _guessCategory(
  BootstrapData bootstrap,
  String body,
  String direction,
) {
  final top = bootstrap.categories
      .where((c) => c.isTopLevel && c.type == direction)
      .toList();
  if (top.isEmpty) {
    return null;
  }
  if (direction == 'income') {
    return top.firstWhere(
      (c) => c.id == 'income_salary' && RegExp(r'工资|薪').hasMatch(body),
      orElse: () => top.first,
    );
  }
  if (RegExp(r'餐|饭|咖啡|奶茶|饮|美团|饿了么').hasMatch(body)) {
    return top.firstWhere(
      (c) => c.id == 'expense_food',
      orElse: () => top.first,
    );
  }
  if (RegExp(r'公交|地铁|打车|滴滴|加油|停车').hasMatch(body)) {
    return top.firstWhere(
      (c) => c.id == 'expense_transport',
      orElse: () => top.first,
    );
  }
  return top.firstWhere(
    (c) => c.id == 'expense_other',
    orElse: () => top.first,
  );
}

LedgerAccount? _guessAccount(
  BootstrapData bootstrap,
  String body,
  String? bankNameFilter,
) {
  var accounts = bootstrap.accounts;
  final filterBank = (bankNameFilter ?? '').trim();
  if (filterBank.isNotEmpty) {
    accounts = accounts
        .where((account) => bankNameMatches(account.name, filterBank))
        .toList();
  }
  final smsBankName = _extractBankName(body);
  if (smsBankName.isNotEmpty) {
    accounts = accounts
        .where((account) => bankNameMatches(account.name, smsBankName))
        .toList();
  }
  final tail = _extractCardTail(body);
  if (tail.isNotEmpty) {
    final tailMatches = accounts
        .where((account) => account.cardTail == tail)
        .toList();
    if (tailMatches.isNotEmpty) {
      accounts = tailMatches;
    } else if (smsBankName.isNotEmpty || filterBank.isNotEmpty) {
      return null;
    }
  }
  return accounts.firstOrNull;
}

LedgerAccount? _accountById(BootstrapData bootstrap, String id) {
  for (final account in bootstrap.accounts) {
    if (account.id == id) {
      return account;
    }
  }
  return null;
}

String _extractCounterparty(String body) {
  return extractSmsCounterparty(body);
}

String _extractAccountHint(String body) {
  return extractSmsAccountHint(body);
}

String _extractCardTail(String body) {
  return extractSmsCardTail(body);
}

String _extractBankName(String body) {
  return extractSmsBankName(body);
}

String _maskSender(String sender) {
  final clean = sender.trim();
  if (clean.length <= 4) {
    return clean;
  }
  return '${clean.substring(0, 3)}**${clean.substring(clean.length - 2)}';
}

String? _templateCardTail(String? value) {
  if (value == null) {
    return null;
  }
  return RegExp(r'\d{3,4}').firstMatch(value)?.group(0);
}

String? _templateBankName(String? value) {
  final cleaned = value
      ?.replaceAll(RegExp(r'^[【\[]+'), '')
      .replaceAll(RegExp(r'[】\]]+$'), '')
      .trim();
  return cleaned == null || cleaned.isEmpty ? null : cleaned;
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
