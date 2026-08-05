import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/settings/app_settings_controller.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/report_parse_models.dart';
import '../services/report_history_service.dart';
import '../services/report_pdf_service.dart';
import '../widgets/common_widgets.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    this.controller,
    this.historyService,
    this.pdfService,
  });

  final AppSettingsController? controller;
  final ReportHistoryService? historyService;
  final ReportPdfService? pdfService;

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
                'Raporlarım',
                style: AppTextStyles.sectionTitle(context),
              ),
              const SizedBox(height: AppSpacing.sm),
              _HistoryBackupTiles(
                service: historyService,
                pdfService: pdfService,
              ),
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
  const _HistoryBackupTiles({this.service, this.pdfService});

  final ReportHistoryService? service;
  final ReportPdfService? pdfService;

  @override
  State<_HistoryBackupTiles> createState() => _HistoryBackupTilesState();
}

class _HistoryBackupTilesState extends State<_HistoryBackupTiles> {
  late final ReportHistoryService _service =
      widget.service ?? ReportHistoryService();
  late final ReportPdfService _pdfService =
      widget.pdfService ?? ReportPdfService();
  bool _busy = false;

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _fileName({required String extension, String? slug}) {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)}';
    final middle = (slug == null || slug.isEmpty) ? '' : '-$slug';
    return 'sana-rapor-ozeti$middle-$stamp.$extension';
  }

  /// Doktora gösterilebilecek okunur PDF. JSON yedeğinden farklı olarak geri
  /// yüklenemez; amacı paylaşmak ve arşivlemek.
  ///
  /// Kullanıcı tek raporu mu yoksa tüm geçmişi mi aktaracağını seçer:
  /// doktora genelde tek rapor gösterilir, arşiv için tümü istenir.
  Future<void> _exportPdf() async {
    setState(() => _busy = true);
    List<ReportHistoryEntry> entries;
    try {
      entries = await _service.load();
    } catch (_) {
      entries = const [];
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;

    if (entries.isEmpty) {
      _notify('Dışa aktarılacak rapor bulunamadı.');
      return;
    }

    final selection = await showDialog<_PdfSelection>(
      context: context,
      builder: (_) => _ReportPickerDialog(entries: entries),
    );
    if (selection == null || !mounted) return;

    final approved = await _confirm(
      title: 'Rapor özeti oluştur',
      message:
          '${selection.summary} okunabilir bir PDF belgesine yazılacak ve '
          'seçtiğin konuma kaydedilecek. Doktoruna gösterebilir veya '
          'arşivleyebilirsin.\n\n'
          'Belge sağlık verini içerir ve uygulamanın korumalı alanının dışına '
          'çıkar. Nereye kaydettiğine ve kimlerle paylaştığına dikkat et.\n\n'
          'Uygulama bu belgenin kopyasını kendi içinde saklamaz.',
    );
    if (approved != true || !mounted) return;

    setState(() => _busy = true);
    try {
      // Belge üretimi senkron ve CPU'ya bağlı; web'de tek iş parçacığı var.
      // Bir kare beklemek göstergenin çizilmesini garantiler, aksi hâlde
      // uygulama donmuş görünür.
      await Future<void>.delayed(Duration.zero);
      final bytes = await _pdfService.build(selection.entries);
      final path = await FilePicker.saveFile(
        dialogTitle: 'Rapor özetini kaydet',
        fileName: _fileName(extension: 'pdf', slug: selection.slug),
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: bytes,
      );
      _notify(_savedMessage(path, 'Rapor özeti'));
    } on ReportPdfEmptyException catch (error) {
      _notify(error.message);
    } catch (error) {
      _notify('Rapor özeti oluşturulamadı: ${_shortError(error)}');
    } finally {
      await _clearTemporaryFiles();
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Kaydetme sonucunu mesaja çevirir.
  ///
  /// Web'de `saveFile` indirmeyi başlatır ve **başarıda da `null` döner**;
  /// iptal ile başarıyı ayırt etmez. Bu yüzden web'de `null` "iptal" sayılamaz,
  /// yoksa dosya inmiş olmasına rağmen "iptal edildi" yazardı.
  String _savedMessage(String? path, String what) {
    if (kIsWeb) return '$what indirildi.';
    return path == null ? '$what oluşturma iptal edildi.' : '$what kaydedildi.';
  }

  /// Hata metnini kullanıcıya gösterilebilecek uzunlukta kısaltır.
  String _shortError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > 140 ? '${text.substring(0, 140)}…' : text;
  }

  Future<bool?> _confirm({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
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
  }

  Future<void> _export() async {
    final approved = await _confirm(
      title: 'Geçmişi yedekle',
      message:
          'Rapor geçmişin bir JSON yedek dosyasına yazılacak ve seçtiğin '
          'konuma kaydedilecek. Bu dosya "Yedekten geri yükle" ile okunur; '
          'okumak için değil, taşımak içindir.\n\n'
          'Dosya sağlık verini içerir ve uygulamanın korumalı alanının '
          'dışına çıkar. Nereye kaydettiğine ve kimlerle paylaştığına dikkat '
          'et.\n\n'
          'Uygulama bu dosyanın kopyasını kendi içinde saklamaz.',
    );
    if (approved != true) return;

    setState(() => _busy = true);
    try {
      final json = await _service.exportJson();
      final bytes = Uint8List.fromList(utf8.encode(json));
      final path = await FilePicker.saveFile(
        dialogTitle: 'Rapor geçmişi yedeğini kaydet',
        fileName: _fileName(extension: 'json'),
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );
      _notify(_savedMessage(path, 'Yedek'));
    } catch (error) {
      _notify('Yedekleme tamamlanamadı: ${_shortError(error)}');
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
        // Paylaşmak için okunur çıktı, yedeklemekten önce gelir: kullanıcıların
        // çoğu "dışa aktar" derken doktoruna gösterebileceği bir belge arıyor.
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: const Text('Rapor özeti oluştur (PDF)'),
          subtitle: const Text(
            'Tek rapor ya da tüm geçmiş. Doktoruna gösterebileceğin belge.',
          ),
          trailing: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          onTap: _busy ? null : _exportPdf,
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.file_upload_outlined),
          title: const Text('Geçmişi yedekle (JSON)'),
          subtitle: const Text(
            'Telefon değiştirince geri yüklemek için. Okunacak belge değildir.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy ? null : _export,
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: const Text('Yedekten geri yükle'),
          subtitle: const Text(
            'Daha önce kaydettiğin JSON yedeğinden yükle. Mevcut raporlar silinmez.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy ? null : _import,
        ),
      ],
    );
  }
}

/// Kullanıcının PDF için seçtiği kapsam.
class _PdfSelection {
  const _PdfSelection({
    required this.entries,
    required this.summary,
    this.slug,
  });

  final List<ReportHistoryEntry> entries;

  /// Onay metninde geçen kapsam ifadesi.
  final String summary;

  /// Dosya adına eklenen ek; tüm geçmişte null.
  final String? slug;
}

/// "Tek rapor mu, tüm geçmiş mi" seçimi.
///
/// Doktora genelde tek rapor gösterilir; arşivlemek isteyen tümünü alır.
/// Seçim durumu diyaloğun kendisinde tutulur — kapanış animasyonu sürerken
/// dışarıdaki state'e dokunulmaz.
class _ReportPickerDialog extends StatefulWidget {
  const _ReportPickerDialog({required this.entries});

  final List<ReportHistoryEntry> entries;

  @override
  State<_ReportPickerDialog> createState() => _ReportPickerDialogState();
}

class _ReportPickerDialogState extends State<_ReportPickerDialog> {
  /// Tüm geçmiş için `null`, tek rapor için o raporun kimliği.
  String? _selectedId;

  /// Türkçe karakterleri dosya adında güvenli karşılıklarına indirger.
  String _slugify(String value) {
    const map = {
      'ç': 'c',
      'Ç': 'c',
      'ğ': 'g',
      'Ğ': 'g',
      'ı': 'i',
      'İ': 'i',
      'ö': 'o',
      'Ö': 'o',
      'ş': 's',
      'Ş': 's',
      'ü': 'u',
      'Ü': 'u',
    };
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(map[char] ?? char);
    }
    final slug = buffer
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.length > 32 ? slug.substring(0, 32) : slug;
  }

  void _submit() {
    final id = _selectedId;
    if (id == null) {
      Navigator.pop(
        context,
        _PdfSelection(
          entries: widget.entries,
          summary: 'Tüm raporların (${widget.entries.length})',
        ),
      );
      return;
    }
    final entry = widget.entries.firstWhere((item) => item.id == id);
    Navigator.pop(
      context,
      _PdfSelection(
        entries: [entry],
        summary: '"${entry.displayName}" raporu',
        slug: _slugify(entry.displayName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget option({
      required String? id,
      required String title,
      required String subtitle,
      required IconData icon,
    }) {
      final selected = _selectedId == id;
      return ListTile(
        leading: Icon(icon, color: selected ? scheme.primary : null),
        title: Text(title),
        subtitle: Text(subtitle),
        selected: selected,
        trailing: selected
            ? Icon(Icons.check_circle, color: scheme.primary)
            : null,
        onTap: () => setState(() => _selectedId = id),
      );
    }

    return AlertDialog(
      title: const Text('Hangi raporlar?'),
      contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      content: SizedBox(
        width: 340,
        child: ListView(
          shrinkWrap: true,
          children: [
            option(
              id: null,
              title: 'Tüm raporlar',
              subtitle: '${widget.entries.length} rapor tek belgede',
              icon: Icons.library_books_outlined,
            ),
            const Divider(height: 1),
            for (final entry in widget.entries)
              option(
                id: entry.id,
                title: entry.displayName,
                subtitle: formatReportDate(entry.reportDate ?? entry.createdAt),
                icon: Icons.description_outlined,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Devam et')),
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
