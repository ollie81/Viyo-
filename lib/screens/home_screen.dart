import 'package:flutter/material.dart' hide Badge;
import 'package:share_plus/share_plus.dart';
import '../models/user_data.dart';
import '../services/storage_service.dart';
import '../services/inspiration_service.dart';
import 'welcome_screen.dart';

class HomeScreen extends StatefulWidget {
  final UserData user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late UserData user;
  int _tab = 0;
  String? _toast;
  final _giftNameCtrl = TextEditingController();
  int _giftAmount = 50;

  @override
  void initState() {
    super.initState();
    user = widget.user;
    _handleDailyReset();
  }

  Future<void> _handleDailyReset() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (user.lastLogin != today) {
      for (var m in user.missions) {
        if (m.type == 'daily') m.completed = false;
      }

      if (user.lastLogin.isNotEmpty) {
        final last = DateTime.tryParse(user.lastLogin);
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        if (last != null &&
            last.year == yesterday.year &&
            last.month == yesterday.month &&
            last.day == yesterday.day) {
          user.streak += 1;
        } else {
          user.streak = 1;
        }
      } else {
        user.streak = 1;
      }

      user.lastLogin = today;
      await StorageService.saveUser(user);
      setState(() {});
    }
  }

  Future<void> _save() async {
    await StorageService.saveUser(user);
    setState(() {});
  }

  void _showToast(String msg) {
    setState(() => _toast = msg);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _completeMission(Mission m) async {
    if (m.completed) return;

    m.completed = true;
    user.coins += m.coins;

    user.transactions.insert(
      0,
      Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: 'earn',
        amount: m.coins,
        description: m.title,
        date: DateTime.now().toIso8601String(),
      ),
    );

    if (user.transactions.length > 50) {
      user.transactions = user.transactions.sublist(0, 50);
    }

    await _save();
    _showToast('+${m.coins} coins! 🎉');
  }

  Future<void> _unlockBadge(Badge b) async {
    if (b.unlocked || user.coins < b.cost) return;

    user.coins -= b.cost;
    b.unlocked = true;

    user.transactions.insert(
      0,
      Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: 'spend',
        amount: b.cost,
        description: 'Unlocked: ${b.name}',
        date: DateTime.now().toIso8601String(),
      ),
    );

    if (user.transactions.length > 50) {
      user.transactions = user.transactions.sublist(0, 50);
    }

    await _save();
    _showToast('Badge unlocked: ${b.name}!');
  }

  Future<void> _giftCoins() async {
    final name = _giftNameCtrl.text.trim();
    if (name.isEmpty || _giftAmount < 10 || user.coins < _giftAmount) return;

    user.coins -= _giftAmount;
    user.gifted += 1;

    user.transactions.insert(
      0,
      Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: 'gift',
        amount: _giftAmount,
        description: 'Gifted to $name',
        date: DateTime.now().toIso8601String(),
      ),
    );

    if (user.transactions.length > 50) {
      user.transactions = user.transactions.sublist(0, 50);
    }

    await _save();
    _giftNameCtrl.clear();
    _showToast('Gifted $_giftAmount coins to $name! 💜');
  }

  Future<void> _share() async {
    final text =
        "I'm boosting my creator journey on Viyo 🔥 Currently at ${user.coins} coins & ${user.streak}-day streak. Join free!";
    await Share.share(text);
  }

  Future<void> _reset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF13132B),
        title: const Text('Reset progress?'),
        content: const Text('This will delete all your coins and progress.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await StorageService.resetUser();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (_) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final completed = user.missions.where((m) => m.completed).length;
    final quote = InspirationService.getTodayQuote();
    final idea = InspirationService.getTodayIdea();

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Viyo',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF67E8F9),
                            ),
                          ),
                          Text(
                            'Hey, ${user.name}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${user.coins}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFBBF24),
                                ),
                              ),
                              const Text(
                                'coins',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E5FF).withOpacity(0.25),
                              borderRadius: BorderRadius.circular(21),
                              border: Border.all(
                                color: const Color(0xFF00E5FF).withOpacity(0.5),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '${user.streak}🔥',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Progress
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF13132B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF1E1E3A)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Today's missions",
                              style: TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                            Text(
                              '$completed/${user.missions.length}',
                              style: const TextStyle(
                                color: Color(0xFF67E8F9),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: completed / user.missions.length,
                            backgroundColor: Colors.white10,
                            color: const Color(0xFF00E5FF),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Tabs
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF13132B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        _tabBtn(0, 'Missions'),
                        _tabBtn(1, 'Inspire'),
                        _tabBtn(2, 'Wallet'),
                        _tabBtn(3, 'Store'),
                      ],
                    ),
                  ),
                ),

                // Content
                Expanded(
                  child: _tab == 0
                      ? _missionsList()
                      : _tab == 1
                          ? _inspireView(quote, idea)
                          : _tab == 2
                              ? _walletView()
                              : _storeView(),
                ),
              ],
            ),

            // Toast
            if (_toast != null)
              Positioned(
                top: 80,
                left: 40,
                right: 40,
                child: Material(
                  color: const Color(0xFFA855F7),
                  borderRadius: BorderRadius.circular(30),
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Text(
                      _toast!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _share,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Color(0xFF1E1E3A)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Share Viyo ↗'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _reset,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white38,
                  side: const BorderSide(color: Color(0xFF1E1E3A)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                child: const Text('Reset'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabBtn(int index, String label) {
    final selected = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF00E5FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? const Color(0xFF0B0B1A) : Colors.white54,
            ),
          ),
        ),
      ),
    );
  }

  Widget _missionsList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      itemCount: user.missions.length,
      itemBuilder: (ctx, i) {
        final m = user.missions[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF13132B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E1E3A)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: m.completed ? Colors.white54 : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      m.description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white38,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '+${m.coins}',
                      style: const TextStyle(
                        color: Color(0xFFFBBF24),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: m.completed ? null : () => _completeMission(m),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: const Color(0xFF0B0B1A),
                  disabledBackgroundColor: Colors.white12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                child: Text(m.completed ? 'Done ✓' : 'Claim'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _inspireView(InspirationItem quote, String idea) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF13132B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1E1E3A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "TODAY'S QUOTE",
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: Color(0xFF67E8F9),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '"${quote.quote}"',
                style: const TextStyle(
                  fontSize: 17,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '— ${quote.author}',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF13132B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1E1E3A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CONTENT IDEA',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: Color(0xFFC084FC),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(idea, style: const TextStyle(fontSize: 16, height: 1.4)),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {
                  final m = user.missions.firstWhere((e) => e.id == 'inspire');
                  if (!m.completed) _completeMission(m);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Color(0xFF1E1E3A)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Mark as read (+30 coins)'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _walletView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF13132B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1E1E3A)),
          ),
          child: Column(
            children: [
              const Text('Your balance', style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 6),
              Text(
                '${user.coins}',
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFBBF24),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Streak: ${user.streak} days  ·  Gifted: ${user.gifted} times',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF13132B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E1E3A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Gift coins to a friend',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _giftNameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Friend's name or @handle",
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '50',
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (v) => _giftAmount = int.tryParse(v) ?? 50,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _giftCoins,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: const Color(0xFF0B0B1A),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Send Gift 💜'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF13132B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E1E3A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Recent activity',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              if (user.transactions.isEmpty)
                const Text(
                  'No transactions yet',
                  style: TextStyle(color: Colors.white38),
                )
              else
                ...user.transactions.take(12).map((tx) {
                  final isEarn = tx.type == 'earn';
                  final isGift = tx.type == 'gift';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            tx.description,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${isEarn ? '+' : '-'}${tx.amount}',
                          style: TextStyle(
                            color: isEarn
                                ? const Color(0xFF22C55E)
                                : isGift
                                    ? const Color(0xFFC084FC)
                                    : Colors.white54,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _storeView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10, left: 4),
          child: Text(
            'Spend coins on free digital rewards. No real money needed.',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
        ...user.badges.map((b) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF13132B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: b.unlocked
                    ? const Color(0xFF00E5FF).withOpacity(0.4)
                    : const Color(0xFF1E1E3A),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            b.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (b.unlocked) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E5FF).withOpacity(0.25),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'OWNED',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF67E8F9),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        b.description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white38,
                        ),
                      ),
                      if (b.cost > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${b.cost} coins',
                          style: const TextStyle(
                            color: Color(0xFFFBBF24),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: (b.unlocked || b.cost == 0 || user.coins < b.cost)
                      ? null
                      : () => _unlockBadge(b),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: const Color(0xFF0B0B1A),
                    disabledBackgroundColor: Colors.white12,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  child: Text(
                    b.unlocked
                        ? '✓'
                        : b.cost == 0
                            ? 'Free'
                            : 'Unlock',
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}