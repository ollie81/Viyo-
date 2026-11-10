import 'package:flutter/material.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';
import 'studio_project_screen.dart';
import 'studio_widgets.dart';

/// Viyo Studio home: the creator's productions and a way to start a new one.
/// Built for phones and wide desktop browsers alike.
class StudioHomeScreen extends StatefulWidget {
  const StudioHomeScreen({super.key});
  @override
  State<StudioHomeScreen> createState() => _StudioHomeScreenState();
}

class _StudioHomeScreenState extends State<StudioHomeScreen> {
  List<StudioProjectSummary>? _projects;
  StudioBalance _balance = const StudioBalance();
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (b, p) = await CreatorStudioService.projects();
      if (mounted) {
        setState(() {
          _balance = b;
          _projects = p;
          _loading = false;
        });
      }
    } on StudioException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _new() async {
    final id = await showDialog<String>(context: context, builder: (_) => const _NewProductionDialog());
    if (id == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudioProjectScreen(projectId: id)));
    _load();
  }

  /// Start with one sentence: a production is made from the idea and the
  /// assistant chat opens with it, so the creator can develop it by talking.
  Future<void> _startWithIdea() async {
    final idea = TextEditingController();
    var terms = false;
    String? error;
    var saving = false;
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
        backgroundColor: StudioColors.panel,
        title: const Text('Start with an idea'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Tell Viyo your idea in a sentence. You\'ll develop it together in a chat.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4)),
            const SizedBox(height: 12),
            TextField(controller: idea, autofocus: true, minLines: 2, maxLines: 5, maxLength: 2000,
                decoration: studioField('Your idea', hint: 'e.g. A poor young man discovers he is a billionaire\'s son')
                    .copyWith(counterText: '')),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: terms,
              onChanged: (v) => setDialog(() => terms = v == true),
              title: const Text('The story and characters are fictional or mine to use, and I won\'t depict real people '
                  'without their consent.', style: TextStyle(fontSize: 12.5)),
            ),
            if (error != null) Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    final text = idea.text.trim();
                    if (text.isEmpty) return setDialog(() => error = 'Write your idea first.');
                    if (!terms) return setDialog(() => error = 'Please confirm the box above.');
                    setDialog(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      final words = text.split(RegExp(r'\s+'));
                      final title = words.take(6).join(' ') + (words.length > 6 ? '…' : '');
                      final id = await CreatorStudioService.createProject(
                          {'title': title.length > 120 ? title.substring(0, 120) : title, 'logline': text, 'accept_terms': true});
                      if (ctx.mounted) Navigator.pop(ctx, id);
                    } on StudioException catch (e) {
                      setDialog(() {
                        saving = false;
                        error = e.message;
                      });
                    }
                  },
            child: Text(saving ? 'Starting…' : 'Start chatting'),
          ),
        ],
      )),
    );
    final text = idea.text.trim();
    idea.dispose();
    if (id == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudioProjectScreen(projectId: id, openChatWith: text)));
    _load();
  }

  Future<void> _open(StudioProjectSummary p) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudioProjectScreen(projectId: p.id)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        titleSpacing: 12,
        title: const Row(children: [
          Icon(Icons.movie_filter_outlined, color: AppColors.primary),
          SizedBox(width: 8),
          Text('Viyo Studio', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: CreditPill(balance: _balance, onTap: () async {
              await showCreditsSheet(context);
              _load();
            })),
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    if (_loading && _projects == null) return const Center(child: CircularProgressIndicator());
    if (_error != null && _projects == null) {
      return ListView(padding: const EdgeInsets.all(32), children: [
        const SizedBox(height: 40),
        const Icon(Icons.cloud_off, size: 40, color: AppColors.textMuted),
        const SizedBox(height: 12),
        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        Center(child: OutlinedButton(onPressed: _load, child: const Text('Try again'))),
      ]);
    }
    final projects = _projects ?? [];
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final pad = w > 900 ? 32.0 : 16.0;
      final cols = w > 1300 ? 4 : w > 950 ? 3 : w > 620 ? 2 : 1;
      return ListView(padding: EdgeInsets.fromLTRB(pad, 8, pad, 100), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _Hero(onNew: _new, onIdea: _startWithIdea, compact: projects.isNotEmpty, wide: w > 900),
              const SizedBox(height: 24),
              if (projects.isNotEmpty) ...[
                Text('Your productions', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: cols,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: cols == 1 ? 2.6 : (cols == 2 ? 2.4 : 2.2),
                  children: [for (final p in projects) _ProjectCard(p, onTap: () => _open(p), horizontal: cols == 1)],
                ),
              ],
            ]),
          ),
        ),
      ]);
    });
  }
}

class _Hero extends StatelessWidget {
  final VoidCallback onNew;
  final VoidCallback? onIdea;
  final bool compact, wide;
  const _Hero({required this.onNew, this.onIdea, required this.compact, required this.wide});

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.edit_note, 'Story', 'Write your idea; AI drafts the script'),
      (Icons.groups_outlined, 'Cast', 'Characters with consistent faces and voices'),
      (Icons.view_carousel_outlined, 'Scenes', 'Images, voices and optional AI video, scene by scene'),
      (Icons.movie_outlined, 'Export', 'Render in 9:16 or 16:9, download, post anywhere'),
    ];
    return Container(
      padding: EdgeInsets.all(wide ? 28 : 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: StudioColors.panelBorder),
        gradient: const LinearGradient(colors: [Color(0xFF141436), Color(0xFF1A1240)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(compact ? 'Make your next episode' : 'Make AI dramas, episodes and films',
            style: TextStyle(fontSize: wide ? 26 : 20, fontWeight: FontWeight.w800, height: 1.2)),
        const SizedBox(height: 6),
        const Text('From an idea to a finished video, scene by scene. You see the price of every step before it runs, and you own what you make.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.45)),
        if (!compact) ...[
          const SizedBox(height: 18),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final (icon, title, body) in steps)
              SizedBox(
                width: wide ? 230 : double.infinity,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: Icon(icon, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(body, style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.35)),
                    ]),
                  ),
                ]),
              ),
          ]),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onNew,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
          icon: const Icon(Icons.add),
          label: const Text('New production', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        if (onIdea != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onIdea,
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Start with an idea (chat)', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ]),
    );
  }
}

const _kindLabels = {'short': 'Short film', 'episode': 'Episode', 'series': 'Series', 'film': 'Film'};

class _ProjectCard extends StatelessWidget {
  final StudioProjectSummary p;
  final VoidCallback onTap;
  final bool horizontal;
  const _ProjectCard(this.p, {required this.onTap, required this.horizontal});

  @override
  Widget build(BuildContext context) {
    final vertical = p.aspectRatio == '9:16';
    final progress = p.sceneCount == 0 ? 0.0 : p.scenesWithImages / p.sceneCount;
    final status = p.renderCount > 0
        ? 'Rendered ×${p.renderCount}'
        : p.sceneCount == 0
            ? 'Story'
            : '${p.scenesWithImages}/${p.sceneCount} scenes ready';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: studioPanel(),
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            AspectFrame(vertical: vertical, imageUrl: p.thumbnailUrl, width: vertical ? 64 : 112, placeholder: Icons.movie_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text(p.logline.isEmpty ? 'No idea written yet' : p.logline,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.35)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  _tag(_kindLabels[p.kind] ?? p.kind),
                  _tag(p.aspectRatio),
                  _tag(status, color: p.renderCount > 0 ? AppColors.success : AppColors.primary),
                ]),
                if (p.sceneCount > 0 && p.renderCount == 0) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(value: progress, minHeight: 4, backgroundColor: Colors.white10, color: AppColors.primary),
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tag(String t, {Color color = AppColors.textSecondary}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}

// ---------------------------------------------------------------- new production

const kStyles = [
  'Cinematic, realistic',
  'Korean drama, soft light',
  'Nollywood drama, warm tones',
  'Anime',
  '3D animated film',
  'Dark thriller, high contrast',
];
const kGenres = ['Drama', 'Romance', 'Thriller', 'Comedy', 'Action', 'Horror', 'Fantasy', 'Family', 'Crime', 'Sci-fi'];

class _NewProductionDialog extends StatefulWidget {
  const _NewProductionDialog();
  @override
  State<_NewProductionDialog> createState() => _NewProductionDialogState();
}

class _NewProductionDialogState extends State<_NewProductionDialog> {
  final _title = TextEditingController();
  final _idea = TextEditingController();
  final _style = TextEditingController(text: kStyles.first);
  final _language = TextEditingController(text: 'English');
  String _kind = 'episode';
  String _aspect = '9:16';
  String _productionStyle = 'video';
  String _genre = 'Drama';
  double _seconds = 90;
  bool _captions = true;
  bool _terms = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _idea, _style, _language]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    if (_title.text.trim().isEmpty) return setState(() => _error = 'Give your production a title.');
    if (!_terms) return setState(() => _error = 'Please confirm the story and characters are yours to use.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await CreatorStudioService.createProject({
        'title': _title.text.trim(), 'logline': _idea.text.trim(), 'kind': _kind, 'aspect_ratio': _aspect,
        'genre': _genre, 'visual_style': _style.text.trim(), 'language': _language.text.trim().isEmpty ? 'English' : _language.text.trim(),
        'target_seconds': _seconds.round(), 'captions': _captions, 'accept_terms': true,
        'production_style': _productionStyle,
      });
      if (mounted) Navigator.pop(context, id);
    } on StudioException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width > 700;
    return Dialog(
      backgroundColor: StudioColors.panel,
      insetPadding: EdgeInsets.symmetric(horizontal: wide ? 40 : 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: StudioColors.panelBorder)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('New production', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(controller: _title, maxLength: 120, decoration: studioField('Title', hint: 'e.g. The Last Bus Home')),
            const SizedBox(height: 6),
            TextField(controller: _idea, maxLines: 4, maxLength: 2000,
                decoration: studioField('Your idea', hint: 'Who is it about, what do they want, what goes wrong?')),
            const SizedBox(height: 10),
            const _Label('Format'),
            Row(children: [
              Expanded(child: _FormatCard(selected: _aspect == '9:16', vertical: true, title: 'Vertical 9:16', subtitle: 'Phones, TikTok, Reels, Viyo dramas', onTap: () => setState(() => _aspect = '9:16'))),
              const SizedBox(width: 10),
              Expanded(child: _FormatCard(selected: _aspect == '16:9', vertical: false, title: 'Landscape 16:9', subtitle: 'YouTube, TV, films', onTap: () => setState(() => _aspect = '16:9'))),
            ]),
            const SizedBox(height: 14),
            const _Label('How it\'s made'),
            Row(children: [
              Expanded(
                child: _StyleCard(
                  selected: _productionStyle == 'video',
                  icon: Icons.movie_creation_outlined,
                  title: 'Talking video',
                  subtitle: 'Every scene moves and the characters speak. Recommended.',
                  onTap: () => setState(() => _productionStyle = 'video'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StyleCard(
                  selected: _productionStyle == 'pictures',
                  icon: Icons.photo_library_outlined,
                  title: 'Pictures with voices',
                  subtitle: 'Still scenes with camera movement. Costs less.',
                  onTap: () => setState(() => _productionStyle = 'pictures'),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            const _Label('Type'),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'short', label: Text('Short')),
                ButtonSegment(value: 'episode', label: Text('Episode')),
                ButtonSegment(value: 'film', label: Text('Film')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(
                width: wide ? 280 : double.infinity,
                child: DropdownButtonFormField<String>(
                  initialValue: _genre,
                  dropdownColor: StudioColors.panel,
                  decoration: studioField('Genre'),
                  items: [for (final g in kGenres) DropdownMenuItem(value: g, child: Text(g))],
                  onChanged: (v) => setState(() => _genre = v ?? _genre),
                ),
              ),
              SizedBox(width: wide ? 280 : double.infinity, child: TextField(controller: _language, decoration: studioField('Language'))),
            ]),
            const SizedBox(height: 14),
            const _Label('Look'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in kStyles)
                ChoiceChip(
                  label: Text(s, style: const TextStyle(fontSize: 12)),
                  selected: _style.text == s,
                  onSelected: (_) => setState(() => _style.text = s),
                ),
            ]),
            const SizedBox(height: 8),
            TextField(controller: _style, onChanged: (_) => setState(() {}), decoration: studioField('Visual style (edit freely)')),
            const SizedBox(height: 14),
            _Label('Length: about ${_fmt(_seconds.round())}'),
            Slider(value: _seconds, min: 30, max: 600, divisions: 38, label: _fmt(_seconds.round()), onChanged: (v) => setState(() => _seconds = v)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _captions,
              onChanged: (v) => setState(() => _captions = v),
              title: const Text('Burn in captions', style: TextStyle(fontSize: 14)),
              subtitle: const Text('Spoken lines appear on screen', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _terms,
              onChanged: (v) => setState(() => _terms = v ?? false),
              title: const Text('The story and characters are fictional or mine to use, and I won\'t depict real people without their consent.',
                  style: TextStyle(fontSize: 12.5, height: 1.35)),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13))),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _create,
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Text('Create', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  String _fmt(int s) => s < 60 ? '$s s' : '${s ~/ 60} min${s % 60 == 0 ? '' : ' ${s % 60} s'}';
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
      );
}

class _FormatCard extends StatelessWidget {
  final bool selected, vertical;
  final String title, subtitle;
  final VoidCallback onTap;
  const _FormatCard({required this.selected, required this.vertical, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.08) : StudioColors.field,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : StudioColors.panelBorder, width: selected ? 1.6 : 1),
        ),
        child: Row(children: [
          Container(
            width: vertical ? 18 : 32,
            height: vertical ? 32 : 18,
            decoration: BoxDecoration(border: Border.all(color: selected ? AppColors.primary : AppColors.textMuted, width: 2), borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
            ]),
          ),
        ]),
      ),
    );
  }
}


class _StyleCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const _StyleCard({required this.selected, required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? AppColors.primary.withValues(alpha: 0.10) : Colors.transparent,
          border: Border.all(color: selected ? AppColors.primary : StudioColors.panelBorder, width: selected ? 1.6 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 22, color: selected ? AppColors.primary : AppColors.textMuted),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3)),
        ]),
      ),
    );
  }
}
