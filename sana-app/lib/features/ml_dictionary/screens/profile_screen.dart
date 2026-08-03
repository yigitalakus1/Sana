import 'package:flutter/material.dart';

import '../../../core/profile/user_profile_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../widgets/common_widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.service});

  final UserProfileService? service;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final UserProfileService _service =
      widget.service ?? UserProfileService();
  final TextEditingController _ageController = TextEditingController();
  String? _sex;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await _service.load();
    if (!mounted) return;
    setState(() {
      _ageController.text = profile.age?.toString() ?? '';
      _sex = profile.sex;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final ageText = _ageController.text.trim();
    final age = ageText.isEmpty ? null : int.tryParse(ageText);
    if (ageText.isNotEmpty && (age == null || age < 0 || age > 120)) {
      setState(() => _error = 'Yaş 0 ile 120 arasında olmalıdır.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.save(UserProfile(age: age, sex: _sex));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil bu cihazda kaydedildi.')),
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'Profil kaydedilemedi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    await _service.clear();
    if (!mounted) return;
    setState(() {
      _ageController.clear();
      _sex = null;
      _error = null;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Profil bilgileri silindi.')));
  }

  @override
  void dispose() {
    _ageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Sağlık Profili')),
      body: ResponsiveCenter(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: AppSpacing.pagePadding(
                  MediaQuery.sizeOf(context).width,
                ).copyWith(bottom: 32),
                children: [
                  Text(
                    'İsteğe bağlı bilgiler',
                    style: AppTextStyles.sectionTitle(context),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Bu bilgiler açıklamaların yaş ve biyolojik bağlama uygun '
                    'olmasına yardımcı olur. Tanı veya tedavi amacıyla kullanılmaz.',
                    style: AppTextStyles.muted(context),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        TextField(
                          key: const ValueKey('profile-age'),
                          controller: _ageController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Yaş',
                            hintText: 'Örn: 34',
                            prefixIcon: Icon(Icons.cake_outlined),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        DropdownButtonFormField<String>(
                          key: const ValueKey('profile-sex'),
                          initialValue: _sex,
                          decoration: const InputDecoration(
                            labelText: 'Biyolojik cinsiyet',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'female',
                              child: Text('Kadın'),
                            ),
                            DropdownMenuItem(
                              value: 'male',
                              child: Text('Erkek'),
                            ),
                            DropdownMenuItem(
                              value: 'other',
                              child: Text('Diğer / belirtmek istemiyorum'),
                            ),
                          ],
                          onChanged: (value) => setState(() => _sex = value),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          ErrorBox(message: _error!),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _saving ? null : _clear,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Bilgileri sil'),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _saving ? null : _save,
                                icon: _saving
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save_outlined),
                                label: const Text('Kaydet'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.lock_outline),
                    title: Text('Yalnızca bu cihazda'),
                    subtitle: Text(
                      'Profil bilgileri uygulamanın yerel alanında saklanır ve '
                      'istediğin zaman silinebilir.',
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
