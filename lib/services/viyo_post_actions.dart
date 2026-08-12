import 'package:flutter/material.dart';

/// Central UI actions for Viyo posts.
///
/// Connect the callbacks to the existing Supabase/API service. Keeping these
/// actions in one place makes it harder for different screens to implement
/// inconsistent ownership rules.
class ViyoPostActions {
  const ViyoPostActions();

  Future<bool> confirmDelete(
    BuildContext context, {
    required String postLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete post?'),
        content: Text(
          'Delete $postLabel? This action should remove the database post and '
          'its stored media from the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result == true;
  }
}
