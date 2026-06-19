class Device {
  Device({
    required this.id,
    required this.name,
    required this.platform,
    required this.isAdmin,
  });

  final String id;
  final String name;
  final String platform;
  final bool isAdmin;

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] as String,
      name: json['name'] as String,
      platform: json['platform'] as String,
      isAdmin: json['is_admin'] as bool? ?? false,
    );
  }
}

class AuditLogEntry {
  AuditLogEntry({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.deviceId,
    required this.deviceName,
    required this.createdAt,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String action;
  final String deviceId;
  final String deviceName;
  final int createdAt;

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    return AuditLogEntry(
      id: json['id'] as String,
      entityType: json['entity_type'] as String,
      entityId: json['entity_id'] as String,
      action: json['action'] as String,
      deviceId: json['device_id'] as String,
      deviceName: json['device_name'] as String? ?? '',
      createdAt: json['created_at'] as int,
    );
  }
}

class Category {
  Category({
    required this.id,
    required this.parentId,
    required this.name,
    required this.type,
    required this.sortOrder,
  });

  final String id;
  final String parentId;
  final String name;
  final String type;
  final int sortOrder;

  bool get isTopLevel => parentId.isEmpty;

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      parentId: json['parent_id'] as String? ?? '',
      name: json['name'] as String,
      type: json['type'] as String,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

class Member {
  Member({required this.id, required this.name, this.sortOrder = 0});

  final String id;
  final String name;
  final int sortOrder;

  factory Member.fromJson(Map<String, dynamic> json) {
    return Member(
      id: json['id'] as String,
      name: json['name'] as String,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

class LedgerAccount {
  LedgerAccount({
    required this.id,
    required this.name,
    required this.type,
    required this.maskedIdentifier,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String type;
  final String maskedIdentifier;
  final int sortOrder;

  String get cardTail => normalizeCardTail(maskedIdentifier);

  String get displayName {
    final tail = cardTail;
    return tail.isEmpty ? name : '$name 尾号$tail';
  }

  factory LedgerAccount.fromJson(Map<String, dynamic> json) {
    return LedgerAccount(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String? ?? '',
      maskedIdentifier: json['masked_identifier'] as String? ?? '',
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

String normalizeCardTail(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length <= 4) {
    return digits;
  }
  return digits.substring(digits.length - 4);
}

String normalizeBankName(String raw) {
  return raw
      .replaceAll(RegExp(r'[\s【】\[\]（）()]+'), '')
      .replaceAll('股份有限公司', '')
      .replaceAll('有限公司', '')
      .trim();
}

bool bankNameMatches(String accountBankName, String smsBankName) {
  final account = normalizeBankName(accountBankName);
  final sms = normalizeBankName(smsBankName);
  if (account.isEmpty || sms.isEmpty) {
    return false;
  }
  return account == sms || account.contains(sms) || sms.contains(account);
}

class BootstrapData {
  BootstrapData({
    required this.device,
    required this.categories,
    required this.members,
    required this.accounts,
    required this.features,
    required this.maxUploadSizeBytes,
  });

  final Device device;
  final List<Category> categories;
  final List<Member> members;
  final List<LedgerAccount> accounts;
  final Map<String, bool> features;
  final int maxUploadSizeBytes;

  factory BootstrapData.fromJson(Map<String, dynamic> json) {
    return BootstrapData(
      device: Device.fromJson(json['device'] as Map<String, dynamic>),
      categories: (json['categories'] as List<dynamic>)
          .map((e) => Category.fromJson(e as Map<String, dynamic>))
          .toList(),
      members: (json['members'] as List<dynamic>)
          .map((e) => Member.fromJson(e as Map<String, dynamic>))
          .toList(),
      accounts: (json['accounts'] as List<dynamic>)
          .map((e) => LedgerAccount.fromJson(e as Map<String, dynamic>))
          .toList(),
      features: (json['features'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, value as bool? ?? false),
      ),
      maxUploadSizeBytes:
          (json['config'] as Map<String, dynamic>?)?['max_upload_size_bytes']
              as int? ??
          20 * 1024 * 1024,
    );
  }
}

class LedgerTransaction {
  LedgerTransaction({
    required this.id,
    required this.amountCent,
    required this.currency,
    required this.direction,
    required this.transactionTime,
    required this.categoryL1Id,
    required this.categoryL2Id,
    required this.memberId,
    required this.accountId,
    required this.counterparty,
    required this.description,
    required this.source,
    required this.createdByDeviceId,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
  });

  final String id;
  final int amountCent;
  final String currency;
  final String direction;
  final int transactionTime;
  final String categoryL1Id;
  final String categoryL2Id;
  final String memberId;
  final String accountId;
  final String counterparty;
  final String description;
  final String source;
  final String createdByDeviceId;
  final int createdAt;
  final int updatedAt;
  final int version;

  factory LedgerTransaction.fromJson(Map<String, dynamic> json) {
    return LedgerTransaction(
      id: json['id'] as String,
      amountCent: json['amount_cent'] as int,
      currency: json['currency'] as String,
      direction: json['direction'] as String,
      transactionTime: json['transaction_time'] as int,
      categoryL1Id: json['category_l1_id'] as String,
      categoryL2Id: json['category_l2_id'] as String? ?? '',
      memberId: json['member_id'] as String,
      accountId: json['account_id'] as String,
      counterparty: json['counterparty'] as String? ?? '',
      description: json['description'] as String? ?? '',
      source: json['source'] as String,
      createdByDeviceId: json['created_by_device_id'] as String,
      createdAt: json['created_at'] as int,
      updatedAt: json['updated_at'] as int,
      version: json['version'] as int,
    );
  }
}

class TransactionPage {
  TransactionPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  final List<LedgerTransaction> items;
  final int page;
  final int pageSize;
  final int total;

  factory TransactionPage.fromJson(Map<String, dynamic> json) {
    return TransactionPage(
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((e) => LedgerTransaction.fromJson(e as Map<String, dynamic>))
          .toList(),
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
      total: json['total'] as int,
    );
  }
}

class AttachmentMeta {
  AttachmentMeta({
    required this.id,
    required this.transactionId,
    required this.originalFileName,
    required this.storedFileName,
    required this.thumbnailFileName,
    required this.sha256,
    required this.mimeType,
    required this.sizeBytes,
    required this.compressionStatus,
    required this.createdAt,
  });

  final String id;
  final String transactionId;
  final String originalFileName;
  final String storedFileName;
  final String thumbnailFileName;
  final String sha256;
  final String mimeType;
  final int sizeBytes;
  final String compressionStatus;
  final int createdAt;

  factory AttachmentMeta.fromJson(Map<String, dynamic> json) {
    return AttachmentMeta(
      id: json['id'] as String,
      transactionId: json['transaction_id'] as String,
      originalFileName: json['original_file_name'] as String? ?? '',
      storedFileName: json['stored_file_name'] as String,
      thumbnailFileName: json['thumbnail_file_name'] as String? ?? '',
      sha256: json['sha256'] as String,
      mimeType: json['mime_type'] as String,
      sizeBytes: json['size_bytes'] as int,
      compressionStatus: json['compression_status'] as String,
      createdAt: json['created_at'] as int,
    );
  }
}

class CategorySuggestion {
  CategorySuggestion({
    required this.clientRef,
    required this.categoryL1Id,
    required this.categoryL2Id,
    required this.confidence,
    required this.method,
    required this.alternatives,
  });

  final String clientRef;
  final String categoryL1Id;
  final String? categoryL2Id;
  final double confidence;
  final String method;
  final List<CategorySuggestionAlternative> alternatives;

  factory CategorySuggestion.fromJson(Map<String, dynamic> json) {
    return CategorySuggestion(
      clientRef: json['client_ref'] as String? ?? '',
      categoryL1Id: json['category_l1_id'] as String? ?? '',
      categoryL2Id: json['category_l2_id'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      method: json['method'] as String? ?? '',
      alternatives: (json['alternatives'] as List<dynamic>? ?? const [])
          .map(
            (item) => CategorySuggestionAlternative.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }
}

class CategorySuggestionAlternative {
  CategorySuggestionAlternative({
    required this.categoryL1Id,
    required this.categoryL2Id,
    required this.confidence,
  });

  final String categoryL1Id;
  final String? categoryL2Id;
  final double confidence;

  factory CategorySuggestionAlternative.fromJson(Map<String, dynamic> json) {
    return CategorySuggestionAlternative(
      categoryL1Id: json['category_l1_id'] as String? ?? '',
      categoryL2Id: json['category_l2_id'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CategoryStat {
  CategoryStat({
    required this.categoryId,
    required this.categoryName,
    String? groupId,
    String? groupName,
    required this.amountCent,
    required this.percent,
  }) : groupId = groupId ?? categoryId,
       groupName = groupName ?? categoryName;

  final String groupId;
  final String groupName;
  final String categoryId;
  final String categoryName;
  final int amountCent;
  final double percent;

  factory CategoryStat.fromJson(Map<String, dynamic> json) {
    final groupId =
        json['group_id'] as String? ?? json['category_id'] as String;
    final groupName =
        json['group_name'] as String? ?? json['category_name'] as String;
    return CategoryStat(
      groupId: groupId,
      groupName: groupName,
      categoryId: json['category_id'] as String? ?? groupId,
      categoryName: json['category_name'] as String? ?? groupName,
      amountCent: json['amount_cent'] as int,
      percent: (json['percent'] as num).toDouble(),
    );
  }
}

class TimelinePoint {
  TimelinePoint({required this.date, required this.amountCent});

  final String date;
  final int amountCent;

  factory TimelinePoint.fromJson(Map<String, dynamic> json) {
    return TimelinePoint(
      date: json['date'] as String,
      amountCent: json['amount_cent'] as int,
    );
  }
}

class TimelineSeries {
  TimelineSeries({
    required this.groupId,
    required this.groupName,
    required this.points,
  });

  final String groupId;
  final String groupName;
  final List<TimelinePoint> points;

  factory TimelineSeries.fromJson(Map<String, dynamic> json) {
    return TimelineSeries(
      groupId: json['group_id'] as String? ?? '',
      groupName: json['group_name'] as String? ?? '',
      points: (json['points'] as List<dynamic>? ?? const [])
          .map((e) => TimelinePoint.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TimelineStats {
  TimelineStats({
    required this.bucket,
    required this.points,
    required this.series,
  });

  final String bucket;
  final List<TimelinePoint> points;
  final List<TimelineSeries> series;

  factory TimelineStats.fromJson(Map<String, dynamic> json) {
    final points = (json['points'] as List<dynamic>? ?? const [])
        .map((e) => TimelinePoint.fromJson(e as Map<String, dynamic>))
        .toList();
    final series = (json['series'] as List<dynamic>? ?? const [])
        .map((e) => TimelineSeries.fromJson(e as Map<String, dynamic>))
        .toList();
    return TimelineStats(
      bucket: json['bucket'] as String? ?? 'day',
      points: points,
      series: series.isNotEmpty
          ? series
          : points.isEmpty
          ? const []
          : [TimelineSeries(groupId: 'total', groupName: '合计', points: points)],
    );
  }
}

String formatMoney(int amountCent) {
  final yuan = amountCent ~/ 100;
  final cents = (amountCent % 100).abs().toString().padLeft(2, '0');
  return '¥$yuan.$cents';
}

String formatDateTime(int unixSeconds) {
  final d = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

String formatTimeOnly(int unixSeconds) {
  final d = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}';
}

String formatDateOnly(DateTime date) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

String formatMonthDayYearDate(DateTime date) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(date.month)}-${two(date.day)}-${date.year}';
}

DateTime? parseMonthDayYearDate(String raw) {
  final value = raw.trim();
  final match = RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{4})$').firstMatch(value);
  if (match == null) {
    return null;
  }
  final month = int.parse(match.group(1)!);
  final day = int.parse(match.group(2)!);
  final year = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

String categoryDisplayName(
  List<Category> categories,
  String categoryL1Id,
  String categoryL2Id,
) {
  final topName = _categoryName(categories, categoryL1Id);
  if (categoryL2Id.isEmpty) {
    return topName;
  }
  final childName = _categoryName(categories, categoryL2Id);
  if (childName == categoryL2Id) {
    return topName;
  }
  return '$childName - $topName';
}

String _categoryName(List<Category> categories, String id) {
  for (final category in categories) {
    if (category.id == id) {
      return category.name;
    }
  }
  return id;
}

String transactionDetailLine({
  required String description,
  required String counterparty,
}) {
  return [
    if (description.trim().isNotEmpty) description.trim(),
    if (counterparty.trim().isNotEmpty) counterparty.trim(),
  ].join(' · ');
}

String formatCompactDate(DateTime date) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${date.year}${two(date.month)}${two(date.day)}';
}

DateTime? parseCompactDate(String raw) {
  final value = raw.trim();
  if (!RegExp(r'^\d{8}$').hasMatch(value)) {
    return null;
  }
  final year = int.parse(value.substring(0, 4));
  final month = int.parse(value.substring(4, 6));
  final day = int.parse(value.substring(6, 8));
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

int? parseAmountCent(String raw) {
  final value = raw.trim();
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(value);
  if (match == null) {
    return null;
  }
  final yuan = int.parse(match.group(1)!);
  final centsText = (match.group(2) ?? '').padRight(2, '0');
  final cents = centsText.isEmpty ? 0 : int.parse(centsText);
  final total = yuan * 100 + cents;
  return total > 0 ? total : null;
}
