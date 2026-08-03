import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/settings/app_settings_controller.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../services/report_history_service.dart';
import '../widgets/common_widgets.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.controller, this.historyService});

  final AppSettingsController? controller;
  final ReportHistoryService? historyService;

  @override
  Widget build(BuildContext context) {
    final settings = controller ?? AppSettingsController.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ResponsiveCenter(
        child: AnimatedBuilder(
          animation: settings,
          builder: (context, _) => ListView(
            padding: AppSpacing.pagePadding(
              MediaQuery.sizeOf(context).width,
            ).copyWith(bottom: 32),
            children: [
              Text('Profil', style: AppTextStyles.sectionTitle(context)),
              const SizedBox(height: AppSpacing.sm),
              _SettingsSurface(
                children: [
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('Sağlık profili'),
                    subtitle: const Text(
                      'İsteğe bağlı yaş ve biyolojik cinsiyet bilgisini yönet.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProfileScreen(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text('Görünüm', style: AppTextStyles.sectionTitle(context)),
              const SizedBox(height: AppSpacing.sm),
              _SettingsSurface(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.dark_mode_outlined),
                    title: const Text('Koyu tema'),
                    subtitle: const Text(
                      'Düşük ışıkta daha rahat bir görünüm kullanır.',
                    ),
                    value: settings.darkMode,
                    onChanged: settings.setDarkMode,
                  ),
                  const Divider(),
                  SwitchListTile(
                    secondary: const Icon(Icons.text_increase_outlined),
                    title: const Text('Büyük yazı'),
                    subtitle: const Text(
                      'Metinleri sistem ayarına ek olarak büyütür.',
                    ),
                    value: settings.largeText,
                    onChanged: settings.setLargeText,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                'Rapor geçmişi yedeği',
                style: AppTextStyles.sectionTitle(context),
              ),
              const SizedBox(height: AppSpacing.sm),
              _HistoryBackupTiles(service: historyService),
              const SizedBox(height: 28),
              Text('Gizlilik', style: AppTextStyles.sectionTitle(context)),
              const SizedBox(height: AppSpacing.sm),
              const _SettingsSurface(
                children: [
                  ListTile(
                    leading: Icon(Icons.devices_outlined),
                    title: Text('Yerel veri'),
                    subtitle: Text(
                      'Favoriler, görünüm ayarları ve rapor geçmişi bu cihazdaki uygulama alanında tutulur.',
                    ),
                  ),
                  Divider(),
                  ListTile(
                    leading: Icon(Icons.health_and_safety_outlined),
                    title: Text('Güvenli açıklamalar'),
                    subtitle: Text(
                      'Sana tanı koymaz; ilaç, doz, takviye veya tedavi önermez.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rapor geçmişini dosyaya aktarma ve dosyadan geri yükleme.
///
/// Dosya yalnız kullanıcının seçtiği konuma yazılır; uygulama kendi alanında
/// kopya tutmaz. Geri yüklemede dosya bellekte okunur ve platformun bıraktığı
/// geçici kopya hemen temizlenir.
class _HistoryBackupTiles extends StatefulWidget {
  const _HistoryBackupTiles({this.service});

  final ReportHistoryService? service;

  @override
  State<_HistoryBackupTiles> createState() => _HistoryBackupTilesState();
}

class _HistoryBackupTilesState extends State<_HistoryBackupTiles> {
  late final ReportHistoryService _service =
      widget.service ?? ReportHistoryService();
  bool _busy = false;

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _fileName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'sana-rapor-gecmisi-${now.year}-${two(now.month)}-${two(now.day)}.json';
  }

  Future<void> _export() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Geçmişi dışa aktar'),
        content: const Text(
          'Rapor geçmişin bir JSON dosyasına yazılacak ve seçtiğin konuma '
          'kaydedilecek.\n\n'
          'Bu dosya sağlık verini içerir ve uygulamanın korumalı alanının '
          'dışına çıkar. Nereye kaydettiğine ve kimlerle paylaştığına dikkat '
          'et.\n\n'
          'Uygulama bu dosyanın kopyasını kendi içinde saklamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Devam et'),
          ),
        ],
      ),
    );
    if (approved != true) return;

    setState(() => _busy = true);
    try {
      final json = await _service.exportJson();
      final bytes = Uint8List.fromList(utf8.encode(json));
      final path = await FilePicker.saveFile(
        dialogTitle: 'Rapor geçmişini kaydet',
        fileName: _fileName(),
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );
      if (path == null) {
        _notify('Dışa aktarma iptal edildi.');
      } else {
        _notify('Rapor geçmişi kaydedildi.');
      }
    } catch (_) {
      _notify('Dışa aktarma tamamlanamadı.');
    } finally {
      // Platformun bıraktığı geçici kopyalar uygulamada birikmesin.
      await _clearTemporaryFiles();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: 'Rapor geçmişi dosyası seç',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
        allowMultiple: false,
      );
      if (picked == null || picked.files.isEmpty) {
        _notify('Geri yükleme iptal edildi.');
        return;
      }
      final bytes = picked.files.single.bytes;
      if (bytes == null) {
        _notify('Dosya okunamadı.');
        return;
      }
      final result = await _service.importJson(utf8.decode(bytes));
      final parts = <String>['${result.added} rapor eklendi'];
      if (result.duplicate > 0) {
        parts.add('${result.duplicate} kayıt zaten vardı');
      }
      if (result.skipped > 0) {
        parts.add('${result.skipped} kayıt okunamadı');
      }
      _notify('${parts.join(', ')}.');
    } on HistoryImportException catch (error) {
      _notify(error.message);
    } catch (_) {
      _notify('Geri yükleme tamamlanamadı.');
    } finally {
      await _clearTemporaryFiles();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearTemporaryFiles() async {
    if (kIsWeb) return;
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (_) {
      // Temizlik yapılamazsa akış bozulmaz.
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsSurface(
      children: [
        ListTile(
          leading: const Icon(Icons.file_upload_outlined),
          title: const Text('Geçmişi dışa aktar'),
          subtitle: const Text(
            'Raporlarını JSON dosyası olarak kaydet. Uygulama kopya tutmaz.',
          ),
          trailing: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          onTap: _busy ? null : _export,
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: const Text('Geçmişi geri yükle'),
          subtitle: const Text(
            'Daha önce kaydettiğin dosyadan yükle. Mevcut raporlar silinmez.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy ? null : _import,
        ),
      ],
    );
  }
}

class _SettingsSurface extends StatelessWidget {
  const _SettingsSurface({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: children),
    );
  }
}
