import 'package:flutter/material.dart';
import '../../../models/series.dart';
import '../../../theme/app_theme.dart';

class DramaDetails {
  final String title;
  final String genre;
  final String description;

  const DramaDetails({required this.title, required this.genre, required this.description});
}

/// Shared title/genre/description form for both creating a brand-new
/// drama and editing an existing one's details from inside Viyo
/// Studio — there was previously no way to do either without leaving
/// Studio for the regular (video-upload-first) upload flow.
Future<DramaDetails?> showDramaDetailsDialog(
  BuildContext context, {
  String initialTitle = '',
  String initialGenre = kDefaultDramaGenre,
  String initialDescription = '',
  required String title,
  required String confirmLabel,
}) {
  final titleController = TextEditingController(text: initialTitle);
  final descriptionController = TextEditingController(text: initialDescription);
  var genre = kDramaGenres.contains(initialGenre) ? initialGenre : kDefaultDramaGenre;

  return showDialog<DramaDetails>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Drama name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: genre,
                isExpanded: true,
                dropdownColor: AppColors.surface,
                decoration: const InputDecoration(labelText: 'Genre'),
                items: kDramaGenres.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => genre = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Description (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final name = titleController.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(
                ctx,
                DramaDetails(title: name, genre: genre, description: descriptionController.text.trim()),
              );
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
}
