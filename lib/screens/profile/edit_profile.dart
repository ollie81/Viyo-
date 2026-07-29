import 'package:flutter/material.dart';
import '../../models/user_profile.dart';
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';

class EditProfileScreen extends StatefulWidget {
  final UserProfile profile;
  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final _displayName = TextEditingController(text: widget.profile.displayName);
  late final _bio = TextEditingController(text: widget.profile.bio);
  late final _niche = TextEditingController(text: widget.profile.niche);
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ProfileService.updateProfile(
        userId: widget.profile.id,
        displayName: _displayName.text.trim(),
        bio: _bio.text.trim(),
        niche: _niche.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Edit Profile')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _displayName,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Display name', labelStyle: TextStyle(color: AppColors.textSecondary)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _bio,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Bio', labelStyle: TextStyle(color: AppColors.textSecondary)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _niche,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Creator niche',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                hintText: 'e.g. travel, fitness, comedy',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}
