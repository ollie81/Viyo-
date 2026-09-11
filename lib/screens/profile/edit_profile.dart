import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../constants/supabase_constants.dart';
import '../../models/user_profile.dart';
import '../../services/profile_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  bool _uploadingAvatar = false;
  File? _pickedAvatar;
  String? _error;

  Future<void> _pickAvatar() async {
    setState(() => _error = null);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() => _pickedAvatar = File(picked.path));
      }
    } catch (e) {
      // Real error shown to the user instead of silently doing nothing —
      // this is almost always a missing gallery/photos permission on the
      // device, or the permission being denied.
      setState(() => _error = 'Could not open photo picker: $e');
    }
  }

  /// Uploads the picked photo and returns its public URL.
  ///
  /// Profile pictures were silently impossible: the `avatars` bucket was
  /// never created in Supabase, so every upload failed against a bucket
  /// that isn't there. Probing it returns the same "Bucket not found"
  /// response as a name that was never used at all, while `posts-media`
  /// answers normally.
  ///
  /// So this tries `avatars` first — it's the right home, and running
  /// avatars_bucket.sql makes it work — and falls back to a folder
  /// inside the posts bucket, which demonstrably exists. The fallback
  /// path keeps the same "<user_id>/..." shape the posts bucket's
  /// policy already allows, so it needs no new policy either. Net
  /// effect: photos work now, and quietly move to the proper bucket the
  /// moment it exists.
  Future<String?> _uploadAvatarIfNeeded() async {
    if (_pickedAvatar == null) return null;
    setState(() => _uploadingAvatar = true);

    final client = SupabaseService.client;
    final ext = _pickedAvatar!.path.split('.').last;

    // Cache-busting name: the same URL with new bytes behind it would
    // keep showing the old photo out of Flutter's image cache.
    final stamp = DateTime.now().millisecondsSinceEpoch;

    final attempts = <MapEntry<String, String>>[
      MapEntry(
        SupabaseConstants.avatarsBucket,
        '${widget.profile.id}/avatar_$stamp.$ext',
      ),
      MapEntry(
        SupabaseConstants.postsBucket,
        '${widget.profile.id}/avatar_$stamp.$ext',
      ),
    ];

    Object? lastError;

    try {
      for (final attempt in attempts) {
        try {
          await client.storage.from(attempt.key).upload(
                attempt.value,
                _pickedAvatar!,
                fileOptions: const FileOptions(upsert: true),
              );
          return client.storage.from(attempt.key).getPublicUrl(attempt.value);
        } catch (e) {
          lastError = e;
        }
      }

      setState(() => _error =
          'Could not upload photo: $lastError\n(Tried both the "avatars" and "${SupabaseConstants.postsBucket}" buckets.)');
      return null;
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      String? avatarUrl;
      if (_pickedAvatar != null) {
        avatarUrl = await _uploadAvatarIfNeeded();
        // If the upload failed, _error is already set — stop here instead
        // of silently saving the rest without the new photo.
        if (avatarUrl == null && _pickedAvatar != null) {
          setState(() => _saving = false);
          return;
        }
      }

      await ProfileService.updateProfile(
        userId: widget.profile.id,
        displayName: _displayName.text.trim(),
        bio: _bio.text.trim(),
        niche: _niche.text.trim(),
        avatarUrl: avatarUrl,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Could not save profile: $e');
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
            Center(
              child: GestureDetector(
                onTap: _uploadingAvatar ? null : _pickAvatar,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: AppColors.surfaceBorder,
                      backgroundImage: _pickedAvatar != null
                          ? FileImage(_pickedAvatar!)
                          : (widget.profile.avatarUrl != null
                              ? NetworkImage(widget.profile.avatarUrl!)
                              : null) as ImageProvider?,
                      child: (_pickedAvatar == null && widget.profile.avatarUrl == null)
                          ? Text(
                              widget.profile.displayName.isNotEmpty
                                  ? widget.profile.displayName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(fontSize: 32),
                            )
                          : null,
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: _uploadingAvatar
                          ? const SizedBox(
                              height: 14,
                              width: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background),
                            )
                          : const Icon(Icons.camera_alt, size: 16, color: AppColors.background),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
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
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: (_saving || _uploadingAvatar) ? null : _save,
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
