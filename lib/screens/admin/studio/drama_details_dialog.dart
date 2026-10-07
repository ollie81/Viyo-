import 'package:flutter/material.dart';
import '../../../models/series.dart';
import '../../../services/profile_service.dart';
import '../../../theme/app_theme.dart';

class DramaDetails {
  final String title;
  final String genre;
  final String description;
  // Null means "leave the owner as whatever it already is" (editing an
  // existing drama with no creator change made) or "use my own
  // account" (creating a brand-new one, the pre-existing default) —
  // see showDramaDetailsDialog's own creator-picker row below. Only
  // non-null when the admin actually picked a different account.
  final String? creatorUserId;

  const DramaDetails({
    required this.title,
    required this.genre,
    required this.description,
    this.creatorUserId,
  });
}

/// Shared title/genre/description/creator form for both creating a
/// brand-new drama and editing an existing one's details from inside
/// Viyo Studio — there was previously no way to do either without
/// leaving Studio for the regular (video-upload-first) upload flow,
/// and no way at all to say which real account a Studio-generated
/// drama (and every episode published from it) actually belongs to.
Future<DramaDetails?> showDramaDetailsDialog(
  BuildContext context, {
  String initialTitle = '',
  String initialGenre = kDefaultDramaGenre,
  String initialDescription = '',
  // The creator picker's starting label/id — pass the series' current
  // owner when editing an existing drama (shown as "@username"), or
  // leave both null when creating a new one (shown as "You" — the
  // pre-existing default of whoever's running Studio).
  String? initialCreatorUserId,
  String? initialCreatorLabel,
  required String title,
  required String confirmLabel,
}) {
  final titleController = TextEditingController(text: initialTitle);
  final descriptionController = TextEditingController(text: initialDescription);
  var genre = kDramaGenres.contains(initialGenre) ? initialGenre : kDefaultDramaGenre;
  var creatorUserId = initialCreatorUserId;
  var creatorLabel = initialCreatorLabel ?? 'You';

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
              const SizedBox(height: 14),
              const Text('Creator account', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              const SizedBox(height: 4),
              InkWell(
                onTap: () async {
                  final picked = await _pickCreator(ctx);
                  if (picked == null) return;
                  setState(() {
                    creatorUserId = picked['id'] as String;
                    creatorLabel = '@${picked['username']}';
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.surfaceBorder),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline, size: 18, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Expanded(child: Text(creatorLabel, style: const TextStyle(fontSize: 13))),
                      const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
                    ],
                  ),
                ),
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
                DramaDetails(
                  title: name,
                  genre: genre,
                  description: descriptionController.text.trim(),
                  creatorUserId: creatorUserId,
                ),
              );
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
}

/// Searches `profiles` by username/display name and lets the admin
/// pick one — reuses ProfileService.searchCreators, the same lookup
/// Discover's own search already relies on.
Future<Map<String, dynamic>?> _pickCreator(BuildContext context) {
  final queryController = TextEditingController();
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setState) {
            List<Map<String, dynamic>> results = [];
            bool loading = false;
            Future<void> search(String q) async {
              if (q.trim().isEmpty) {
                setState(() => results = []);
                return;
              }
              setState(() => loading = true);
              try {
                final found = await ProfileService.searchCreators(q.trim());
                setState(() {
                  results = found;
                  loading = false;
                });
              } catch (_) {
                setState(() => loading = false);
              }
            }

            return SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.6,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: TextField(
                      controller: queryController,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Search by username or name...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: search,
                    ),
                  ),
                  if (loading) const LinearProgressIndicator(),
                  Expanded(
                    child: results.isEmpty
                        ? Center(
                            child: Text(
                              queryController.text.trim().isEmpty
                                  ? 'Type to search for an account.'
                                  : 'No accounts found.',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (_, i) {
                              final r = results[i];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.surfaceBorder,
                                  backgroundImage:
                                      r['avatar_url'] != null ? NetworkImage(r['avatar_url']) : null,
                                  child: r['avatar_url'] == null ? const Icon(Icons.person, size: 18) : null,
                                ),
                                title: Text(r['display_name'] ?? r['username'] ?? '',
                                    style: const TextStyle(color: Colors.white)),
                                subtitle: Text('@${r['username'] ?? ''}',
                                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                onTap: () => Navigator.pop(ctx, r),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}
