import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ledger_client/src/app_controller.dart';
import 'package:ledger_client/src/models.dart';
import 'package:ledger_client/src/widgets/responsive_layout.dart';

class TransactionFormPage extends StatefulWidget {
  const TransactionFormPage({
    super.key,
    required this.controller,
    this.transaction,
  });

  final AppController controller;
  final LedgerTransaction? transaction;

  @override
  State<TransactionFormPage> createState() => _TransactionFormPageState();
}

class _TransactionFormPageState extends State<TransactionFormPage> {
  final formKey = GlobalKey<FormState>();
  final ImagePicker imagePicker = ImagePicker();
  late final TextEditingController amountController;
  late final TextEditingController counterpartyController;
  late final TextEditingController descriptionController;
  late String direction;
  String? categoryL1Id;
  String? categoryL2Id;
  late String memberId;
  late String accountId;
  late DateTime transactionTime;
  bool submitting = false;
  bool loadingAttachments = false;
  bool uploadingPhotos = false;
  String? error;
  final List<XFile> pendingPhotos = [];
  List<AttachmentMeta> attachments = [];
  final Map<String, Uint8List> thumbnails = {};
  bool attachmentsChanged = false;

  bool get editing => widget.transaction != null;
  bool get supportsCamera =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    final bootstrap = widget.controller.bootstrapData!;
    final item = widget.transaction;
    direction = item?.direction ?? 'expense';
    categoryL1Id =
        item?.categoryL1Id ?? _topCategories(bootstrap).firstOrNull?.id;
    categoryL2Id = item?.categoryL2Id;
    memberId = item?.memberId ?? bootstrap.members.first.id;
    accountId = item?.accountId ?? bootstrap.accounts.first.id;
    transactionTime = item == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(item.transactionTime * 1000);
    amountController = TextEditingController(
      text: item == null ? '' : (item.amountCent / 100).toStringAsFixed(2),
    );
    counterpartyController = TextEditingController(
      text: item?.counterparty ?? '',
    );
    descriptionController = TextEditingController(
      text: item?.description ?? '',
    );
    if (item != null) {
      _loadAttachments(item.id);
    }
  }

  @override
  void dispose() {
    amountController.dispose();
    counterpartyController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = widget.controller.bootstrapData!;
    final topCategories = _topCategories(bootstrap);
    final childCategories = bootstrap.categories
        .where((c) => c.parentId == categoryL1Id && c.type == direction)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? '编辑交易' : '新增交易'),
        leading: IconButton(
          tooltip: '返回',
          onPressed: () => Navigator.of(context).pop(attachmentsChanged),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          if (editing)
            IconButton(
              tooltip: '删除',
              onPressed: submitting ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: formKey,
        child: ResponsiveListView(
          maxWidth: kFormMaxWidth,
          children: [
            ResponsiveFieldGrid(
              children: [
                TextFormField(
                  controller: amountController,
                  decoration: const InputDecoration(labelText: '金额 RMB'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) => parseAmountCent(value ?? '') == null
                      ? '请输入正数金额，最多两位小数'
                      : null,
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('form-direction-$direction'),
                  initialValue: direction,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '方向'),
                  items: const [
                    DropdownMenuItem(value: 'expense', child: Text('支出')),
                    DropdownMenuItem(value: 'income', child: Text('收入')),
                    DropdownMenuItem(value: 'transfer', child: Text('转账')),
                  ],
                  onChanged: submitting
                      ? null
                      : (value) {
                          setState(() {
                            direction = value!;
                            categoryL1Id = _topCategories(
                              bootstrap,
                            ).firstOrNull?.id;
                            categoryL2Id = null;
                          });
                        },
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('form-l1-$direction-$categoryL1Id'),
                  initialValue: categoryL1Id,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '一级分类'),
                  items: topCategories
                      .map(
                        (c) =>
                            DropdownMenuItem(value: c.id, child: Text(c.name)),
                      )
                      .toList(),
                  onChanged: submitting
                      ? null
                      : (value) {
                          setState(() {
                            categoryL1Id = value;
                            categoryL2Id = null;
                          });
                        },
                ),
                DropdownButtonFormField<String?>(
                  key: ValueKey('form-l2-$categoryL1Id-$categoryL2Id'),
                  initialValue: categoryL2Id?.isEmpty == true
                      ? null
                      : categoryL2Id,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '二级分类'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('不选择'),
                    ),
                    ...childCategories.map(
                      (c) => DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text(c.name),
                      ),
                    ),
                  ],
                  onChanged: submitting
                      ? null
                      : (value) => setState(() => categoryL2Id = value),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('form-member-$memberId'),
                  initialValue: memberId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '使用人'),
                  items: bootstrap.members
                      .map(
                        (m) =>
                            DropdownMenuItem(value: m.id, child: Text(m.name)),
                      )
                      .toList(),
                  onChanged: submitting
                      ? null
                      : (value) => setState(() => memberId = value!),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('form-account-$accountId'),
                  initialValue: accountId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '账户'),
                  items: bootstrap.accounts
                      .map(
                        (a) => DropdownMenuItem(
                          value: a.id,
                          child: Text(a.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: submitting
                      ? null
                      : (value) => setState(() => accountId = value!),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: submitting ? null : _pickDateTime,
              icon: const Icon(Icons.schedule),
              label: Text(
                formatDateTime(transactionTime.millisecondsSinceEpoch ~/ 1000),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: counterpartyController,
              decoration: const InputDecoration(labelText: '交易对象'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: '详细描述'),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            _PhotoSection(
              attachments: attachments,
              thumbnails: thumbnails,
              pendingPhotos: pendingPhotos,
              loading: loadingAttachments,
              uploading: uploadingPhotos,
              supportsCamera: supportsCamera,
              uploadImmediately: editing,
              onPickGallery: submitting
                  ? null
                  : () => _pickPhoto(ImageSource.gallery),
              onPickCamera: submitting || !supportsCamera
                  ? null
                  : () => _pickPhoto(ImageSource.camera),
              onRemovePending: submitting
                  ? null
                  : (index) => setState(() => pendingPhotos.removeAt(index)),
              onOpenAttachment: _openAttachment,
              onDeleteAttachment: _deleteAttachment,
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: submitting ? null : _submit,
              icon: Icon(editing ? Icons.save : Icons.add),
              label: Text(editing ? '保存修改' : '新增交易'),
            ),
          ],
        ),
      ),
    );
  }

  List<Category> _topCategories(BootstrapData bootstrap) {
    return bootstrap.categories
        .where((c) => c.isTopLevel && c.type == direction)
        .toList();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: transactionTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(transactionTime),
    );
    if (time == null) {
      return;
    }
    setState(() {
      transactionTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (!formKey.currentState!.validate()) {
      return;
    }
    final token = widget.controller.token;
    if (token == null) {
      setState(() => error = '当前无网络，请联网后重试');
      return;
    }
    final body = <String, dynamic>{
      'amount_cent': parseAmountCent(amountController.text)!,
      'currency': 'CNY',
      'direction': direction,
      'transaction_time': transactionTime.millisecondsSinceEpoch ~/ 1000,
      'category_l1_id': categoryL1Id,
      'category_l2_id': categoryL2Id,
      'member_id': memberId,
      'account_id': accountId,
      'counterparty': counterpartyController.text.trim(),
      'description': descriptionController.text.trim(),
    };
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      late final LedgerTransaction saved;
      if (editing) {
        saved = await widget.controller.api.patchTransaction(
          token,
          widget.transaction!.id,
          body,
        );
      } else {
        saved = await widget.controller.api.createTransaction(token, body);
      }
      if (pendingPhotos.isNotEmpty) {
        await _uploadPendingPhotos(token, saved.id);
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => submitting = false);
      }
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await imagePicker.pickImage(
        source: source,
        requestFullMetadata: false,
      );
      if (file == null) {
        return;
      }
      final maxBytes =
          widget.controller.bootstrapData?.maxUploadSizeBytes ??
          20 * 1024 * 1024;
      final size = await file.length();
      if (size > maxBytes) {
        setState(() => error = '图片超过上传上限');
        return;
      }
      if (editing) {
        await _uploadExistingTransactionPhoto(file);
        return;
      }
      setState(() {
        pendingPhotos.add(file);
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    }
  }

  Future<void> _uploadExistingTransactionPhoto(XFile photo) async {
    final token = widget.controller.token;
    if (token == null || widget.transaction == null) {
      setState(() => error = '当前无网络，请联网后重试');
      return;
    }
    setState(() {
      uploadingPhotos = true;
      error = null;
    });
    try {
      final bytes = await photo.readAsBytes();
      await widget.controller.api.uploadAttachment(
        token,
        transactionId: widget.transaction!.id,
        bytes: bytes,
        fileName: photo.name.isEmpty ? 'receipt.jpg' : photo.name,
      );
      attachmentsChanged = true;
      await _loadAttachments(widget.transaction!.id);
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => uploadingPhotos = false);
      }
    }
  }

  Future<void> _uploadPendingPhotos(String token, String transactionId) async {
    setState(() {
      uploadingPhotos = true;
      error = null;
    });
    try {
      for (final photo in List<XFile>.from(pendingPhotos)) {
        final bytes = await photo.readAsBytes();
        await widget.controller.api.uploadAttachment(
          token,
          transactionId: transactionId,
          bytes: bytes,
          fileName: photo.name.isEmpty ? 'receipt.jpg' : photo.name,
        );
      }
      attachmentsChanged = true;
      pendingPhotos.clear();
    } finally {
      if (mounted) {
        setState(() => uploadingPhotos = false);
      }
    }
  }

  Future<void> _loadAttachments(String transactionId) async {
    final token = widget.controller.token;
    if (token == null) {
      return;
    }
    setState(() => loadingAttachments = true);
    try {
      final items = await widget.controller.api.listAttachments(
        token,
        transactionId,
      );
      final loaded = <String, Uint8List>{};
      for (final item in items) {
        loaded[item.id] = await widget.controller.api.attachmentBytes(
          token,
          item.id,
          thumbnail: true,
        );
      }
      if (mounted) {
        setState(() {
          attachments = items;
          thumbnails
            ..clear()
            ..addAll(loaded);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => loadingAttachments = false);
      }
    }
  }

  Future<void> _deleteAttachment(AttachmentMeta attachment) async {
    final token = widget.controller.token;
    if (token == null) {
      setState(() => error = '当前无网络，请联网后重试');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除照片'),
        content: const Text('照片会从当前交易中移除，服务端保留软删除记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    setState(() {
      loadingAttachments = true;
      error = null;
    });
    try {
      await widget.controller.api.deleteAttachment(token, attachment.id);
      attachmentsChanged = true;
      if (mounted) {
        setState(() {
          attachments.removeWhere((item) => item.id == attachment.id);
          thumbnails.remove(attachment.id);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => loadingAttachments = false);
      }
    }
  }

  Future<void> _openAttachment(AttachmentMeta attachment) async {
    final token = widget.controller.token;
    if (token == null) {
      setState(() => error = '当前无网络，请联网后重试');
      return;
    }
    final imageFuture = widget.controller.api.attachmentBytes(
      token,
      attachment.id,
    );
    await showDialog<void>(
      context: context,
      builder: (_) => _AttachmentPreviewDialog(
        title: attachment.originalFileName.isEmpty
            ? '照片'
            : attachment.originalFileName,
        imageFuture: imageFuture,
      ),
    );
  }

  Future<void> _delete() async {
    final token = widget.controller.token;
    if (token == null || widget.transaction == null) {
      return;
    }
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      await widget.controller.api.deleteTransaction(
        token,
        widget.transaction!.id,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => submitting = false);
      }
    }
  }
}

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.attachments,
    required this.thumbnails,
    required this.pendingPhotos,
    required this.loading,
    required this.uploading,
    required this.supportsCamera,
    required this.uploadImmediately,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onRemovePending,
    required this.onOpenAttachment,
    required this.onDeleteAttachment,
  });

  final List<AttachmentMeta> attachments;
  final Map<String, Uint8List> thumbnails;
  final List<XFile> pendingPhotos;
  final bool loading;
  final bool uploading;
  final bool supportsCamera;
  final bool uploadImmediately;
  final VoidCallback? onPickGallery;
  final VoidCallback? onPickCamera;
  final ValueChanged<int>? onRemovePending;
  final ValueChanged<AttachmentMeta> onOpenAttachment;
  final ValueChanged<AttachmentMeta> onDeleteAttachment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('照片', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (supportsCamera)
              OutlinedButton.icon(
                onPressed: onPickCamera,
                icon: const Icon(Icons.photo_camera),
                label: const Text('拍照'),
              ),
            OutlinedButton.icon(
              onPressed: onPickGallery,
              icon: const Icon(Icons.photo_library),
              label: Text(kIsWeb ? '选择图片' : '相册'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          uploadImmediately ? '选择图片后会立即上传。' : '选择图片后，保存交易时上传。',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (loading || uploading)
          const LinearProgressIndicator()
        else if (attachments.isEmpty && pendingPhotos.isEmpty)
          Text('暂无照片', style: theme.textTheme.bodyMedium)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...attachments.map(
                (item) => _AttachmentThumb(
                  attachment: item,
                  bytes: thumbnails[item.id],
                  onTap: () => onOpenAttachment(item),
                  onDelete: () => onDeleteAttachment(item),
                ),
              ),
              for (var i = 0; i < pendingPhotos.length; i++)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: InputChip(
                    avatar: const Icon(Icons.image),
                    label: Text(
                      pendingPhotos[i].name.isEmpty
                          ? '待上传照片（保存后上传）'
                          : '${pendingPhotos[i].name}（保存后上传）',
                      overflow: TextOverflow.ellipsis,
                    ),
                    onDeleted: onRemovePending == null
                        ? null
                        : () => onRemovePending!(i),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({
    required this.attachment,
    required this.bytes,
    required this.onTap,
    required this.onDelete,
  });

  final AttachmentMeta attachment;
  final Uint8List? bytes;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: Semantics(
        button: true,
        label: '查看照片',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                GestureDetector(
                  onTap: onTap,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: bytes == null
                          ? ColoredBox(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.image),
                            )
                          : Image.memory(
                              bytes!,
                              fit: BoxFit.cover,
                              alignment: Alignment.center,
                            ),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: '删除照片',
                      onPressed: onDelete,
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 16,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: onTap,
              child: Text(
                attachment.originalFileName.isEmpty
                    ? '照片'
                    : attachment.originalFileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentPreviewDialog extends StatelessWidget {
  const _AttachmentPreviewDialog({
    required this.title,
    required this.imageFuture,
  });

  final String title;
  final Future<Uint8List> imageFuture;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - 32).clamp(280.0, 960.0).toDouble();
    final height = (size.height - 64).clamp(320.0, 720.0).toDouble();
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<Uint8List>(
                future: imageFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return Center(
                      child: Text(
                        '图片读取失败',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    );
                  }
                  return ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: InteractiveViewer(
                      boundaryMargin: const EdgeInsets.all(80),
                      minScale: 1,
                      maxScale: 5,
                      child: Center(
                        child: Image.memory(
                          snapshot.data!,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
