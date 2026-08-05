import 'package:flutter/material.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../ml_dictionary/widgets/common_widgets.dart';
import '../../ml_dictionary/widgets/sana_card.dart';
import '../models/medication_reminder.dart';
import '../services/medication_reminder_service.dart';

/// İlaç ve ölçüm hatırlatıcıları.
///
/// Uygulama ilaç veya doz ÖNERMEZ; kullanıcı kendi hatırlatmasını kurar.
class MedicationReminderScreen extends StatefulWidget {
  const MedicationReminderScreen({super.key, this.service});

  final MedicationReminderService? service;

  @override
  State<MedicationReminderScreen> createState() =>
      _MedicationReminderScreenState();
}

class _MedicationReminderScreenState extends State<MedicationReminderScreen> {
  late final MedicationReminderService _service =
      widget.service ?? MedicationReminderService();

  List<MedicationReminder> _items = const [];
  bool _loading = true;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _service.load();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openEditor([MedicationReminder? existing]) async {
    final result = await showModalBottomSheet<MedicationReminder>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ReminderEditor(existing: existing),
    );
    if (result == null) return;

    // İzin yalnız ilk kayıtta ve gerçekten gerektiğinde istenir.
    if (result.active) {
      final permission = await NotificationService.instance.requestPermission();
      if (!mounted) return;
      setState(
        () => _permissionDenied = permission == NotificationPermission.denied,
      );
    }

    final items = await _service.save(result);
    if (!mounted) return;
    setState(() => _items = items);
    _notify(
      existing == null ? 'Hatırlatıcı kuruldu' : 'Hatırlatıcı güncellendi',
    );
  }

  Future<void> _toggle(MedicationReminder reminder, bool active) async {
    final items = await _service.save(reminder.copyWith(active: active));
    if (!mounted) return;
    setState(() => _items = items);
  }

  Future<void> _delete(MedicationReminder reminder) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hatırlatıcı silinsin mi?'),
        content: Text(
          '"${reminder.name}" hatırlatıcısı ve bildirimleri kaldırılacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    final items = await _service.delete(reminder.id);
    if (!mounted) return;
    setState(() => _items = items);
    _notify('Hatırlatıcı silindi');
  }

  @override
  Widget build(BuildContext context) {
    final supported = NotificationService.instance.supported;
    return Scaffold(
      appBar: AppBar(title: const Text('İlaç Hatırlatıcı')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add_alarm_rounded),
        label: const Text('Hatırlatıcı ekle'),
      ),
      body: ResponsiveCenter(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: AppSpacing.pagePadding(
                  MediaQuery.sizeOf(context).width,
                ).copyWith(bottom: 96),
                children: [
                  const DisclaimerBox(
                    title: 'Hatırlatma aracıdır, tedavi önerisi değildir',
                    text:
                        'Sana ilaç veya doz önermez. Hatırlatmayı sen kurarsın; '
                        'ilacın, dozun ve saatin doktorunun verdiği bilgilerdir.',
                  ),
                  if (!supported) ...[
                    const SizedBox(height: AppSpacing.md),
                    const DisclaimerBox.attention(
                      title: 'Bu cihazda bildirim gönderilemiyor',
                      text:
                          'Zamanlanmış bildirimler telefonda çalışır. Burada '
                          'hatırlatıcıları kurabilir ve düzenleyebilirsin.',
                    ),
                  ] else if (_permissionDenied) ...[
                    const SizedBox(height: AppSpacing.md),
                    const DisclaimerBox.attention(
                      title: 'Bildirim izni kapalı',
                      text:
                          'Hatırlatıcılar kaydedildi ama bildirim gönderilemez. '
                          'Telefon ayarlarından Sana için bildirimlere izin ver.',
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  if (_items.isEmpty)
                    const SanaStateCard(
                      icon: Icons.alarm_off_outlined,
                      title: 'Henüz hatırlatıcı yok',
                      message:
                          'Düzenli kullandığın bir ilaç veya ölçüm için '
                          'hatırlatma kurabilirsin.',
                    )
                  else
                    for (final item in _items) ...[
                      _ReminderCard(
                        reminder: item,
                        onEdit: () => _openEditor(item),
                        onDelete: () => _delete(item),
                        onToggle: (value) => _toggle(item, value),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                ],
              ),
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.reminder,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final MedicationReminder reminder;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SanaCard(
      onTap: onEdit,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: reminder.active
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
            ),
            child: Icon(
              reminder.active
                  ? Icons.medication_outlined
                  : Icons.notifications_off_outlined,
              size: 22,
              color: reminder.active
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reminder.name,
                  style: AppTextStyles.sectionTitle(context),
                ),
                const SizedBox(height: 2),
                Text(
                  reminder.scheduleLabel,
                  style: AppTextStyles.caption(context),
                ),
                if (reminder.note != null && reminder.note!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      reminder.note!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            children: [
              Switch(value: reminder.active, onChanged: onToggle),
              IconButton(
                tooltip: 'Sil',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Hatırlatıcı ekleme/düzenleme alt sayfası.
class _ReminderEditor extends StatefulWidget {
  const _ReminderEditor({this.existing});

  final MedicationReminder? existing;

  @override
  State<_ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<_ReminderEditor> {
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _noteCtrl = TextEditingController(
    text: widget.existing?.note ?? '',
  );
  late ReminderSchedule _schedule =
      widget.existing?.schedule ?? ReminderSchedule.daily;
  late TimeOfDay _time = TimeOfDay(
    hour: widget.existing?.hour ?? 9,
    minute: widget.existing?.minute ?? 0,
  );
  late int _interval = widget.existing?.intervalHours ?? 8;

  static const List<int> _intervalOptions = [2, 4, 6, 8, 12];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bir ad gir (ör. Tansiyon ilacı)')),
      );
      return;
    }
    final note = _noteCtrl.text.trim();
    Navigator.pop(
      context,
      MedicationReminder(
        id:
            widget.existing?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        note: note.isEmpty ? null : note,
        schedule: _schedule,
        hour: _time.hour,
        minute: _time.minute,
        intervalHours: _interval,
        active: widget.existing?.active ?? true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daily = _schedule == ReminderSchedule.daily;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.existing == null
                    ? 'Hatırlatıcı ekle'
                    : 'Hatırlatıcıyı düzenle',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Ad',
                  hintText: 'ör. Tansiyon ilacı',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _noteCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Not (isteğe bağlı)',
                  hintText: 'ör. 1 tablet, tok karnına',
                  helperText: 'Doktorunun verdiği bilgiyi kendin yazarsın.',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Sıklık', style: AppTextStyles.sectionTitle(context)),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<ReminderSchedule>(
                segments: const [
                  ButtonSegment(
                    value: ReminderSchedule.daily,
                    label: Text('Günlük'),
                    icon: Icon(Icons.today_outlined),
                  ),
                  ButtonSegment(
                    value: ReminderSchedule.everyNHours,
                    label: Text('Saat aralıklı'),
                    icon: Icon(Icons.timelapse_outlined),
                  ),
                ],
                selected: {_schedule},
                onSelectionChanged: (value) =>
                    setState(() => _schedule = value.first),
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule_outlined),
                label: Text(
                  daily
                      ? 'Saat: ${_time.format(context)}'
                      : 'Başlangıç: ${_time.format(context)}',
                ),
              ),
              if (!daily) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Kaç saatte bir?',
                  style: AppTextStyles.sectionTitle(context),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final option in _intervalOptions)
                      ChoiceChip(
                        label: Text('$option saat'),
                        selected: _interval == option,
                        onSelected: (_) => setState(() => _interval = option),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Günde ${(24 / _interval).floor()} kez hatırlatılır.',
                  style: AppTextStyles.caption(context),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              SanaPrimaryButton(
                label: 'Kaydet',
                icon: Icons.check_rounded,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
