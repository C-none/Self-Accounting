import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_client/src/models.dart';
import 'package:ledger_client/src/pages/sms_import_page.dart';
import 'package:ledger_client/src/pages/stats_page.dart';
import 'package:ledger_client/src/sms/sms_platform.dart';
import 'package:ledger_client/src/sms/sms_templates.dart';

void main() {
  test('parses RMB input to integer cents', () {
    expect(parseAmountCent('12.34'), 1234);
    expect(parseAmountCent('12'), 1200);
    expect(parseAmountCent('12.3'), 1230);
    expect(parseAmountCent(' 001.20 '), 120);
    expect(parseAmountCent('0.01'), 1);
    expect(parseAmountCent('0'), isNull);
    expect(parseAmountCent('0.00'), isNull);
    expect(parseAmountCent('.12'), isNull);
    expect(parseAmountCent('12.'), isNull);
    expect(parseAmountCent('12.345'), isNull);
    expect(parseAmountCent('-12.34'), isNull);
    expect(parseAmountCent('12元'), isNull);
  });

  test('formats integer cents for display', () {
    expect(formatMoney(0), '¥0.00');
    expect(formatMoney(1), '¥0.01');
    expect(formatMoney(120), '¥1.20');
    expect(formatMoney(123456), '¥1234.56');
  });

  test('parses empty transaction pages and statistics safely', () {
    final page = TransactionPage.fromJson({
      'items': null,
      'page': 1,
      'page_size': 50,
      'total': 0,
    });
    expect(page.items, isEmpty);
    expect(page.page, 1);

    final stat = CategoryStat.fromJson({
      'category_id': 'expense_food',
      'category_name': '餐饮',
      'amount_cent': 1234,
      'percent': 50,
    });
    expect(stat.percent, 50.0);

    final point = TimelinePoint.fromJson({
      'date': '2026-06-01',
      'amount_cent': 0,
    });
    expect(point.amountCent, 0);
  });

  test(
    'parses SMS body into structured candidate without uploading raw body',
    () {
      final bootstrap = BootstrapData(
        device: Device(
          id: 'dev',
          name: 'Android',
          platform: 'android',
          isAdmin: false,
        ),
        categories: [
          Category(
            id: 'expense_food',
            parentId: '',
            name: '餐饮',
            type: 'expense',
            sortOrder: 10,
          ),
        ],
        members: [Member(id: 'member_self', name: '本人')],
        accounts: [
          LedgerAccount(
            id: 'account_cmb_1234',
            name: '招商银行',
            type: 'bank',
            maskedIdentifier: '1234',
          ),
        ],
        features: const {'sms': true},
        maxUploadSizeBytes: 20 * 1024 * 1024,
      );
      final candidate = parseSmsBody(
        body: '尾号1234账户消费45.67元，商户：咖啡店',
        sender: '95555',
        dateMillis: DateTime(2026, 6, 1).millisecondsSinceEpoch,
        bootstrap: bootstrap,
      );
      expect(candidate, isNotNull);
      expect(candidate!.amountCent, 4567);
      expect(candidate.rawBody, '尾号1234账户消费45.67元，商户：咖啡店');
      expect(candidate.direction, 'expense');
      expect(candidate.categoryL1Id, 'expense_food');
      expect(candidate.accountHint, '尾号1234');
      expect(candidate.accountId, 'account_cmb_1234');
      expect(candidate.description.contains('消费45.67'), isFalse);
      expect(
        candidate.smsReceivedAtMs,
        DateTime(2026, 6, 1).millisecondsSinceEpoch,
      );
      final body = smsImportBody(candidate);
      expect(body.keys, isNot(contains('raw_body')));
      expect(body.keys, isNot(contains('body')));
      expect(body.keys, isNot(contains('message')));
      expect(body.values, isNot(contains(candidate.rawBody)));
    },
  );

  test('applies usable category suggestions and keeps raw body local', () {
    final candidate = _smsCandidate(
      categoryL1Id: 'expense_food',
      rawBody: 'local sms body must stay local',
    );
    final suggestionItems = categorySuggestionItemsForSms([candidate]);
    expect(suggestionItems, hasLength(1));
    expect(suggestionItems.first.keys, isNot(contains('raw_body')));
    expect(suggestionItems.first.keys, isNot(contains('body')));
    expect(suggestionItems.first.keys, isNot(contains('message')));
    expect(suggestionItems.first.values, isNot(contains(candidate.rawBody)));

    final updated = applyCategorySuggestions(
      [candidate],
      [
        CategorySuggestion(
          clientRef: candidate.smsHash,
          categoryL1Id: 'expense_transport',
          categoryL2Id: null,
          confidence: 0.82,
          method: 'nb',
          alternatives: [
            CategorySuggestionAlternative(
              categoryL1Id: 'expense_transport',
              categoryL2Id: null,
              confidence: 0.82,
            ),
            CategorySuggestionAlternative(
              categoryL1Id: 'expense_food',
              categoryL2Id: null,
              confidence: 0.18,
            ),
          ],
        ),
      ],
    );

    expect(updated.single.categoryL1Id, 'expense_transport');
    expect(updated.single.rawBody, candidate.rawBody);
  });

  test('keeps local category when suggestion confidence or margin is weak', () {
    final candidate = _smsCandidate(categoryL1Id: 'expense_food');
    final weakConfidence = applyCategorySuggestions(
      [candidate],
      [
        CategorySuggestion(
          clientRef: candidate.smsHash,
          categoryL1Id: 'expense_transport',
          categoryL2Id: null,
          confidence: 0.60,
          method: 'nb',
          alternatives: const [],
        ),
      ],
    );
    expect(weakConfidence.single.categoryL1Id, 'expense_food');

    final weakMargin = applyCategorySuggestions(
      [candidate],
      [
        CategorySuggestion(
          clientRef: candidate.smsHash,
          categoryL1Id: 'expense_transport',
          categoryL2Id: null,
          confidence: 0.70,
          method: 'nb',
          alternatives: [
            CategorySuggestionAlternative(
              categoryL1Id: 'expense_transport',
              categoryL2Id: null,
              confidence: 0.70,
            ),
            CategorySuggestionAlternative(
              categoryL1Id: 'expense_food',
              categoryL2Id: null,
              confidence: 0.62,
            ),
          ],
        ),
      ],
    );
    expect(weakMargin.single.categoryL1Id, 'expense_food');

    final noSuggestions = applyCategorySuggestions([candidate], const []);
    expect(noSuggestions.single.categoryL1Id, 'expense_food');
  });

  test('SMS hash uses sender received time and normalized body only', () {
    final bootstrap = BootstrapData(
      device: Device(
        id: 'dev',
        name: 'Android',
        platform: 'android',
        isAdmin: false,
      ),
      categories: [
        Category(
          id: 'expense_other',
          parentId: '',
          name: '其他支出',
          type: 'expense',
          sortOrder: 10,
        ),
      ],
      members: [Member(id: 'member_self', name: '本人')],
      accounts: [
        LedgerAccount(
          id: 'account_cash',
          name: '现金',
          type: 'cash',
          maskedIdentifier: '',
        ),
      ],
      features: const {'sms': true},
      maxUploadSizeBytes: 20 * 1024 * 1024,
    );
    final dateMillis = DateTime(2026, 6, 1, 12, 0).millisecondsSinceEpoch;
    final compact = parseSmsBody(
      body: '账户 交易45.67元， 商户：咖啡店',
      sender: '95555',
      dateMillis: dateMillis,
      bootstrap: bootstrap,
    );
    final spaced = parseSmsBody(
      body: ' 账户   交易45.67元，\n商户：咖啡店 ',
      sender: '95555',
      dateMillis: dateMillis,
      bootstrap: bootstrap,
    );
    final differentSender = parseSmsBody(
      body: '账户 交易45.67元， 商户：咖啡店',
      sender: '95588',
      dateMillis: dateMillis,
      bootstrap: bootstrap,
    );
    final differentTime = parseSmsBody(
      body: '账户 交易45.67元， 商户：咖啡店',
      sender: '95555',
      dateMillis: dateMillis + 1000,
      bootstrap: bootstrap,
    );
    final sameRoundedSecondTime = parseSmsBody(
      body: '账户 交易45.67元， 商户：咖啡店',
      sender: '95555',
      dateMillis: dateMillis + 289,
      bootstrap: bootstrap,
    );
    final differentBootstrap = parseSmsBody(
      body: '账户 交易45.67元， 商户：咖啡店',
      sender: '95555',
      dateMillis: dateMillis,
      bootstrap: BootstrapData(
        device: bootstrap.device,
        categories: [
          Category(
            id: 'expense_custom',
            parentId: '',
            name: '自定义支出',
            type: 'expense',
            sortOrder: 10,
          ),
        ],
        members: bootstrap.members,
        accounts: bootstrap.accounts,
        features: bootstrap.features,
        maxUploadSizeBytes: bootstrap.maxUploadSizeBytes,
      ),
    );
    expect(compact, isNotNull);
    expect(spaced, isNotNull);
    expect(differentSender, isNotNull);
    expect(differentTime, isNotNull);
    expect(sameRoundedSecondTime, isNotNull);
    expect(differentBootstrap, isNotNull);
    expect(spaced!.smsHash, compact!.smsHash);
    expect(sameRoundedSecondTime!.smsHash, compact.smsHash);
    expect(differentSender!.smsHash, isNot(compact.smsHash));
    expect(differentTime!.smsHash, isNot(compact.smsHash));
    expect(differentBootstrap!.smsHash, compact.smsHash);
  });

  test('parses ICBC complex card SMS with bank and balance fields', () {
    final bootstrap = BootstrapData(
      device: Device(
        id: 'dev',
        name: 'Android',
        platform: 'android',
        isAdmin: false,
      ),
      categories: [
        Category(
          id: 'expense_food',
          parentId: '',
          name: '餐饮',
          type: 'expense',
          sortOrder: 10,
        ),
      ],
      members: [Member(id: 'member_self', name: '本人')],
      accounts: [
        LedgerAccount(
          id: 'account_icbc_0973',
          name: '工商银行',
          type: 'bank',
          maskedIdentifier: '0973',
        ),
      ],
      features: const {'sms': true},
      maxUploadSizeBytes: 20 * 1024 * 1024,
    );
    final candidate = parseSmsBody(
      body: '尾号0973卡6月6日10:31支出(消费美团支付-橘选数码生活精品馆（国家会)37元，余额16,026.09元。【工商银行】',
      sender: '95588',
      dateMillis: DateTime(2026, 6, 6, 10, 40).millisecondsSinceEpoch,
      bootstrap: bootstrap,
      bankNameFilter: '工商银行',
    );
    expect(candidate, isNotNull);
    expect(candidate!.amountCent, 3700);
    expect(candidate.direction, 'expense');
    expect(candidate.accountId, 'account_icbc_0973');
    expect(candidate.accountHint, '尾号0973');
    expect(candidate.bankName, '工商银行');
    expect(candidate.counterparty.contains('橘选数码生活精品馆'), isTrue);
    expect(
      candidate.smsTime,
      DateTime(2026, 6, 6, 10, 40).millisecondsSinceEpoch ~/ 1000,
    );
    expect(
      parseSmsBody(
        body: '尾号0973卡6月6日10:31支出(消费美团支付-橘选数码生活精品馆（国家会)37元，余额16,026.09元。【工商银行】',
        sender: '95588',
        dateMillis: DateTime(2026, 6, 6, 10, 40).millisecondsSinceEpoch,
        bootstrap: bootstrap,
        bankNameFilter: '招商银行',
      ),
      isNull,
    );
  });

  test('learns enabled SMS templates from msg_test samples', () {
    final samples = _loadMsgTestSamples();
    final bootstrap = _templateBootstrap();
    final accountA = bootstrap.accounts.firstWhere(
      (item) => item.name == '贵州银行',
    );
    final accountB = bootstrap.accounts.firstWhere(
      (item) => item.name == '工商银行',
    );
    final fromDate = DateTime(2026, 6, 1);
    final toDate = DateTime(2026, 6, 6);

    final rowsA = _rowsForSamples(samples['A']!);
    final rowsB = _rowsForSamples(samples['B']!);
    final learnedA = learnSmsTemplatesFromRows(
      rowsA,
      account: accountA,
      sender: samples['A']!.sender,
      fromDate: fromDate,
      toDate: toDate,
    );
    final learnedB = learnSmsTemplatesFromRows(
      rowsB,
      account: accountB,
      sender: samples['B']!.sender,
      fromDate: fromDate,
      toDate: toDate,
    );

    expect(learnedA, hasLength(2));
    expect(learnedB, hasLength(1));
    expect(learnedA.first.sampleCount, 3);
    expect(learnedA.last.sampleCount, 2);
    expect(
      smsTemplatePattern(samples['A']!.messages[2]),
      smsTemplatePattern(samples['A']!.messages[3]),
    );

    var templates = replaceSmsTemplatesForScope(
      const [],
      learnedA,
      sender: samples['A']!.sender,
      accountId: accountA.id,
    );
    expect(
      parseSmsRows(
        rowsA,
        bootstrap,
        fromDate: fromDate,
        toDate: toDate,
        templates: templates,
        requireTemplate: true,
      ),
      isEmpty,
    );

    templates = templates
        .map(
          (item) => item.id == learnedA.first.id
              ? item.copyWith(enabled: true)
              : item,
        )
        .toList();
    expect(
      parseSmsRows(
        rowsA,
        bootstrap,
        fromDate: fromDate,
        toDate: toDate,
        templates: templates,
        requireTemplate: true,
      ),
      hasLength(3),
    );

    templates = templates.map((item) => item.copyWith(enabled: true)).toList();
    expect(
      parseSmsRows(
        rowsA,
        bootstrap,
        fromDate: fromDate,
        toDate: toDate,
        templates: templates,
        requireTemplate: true,
      ),
      hasLength(5),
    );

    templates = replaceSmsTemplatesForScope(
      templates,
      learnedB.map((item) => item.copyWith(enabled: true)).toList(),
      sender: samples['B']!.sender,
      accountId: accountB.id,
    );
    final parsedB = parseSmsRows(
      rowsB,
      bootstrap,
      fromDate: fromDate,
      toDate: toDate,
      templates: templates,
      requireTemplate: true,
    );
    expect(parsedB, hasLength(4));
    expect(parsedB.first.accountId, accountB.id);
    expect(parsedB.first.balanceCent, isNotNull);

    final storedJson = encodeSmsTemplates(templates);
    expect(storedJson.contains(samples['A']!.messages.first), isFalse);
    expect(storedJson.contains('55696.02'), isFalse);
    expect(storedJson.contains('特约商户'), isFalse);

    final expectedParsedCounts = {
      'C': 3,
      'D': 3,
      'E': 3,
      'F': 2,
      'G': 2,
      'H': 7,
    };
    for (final entry in expectedParsedCounts.entries) {
      final sample = samples[entry.key]!;
      final account = bootstrap.accounts.firstWhere(
        (item) => item.id == 'account_${entry.key.toLowerCase()}',
      );
      final rows = _rowsForSamples(sample);
      final learned = learnSmsTemplatesFromRows(
        rows,
        account: account,
        sender: sample.sender,
        fromDate: fromDate,
        toDate: toDate,
      );
      expect(learned, isNotEmpty, reason: 'account ${entry.key}');
      final parsed = parseSmsRows(
        rows,
        bootstrap,
        fromDate: fromDate,
        toDate: toDate,
        templates: learned.map((item) => item.copyWith(enabled: true)).toList(),
        requireTemplate: true,
      );
      expect(parsed, hasLength(entry.value), reason: 'account ${entry.key}');
      expect(parsed.every((item) => item.accountId == account.id), isTrue);
      expect(parsed.every((item) => item.rawBody.isNotEmpty), isTrue);
      expect(parsed.every((item) => item.balanceCent != null), isTrue);
      expect(
        parsed.every(
          (item) =>
              item.smsTime ==
              DateTime(2026, 6, 6, 12).millisecondsSinceEpoch ~/ 1000,
        ),
        isTrue,
      );
      if (entry.key == 'H') {
        expect(parsed.every((item) => item.counterparty.isNotEmpty), isTrue);
      }
    }
  });

  test('stats default date range ends today and starts one month earlier', () {
    final range = defaultStatsDateRange(DateTime(2026, 6, 13, 14, 30));
    expect(range.fromDate, DateTime(2026, 5, 13));
    expect(range.toDate, DateTime(2026, 6, 13));

    final endOfMonth = defaultStatsDateRange(DateTime(2026, 3, 31, 8));
    expect(endOfMonth.fromDate, DateTime(2026, 2, 28));
    expect(endOfMonth.toDate, DateTime(2026, 3, 31));
  });
}

class _MsgSample {
  _MsgSample({required this.sender, required this.messages});

  final String sender;
  final List<String> messages;
}

Map<String, _MsgSample> _loadMsgTestSamples() {
  final file = File('../msg_test.md');
  final sections = <String, _MsgSample>{};
  String? account;
  String? sender;
  var messages = <String>[];

  void flush() {
    if (account != null && sender != null) {
      sections[account] = _MsgSample(sender: sender, messages: messages);
    }
  }

  for (final rawLine in file.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    if (line.startsWith('银行账户:')) {
      flush();
      account = line.split(':').last.trim();
      sender = null;
      messages = <String>[];
    } else if (line.startsWith('发送号码:')) {
      sender = line.split(':').last.trim();
    } else if (!line.startsWith('---') && account != null) {
      messages.add(line);
    }
  }
  flush();
  return sections;
}

List<Map<String, dynamic>> _rowsForSamples(_MsgSample sample) {
  final receivedAt = DateTime(2026, 6, 6, 12).millisecondsSinceEpoch;
  return [
    for (final message in sample.messages)
      {'sender': sample.sender, 'dateMillis': receivedAt, 'body': message},
  ];
}

SmsCandidate _smsCandidate({
  String categoryL1Id = 'expense_food',
  String rawBody = 'local sms body',
}) {
  return SmsCandidate(
    smsHash: 'hash-1',
    senderMasked: '106**01',
    smsReceivedAtMs: DateTime(2026, 6, 1, 12).millisecondsSinceEpoch,
    smsTime: DateTime(2026, 6, 1, 12).millisecondsSinceEpoch ~/ 1000,
    amountCent: 2680,
    direction: 'expense',
    counterparty: '星巴克咖啡',
    accountHint: '尾号1234',
    bankName: '示例银行',
    accountId: 'account_bank_1234',
    categoryL1Id: categoryL1Id,
    categoryL2Id: null,
    memberId: 'member_self',
    description: '短信导入：星巴克咖啡',
    rawBody: rawBody,
  );
}

BootstrapData _templateBootstrap() {
  return BootstrapData(
    device: Device(
      id: 'dev',
      name: 'Android',
      platform: 'android',
      isAdmin: false,
    ),
    categories: [
      Category(
        id: 'expense_transport',
        parentId: '',
        name: '交通',
        type: 'expense',
        sortOrder: 10,
      ),
      Category(
        id: 'income_other',
        parentId: '',
        name: '其他收入',
        type: 'income',
        sortOrder: 20,
      ),
    ],
    members: [Member(id: 'member_self', name: '本人')],
    accounts: [
      LedgerAccount(
        id: 'account_a_3949',
        name: '贵州银行',
        type: 'bank',
        maskedIdentifier: '3949',
      ),
      LedgerAccount(
        id: 'account_b_0973',
        name: '工商银行',
        type: 'bank',
        maskedIdentifier: '0973',
      ),
      LedgerAccount(
        id: 'account_c',
        name: '示例银行',
        type: 'bank',
        maskedIdentifier: '0826',
      ),
      LedgerAccount(
        id: 'account_d',
        name: '示例银行',
        type: 'bank',
        maskedIdentifier: '3179',
      ),
      LedgerAccount(
        id: 'account_e',
        name: '示例银行',
        type: 'bank',
        maskedIdentifier: '6405',
      ),
      LedgerAccount(
        id: 'account_f',
        name: '示例银行',
        type: 'bank',
        maskedIdentifier: '5551',
      ),
      LedgerAccount(
        id: 'account_g',
        name: '示例银行',
        type: 'bank',
        maskedIdentifier: '7288',
      ),
      LedgerAccount(
        id: 'account_h',
        name: '示例银行',
        type: 'bank',
        maskedIdentifier: '4412',
      ),
    ],
    features: const {'sms': true},
    maxUploadSizeBytes: 20 * 1024 * 1024,
  );
}
