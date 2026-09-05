import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'models/food_item.dart';
import 'services/ai_expiry_service.dart';
import 'services/food_repository.dart';
import 'services/notification_service.dart';

const _ink = Color(0xFF25221F);
const _muted = Color(0xFF746F68);
const _canvas = Color(0xFFF8F7F2);
const _surface = Color(0xFFFFFFFF);
const _orange = Color(0xFFFF7043);
const _orangeSoft = Color(0xFFFFE7DB);
const _green = Color(0xFF2F7D62);
const _greenSoft = Color(0xFFE1F1E9);
const _yellow = Color(0xFFFFC857);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = FoodRepository();
  final snapshot = await repository.load();
  final notificationService = NotificationService();
  await notificationService.initialize();
  await notificationService.syncReminders(
    items: snapshot.items,
    enabled: snapshot.notificationsEnabled,
    reminderHour: snapshot.reminderHour,
  );
  runApp(
    DueBiteApp(
      repository: repository,
      notificationService: notificationService,
      initialSnapshot: snapshot,
    ),
  );
}

class DueBiteApp extends StatelessWidget {
  const DueBiteApp({
    super.key,
    required this.repository,
    required this.notificationService,
    required this.initialSnapshot,
  });

  final FoodRepository repository;
  final NotificationService notificationService;
  final AppSnapshot initialSnapshot;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _orange,
      brightness: Brightness.light,
      surface: _canvas,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DueBite',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: _canvas,
        fontFamilyFallback: const ['Noto Sans JP', 'Yu Gothic', 'sans-serif'],
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: _ink,
          displayColor: _ink,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: _canvas,
          surfaceTintColor: Colors.transparent,
          foregroundColor: _ink,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: _surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF1F0EB),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 17,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _orange, width: 1.6),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: _ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: ExpiryHome(
        repository: repository,
        notificationService: notificationService,
        initialSnapshot: initialSnapshot,
      ),
    );
  }
}

class ExpiryHome extends StatefulWidget {
  const ExpiryHome({
    super.key,
    required this.repository,
    required this.notificationService,
    required this.initialSnapshot,
  });

  final FoodRepository repository;
  final NotificationService notificationService;
  final AppSnapshot initialSnapshot;

  @override
  State<ExpiryHome> createState() => _ExpiryHomeState();
}

class _ExpiryHomeState extends State<ExpiryHome> {
  final _picker = ImagePicker();
  final _aiService = const AiExpiryService();
  late List<FoodItem> _items;
  late int _points;
  late bool _notificationsEnabled;
  late int _reminderHour;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _items = [...widget.initialSnapshot.items];
    _points = widget.initialSnapshot.points;
    _notificationsEnabled = widget.initialSnapshot.notificationsEnabled;
    _reminderHour = widget.initialSnapshot.reminderHour;
  }

  List<FoodItem> get _activeItems =>
      _items.where((item) => !item.isConsumed).toList()
        ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));

  void _persist() {
    unawaited(
      widget.repository.save(
        AppSnapshot(
          items: _items,
          points: _points,
          notificationsEnabled: _notificationsEnabled,
          reminderHour: _reminderHour,
        ),
      ),
    );
    unawaited(
      widget.notificationService.syncReminders(
        items: _items,
        enabled: _notificationsEnabled,
        reminderHour: _reminderHour,
      ),
    );
  }

  Future<void> _showReminderSettings() async {
    final result = await showModalBottomSheet<ReminderSettings>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => NotificationSettingsSheet(
        enabled: _notificationsEnabled,
        reminderHour: _reminderHour,
        isSupported: widget.notificationService.isSupported,
      ),
    );
    if (!mounted || result == null) return;

    if (result.enabled) {
      final granted = await widget.notificationService.requestPermission();
      if (!mounted) return;
      if (!granted) {
        if (_notificationsEnabled) {
          setState(() => _notificationsEnabled = false);
          _persist();
        }
        _showMessage('通知が許可されませんでした。端末設定から変更できます');
        return;
      }
    }

    setState(() {
      _notificationsEnabled = result.enabled;
      _reminderHour = result.reminderHour;
    });
    _persist();
    _showMessage(
      _notificationsEnabled
          ? '期限のお知らせを$_reminderHour時に設定しました'
          : '期限のお知らせをオフにしました',
    );
  }

  Future<void> _showAddMenu() async {
    HapticFeedback.selectionClick();
    final action = await showModalBottomSheet<_AddAction>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const _AddFoodSheet(),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _AddAction.camera:
        await _captureAndAnalyze(ImageSource.camera);
      case _AddAction.gallery:
        await _captureAndAnalyze(ImageSource.gallery);
      case _AddAction.agent:
        await _openProductAgent();
      case _AddAction.manual:
        await _openEditor();
    }
  }

  Future<void> _captureAndAnalyze(ImageSource source) async {
    XFile? photo;
    try {
      photo = await _picker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1800,
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      _showMessage(
        error.code.contains('denied')
            ? 'カメラの利用を端末設定から許可してください'
            : 'カメラを開けませんでした。手入力をお試しください',
      );
      return;
    } catch (_) {
      if (mounted) _showMessage('画像を選択できませんでした');
      return;
    }
    if (photo == null || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AnalyzingDialog(),
    );

    AiExpiryResult? result;
    String? errorMessage;
    try {
      result = await _aiService.analyze(photo);
    } on AiExpiryException catch (error) {
      errorMessage = error.message;
    } catch (_) {
      errorMessage = 'AI解析に失敗しました。内容を手入力してください';
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (errorMessage != null) _showMessage(errorMessage);
    await _openEditor(photo: photo, aiResult: result);
  }

  Future<void> _openEditor({XFile? photo, AiExpiryResult? aiResult}) async {
    final draft = await Navigator.of(context).push<FoodDraft>(
      MaterialPageRoute(
        builder: (_) => FoodEditorPage(photo: photo, aiResult: aiResult),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || draft == null) return;

    _registerDraft(draft);
  }

  Future<void> _openProductAgent() async {
    final draft = await Navigator.of(context).push<FoodDraft>(
      MaterialPageRoute(
        builder: (_) => ProductAgentPage(service: _aiService),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || draft == null) return;

    _registerDraft(draft);
  }

  void _registerDraft(FoodDraft draft) {
    final item = FoodItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: draft.name,
      category: draft.category,
      expiryDate: draft.expiryDate,
      registeredAt: DateTime.now(),
      registeredWithAi: draft.registeredWithAi,
    );
    setState(() {
      _items = [..._items, item];
      _pageIndex = 1;
    });
    _persist();
    _showMessage('${item.name}を登録しました');
  }

  Future<void> _consume(FoodItem item) async {
    final points = item.daysRemaining < 0
        ? 0
        : item.daysRemaining <= 1
        ? 20
        : item.daysRemaining <= 3
        ? 15
        : 10;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: Container(
          width: 58,
          height: 58,
          decoration: const BoxDecoration(
            color: _greenSoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.restaurant_rounded, color: _green, size: 30),
        ),
        title: const Text('食べきりましたか？'),
        content: Text(
          points > 0
              ? '${item.name}を食べきると $points ポイントもらえます。'
              : '${item.name}を食べきり済みにします。',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('まだ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('食べきった！'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() {
      _items = _items
          .map(
            (current) => current.id == item.id
                ? current.consume(points: points)
                : current,
          )
          .toList();
      _points += points;
    });
    _persist();
    HapticFeedback.mediumImpact();
    if (points > 0) {
      await showDialog<void>(
        context: context,
        builder: (_) =>
            _PointEarnedDialog(points: points, totalPoints: _points),
      );
    } else {
      _showMessage('食べきり済みにしました');
    }
  }

  Future<void> _delete(FoodItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('食品を削除しますか？'),
        content: Text('${item.name}を一覧から削除します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _items.removeWhere((current) => current.id == item.id));
    _persist();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeDashboard(
        items: _activeItems,
        points: _points,
        notificationsEnabled: _notificationsEnabled,
        onAdd: _showAddMenu,
        onReminderSettings: _showReminderSettings,
        onConsume: _consume,
        onSeeAll: () => setState(() => _pageIndex = 1),
      ),
      FoodListPage(items: _items, onConsume: _consume, onDelete: _delete),
      PointsPage(items: _items, points: _points),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: IndexedStack(index: _pageIndex, children: pages),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 72,
        backgroundColor: _surface,
        indicatorColor: _orangeSoft,
        selectedIndex: _pageIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) => setState(() => _pageIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: _orange),
            label: 'ホーム',
          ),
          NavigationDestination(
            icon: Icon(Icons.kitchen_outlined),
            selectedIcon: Icon(Icons.kitchen_rounded, color: _orange),
            label: '食品',
          ),
          NavigationDestination(
            icon: Icon(Icons.stars_outlined),
            selectedIcon: Icon(Icons.stars_rounded, color: _orange),
            label: 'ポイント',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-food-button'),
        heroTag: 'add-food',
        onPressed: _showAddMenu,
        backgroundColor: _ink,
        foregroundColor: Colors.white,
        elevation: 5,
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text(
          '食品を登録',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class HomeDashboard extends StatelessWidget {
  const HomeDashboard({
    super.key,
    required this.items,
    required this.points,
    required this.notificationsEnabled,
    required this.onAdd,
    required this.onReminderSettings,
    required this.onConsume,
    required this.onSeeAll,
  });

  final List<FoodItem> items;
  final int points;
  final bool notificationsEnabled;
  final VoidCallback onAdd;
  final VoidCallback onReminderSettings;
  final ValueChanged<FoodItem> onConsume;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final urgent = items.where((item) => item.daysRemaining <= 3).length;
    return CustomScrollView(
      key: const PageStorageKey('home-scroll'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
          sliver: SliverList.list(
            children: [
              _HomeHeader(points: points),
              const SizedBox(height: 26),
              _OverviewCard(
                urgent: urgent,
                total: items.length,
                notificationsEnabled: notificationsEnabled,
                onAdd: onAdd,
                onReminderSettings: onReminderSettings,
              ),
              const SizedBox(height: 28),
              _SectionHeader(
                title: 'もうすぐ期限',
                action: items.length > 3 ? 'すべて見る' : null,
                onTap: onSeeAll,
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                _EmptyFoods(onAdd: onAdd)
              else
                ...items
                    .take(3)
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FoodCard(
                          item: item,
                          onConsume: () => onConsume(item),
                        ),
                      ),
                    ),
              const SizedBox(height: 16),
              const _WasteTipCard(),
            ],
          ),
        ),
      ],
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: _orange,
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.eco_rounded, color: Colors.white, size: 27),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DueBite',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .5,
                ),
              ),
              Text('おいしく、むだなく。', style: TextStyle(color: _muted, fontSize: 12)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFFECE9E2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.stars_rounded, color: _yellow, size: 20),
              const SizedBox(width: 5),
              Text(
                '$points P',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.urgent,
    required this.total,
    required this.notificationsEnabled,
    required this.onAdd,
    required this.onReminderSettings,
  });

  final int urgent;
  final int total;
  final bool notificationsEnabled;
  final VoidCallback onAdd;
  final VoidCallback onReminderSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF7A4F), Color(0xFFFF9A62)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: _orange.withValues(alpha: .24),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .2),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text(
                  '今日のチェック',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '通知設定',
                onPressed: onReminderSettings,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: .18),
                  foregroundColor: Colors.white,
                ),
                icon: Icon(
                  notificationsEnabled
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            urgent == 0 ? '期限が近い食品は\nありません' : '期限が近い食品が\n$urgent個あります',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 27,
              height: 1.25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            total == 0 ? 'まずは食品を登録してみましょう' : '早めに食べてポイントをもらおう！',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .88),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAdd,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _orange,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.camera_alt_rounded, size: 20),
            label: const Text(
              '写真でかんたん登録',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action, this.onTap});

  final String title;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onTap,
            child: Text(action!, style: const TextStyle(color: _orange)),
          ),
      ],
    );
  }
}

class FoodCard extends StatelessWidget {
  const FoodCard({
    super.key,
    required this.item,
    this.onConsume,
    this.onDelete,
  });

  final FoodItem item;
  final VoidCallback? onConsume;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final status = _ExpiryStatus.from(item.daysRemaining);
    return Semantics(
      label: '${item.name}、${status.label}',
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFEDEAE4)),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: status.softColor,
                borderRadius: BorderRadius.circular(17),
              ),
              alignment: Alignment.center,
              child: Text(
                _foodEmoji(item.category),
                style: const TextStyle(fontSize: 25),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (item.registeredWithAi)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            color: _orange,
                            size: 15,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${_formatDate(item.expiryDate)} ・ ${item.category}',
                    style: const TextStyle(color: _muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (item.isConsumed)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _greenSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.check_rounded, color: _green, size: 20),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    status.label,
                    style: TextStyle(
                      color: status.color,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: onConsume,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '食べきった',
                        style: TextStyle(
                          color: onConsume == null ? _muted : _green,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            if (onDelete != null)
              IconButton(
                tooltip: '削除',
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: _muted,
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFoods extends StatelessWidget {
  const _EmptyFoods({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          const Text('🥕', style: TextStyle(fontSize: 42)),
          const SizedBox(height: 10),
          const Text(
            '登録された食品はありません',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          const Text(
            '写真または手入力で追加できます',
            style: TextStyle(color: _muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onAdd, child: const Text('食品を登録する')),
        ],
      ),
    );
  }
}

class _WasteTipCard extends StatelessWidget {
  const _WasteTipCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _greenSoft,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded, color: _green),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DueBite ヒント',
                  style: TextStyle(color: _green, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 4),
                Text(
                  '期限の近い食品を冷蔵庫の手前に置くと、食べ忘れを減らせます。',
                  style: TextStyle(
                    color: Color(0xFF456B5C),
                    height: 1.5,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FoodListPage extends StatefulWidget {
  const FoodListPage({
    super.key,
    required this.items,
    required this.onConsume,
    required this.onDelete,
  });

  final List<FoodItem> items;
  final ValueChanged<FoodItem> onConsume;
  final ValueChanged<FoodItem> onDelete;

  @override
  State<FoodListPage> createState() => _FoodListPageState();
}

class _FoodListPageState extends State<FoodListPage> {
  _FoodFilter _filter = _FoodFilter.active;

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items.where((item) {
      return switch (_filter) {
        _FoodFilter.active => !item.isConsumed,
        _FoodFilter.consumed => item.isConsumed,
        _FoodFilter.all => true,
      };
    }).toList()..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: _PageTitle(title: '食品リスト', subtitle: '登録した食品を期限順に表示しています'),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              _FilterPill(
                label: '期限内',
                selected: _filter == _FoodFilter.active,
                onTap: () => setState(() => _filter = _FoodFilter.active),
              ),
              _FilterPill(
                label: '食べきり済み',
                selected: _filter == _FoodFilter.consumed,
                onTap: () => setState(() => _filter = _FoodFilter.consumed),
              ),
              _FilterPill(
                label: 'すべて',
                selected: _filter == _FoodFilter.all,
                onTap: () => setState(() => _filter = _FoodFilter.all),
              ),
            ],
          ),
        ),
        const SizedBox(height: 15),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text(
                    'このリストに食品はありません',
                    style: TextStyle(color: _muted),
                  ),
                )
              : ListView.separated(
                  key: PageStorageKey('food-list-${_filter.name}'),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return FoodCard(
                      item: item,
                      onConsume: item.isConsumed
                          ? null
                          : () => widget.onConsume(item),
                      onDelete: () => widget.onDelete(item),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 9),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: _ink,
        backgroundColor: _surface,
        side: BorderSide.none,
        labelStyle: TextStyle(
          color: selected ? Colors.white : _muted,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      ),
    );
  }
}

class PointsPage extends StatelessWidget {
  const PointsPage({super.key, required this.items, required this.points});

  final List<FoodItem> items;
  final int points;

  @override
  Widget build(BuildContext context) {
    final level = points ~/ 300 + 1;
    final progress = (points % 300) / 300;
    final history = items.where((item) => item.earnedPoints > 0).toList()
      ..sort((a, b) => b.consumedAt!.compareTo(a.consumedAt!));
    return CustomScrollView(
      key: const PageStorageKey('points-scroll'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          sliver: SliverList.list(
            children: [
              const _PageTitle(
                title: 'DueBite ポイント',
                subtitle: '食べきるほど、ちょっとうれしい',
              ),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _ink,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: _ink.withValues(alpha: .16),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LEVEL $level',
                      style: const TextStyle(
                        color: _yellow,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Icon(
                          Icons.stars_rounded,
                          color: _yellow,
                          size: 34,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$points',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 42,
                            height: .9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'P',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation(_yellow),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '次のレベルまで ${300 - (points % 300)} P',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              const _SectionHeader(title: 'ポイントのもらい方'),
              const SizedBox(height: 12),
              const Row(
                children: [
                  Expanded(
                    child: _PointRule(icon: '⏰', title: '前日まで', points: '+20P'),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _PointRule(
                      icon: '🍽️',
                      title: '3日前まで',
                      points: '+15P',
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _PointRule(
                      icon: '🌱',
                      title: 'それより前',
                      points: '+10P',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              const _SectionHeader(title: '獲得履歴'),
              const SizedBox(height: 10),
              if (history.isEmpty)
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '食品を食べきると、ここに履歴が表示されます。',
                    style: TextStyle(color: _muted),
                  ),
                )
              else
                ...history
                    .take(8)
                    .map(
                      (item) => ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: _greenSoft,
                          child: Text(_foodEmoji(item.category)),
                        ),
                        title: Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${_formatDate(item.consumedAt!)} に食べきり',
                        ),
                        trailing: Text(
                          '+${item.earnedPoints} P',
                          style: const TextStyle(
                            color: _green,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PointRule extends StatelessWidget {
  const _PointRule({
    required this.icon,
    required this.title,
    required this.points,
  });

  final String icon;
  final String title;
  final String points;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 25)),
          const SizedBox(height: 7),
          Text(title, style: const TextStyle(color: _muted, fontSize: 11)),
          const SizedBox(height: 3),
          Text(
            points,
            style: const TextStyle(fontWeight: FontWeight.w900, color: _orange),
          ),
        ],
      ),
    );
  }
}

class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(subtitle, style: const TextStyle(color: _muted, fontSize: 13)),
        ],
      ),
    );
  }
}

class ReminderSettings {
  const ReminderSettings({required this.enabled, required this.reminderHour});

  final bool enabled;
  final int reminderHour;
}

class NotificationSettingsSheet extends StatefulWidget {
  const NotificationSettingsSheet({
    super.key,
    required this.enabled,
    required this.reminderHour,
    required this.isSupported,
  });

  final bool enabled;
  final int reminderHour;
  final bool isSupported;

  @override
  State<NotificationSettingsSheet> createState() =>
      _NotificationSettingsSheetState();
}

class _NotificationSettingsSheetState extends State<NotificationSettingsSheet> {
  late bool _enabled;
  late int _reminderHour;

  static const _hours = [8, 9, 12, 18, 20];

  @override
  void initState() {
    super.initState();
    _enabled = widget.enabled;
    _reminderHour = widget.reminderHour;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.paddingOf(context).bottom + 22,
      ),
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD9D5CE),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            '期限のお知らせ',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          const Text('賞味期限の3日前と当日にお知らせします', style: TextStyle(color: _muted)),
          const SizedBox(height: 20),
          if (!widget.isSupported)
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4DB),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Color(0xFFA76C00)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '期限通知はiOS・Android版で利用できます。',
                      style: TextStyle(color: Color(0xFF825B12)),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF7F6F2),
                borderRadius: BorderRadius.circular(18),
              ),
              child: SwitchListTile(
                key: const Key('notification-toggle'),
                value: _enabled,
                activeTrackColor: _green,
                title: const Text(
                  '通知を受け取る',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('端末の通知設定はいつでも変更できます'),
                secondary: Icon(
                  _enabled
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_outlined,
                  color: _enabled ? _green : _muted,
                ),
                onChanged: (value) => setState(() => _enabled = value),
              ),
            ),
            const SizedBox(height: 22),
            const Text('通知する時間', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _hours
                  .map(
                    (hour) => ChoiceChip(
                      label: Text('$hour:00'),
                      selected: _reminderHour == hour,
                      onSelected: _enabled
                          ? (_) => setState(() => _reminderHour = hour)
                          : null,
                      selectedColor: _green,
                      checkmarkColor: Colors.white,
                      labelStyle: TextStyle(
                        color: _reminderHour == hour && _enabled
                            ? Colors.white
                            : _muted,
                        fontWeight: FontWeight.w700,
                      ),
                      side: BorderSide.none,
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 26),
          FilledButton(
            key: const Key('save-notification-settings'),
            onPressed: widget.isSupported
                ? () => Navigator.pop(
                    context,
                    ReminderSettings(
                      enabled: _enabled,
                      reminderHour: _reminderHour,
                    ),
                  )
                : () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: _ink,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(widget.isSupported ? '設定を保存' : '閉じる'),
          ),
        ],
      ),
    );
  }
}

class _AddFoodSheet extends StatelessWidget {
  const _AddFoodSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.paddingOf(context).bottom + 22,
      ),
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD9D5CE),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            '食品を登録',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          const Text('登録方法を選んでください', style: TextStyle(color: _muted)),
          const SizedBox(height: 22),
          _AddOption(
            icon: Icons.camera_alt_rounded,
            iconColor: _orange,
            backgroundColor: _orangeSoft,
            title: '写真を撮ってAI登録',
            subtitle: '商品名と賞味期限をAIが読み取ります',
            badge: 'おすすめ',
            onTap: () => Navigator.pop(context, _AddAction.camera),
          ),
          const SizedBox(height: 10),
          _AddOption(
            icon: Icons.photo_library_outlined,
            iconColor: _green,
            backgroundColor: _greenSoft,
            title: 'アルバムから選ぶ',
            subtitle: '保存済みの写真をAIで読み取ります',
            onTap: () => Navigator.pop(context, _AddAction.gallery),
          ),
          const SizedBox(height: 10),
          _AddOption(
            icon: Icons.forum_rounded,
            iconColor: const Color(0xFF6750A4),
            backgroundColor: const Color(0xFFEDE7F7),
            title: 'AIと会話して登録',
            subtitle: '質問に答えて商品と期限を特定します',
            badge: 'NEW',
            onTap: () => Navigator.pop(context, _AddAction.agent),
          ),
          const SizedBox(height: 10),
          _AddOption(
            icon: Icons.edit_calendar_outlined,
            iconColor: const Color(0xFF476A85),
            backgroundColor: const Color(0xFFE4EFF7),
            title: '手入力で登録',
            subtitle: '商品名と日付を自分で入力します',
            onTap: () => Navigator.pop(context, _AddAction.manual),
          ),
        ],
      ),
    );
  }
}

class _AddOption extends StatelessWidget {
  const _AddOption({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFAF9F6),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 51,
                height: 51,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _orangeSoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              badge!,
                              style: const TextStyle(
                                color: _orange,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: _muted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalyzingDialog extends StatelessWidget {
  const _AnalyzingDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 58,
                height: 58,
                child: CircularProgressIndicator(
                  color: _orange,
                  strokeWidth: 5,
                ),
              ),
              SizedBox(height: 22),
              Text(
                'AIが写真を読み取り中…',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 8),
              Text(
                '商品名と賞味期限を探しています',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProductAgentPage extends StatefulWidget {
  const ProductAgentPage({super.key, required this.service});

  final AiExpiryService service;

  @override
  State<ProductAgentPage> createState() => _ProductAgentPageState();
}

class _ProductAgentPageState extends State<ProductAgentPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <ProductChatMessage>[
    const ProductChatMessage(
      role: 'assistant',
      text: '一緒に商品を特定しましょう。商品名、種類、パッケージの特徴など、分かることを教えてください。',
    ),
  ];
  ProductAgentResult? _candidate;
  bool _sending = false;
  String? _errorMessage;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _messages.add(ProductChatMessage(role: 'user', text: text));
      _sending = true;
      _errorMessage = null;
    });
    _inputController.clear();
    _scrollToBottom();

    await _requestAgent();
  }

  Future<void> _requestAgent() async {
    try {
      final result = await widget.service.identifyProduct(_messages);
      if (!mounted) return;
      setState(() {
        _messages.add(
          ProductChatMessage(role: 'assistant', text: result.reply),
        );
        _candidate = result.ready ? result : null;
        _sending = false;
      });
    } on AiExpiryException catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _errorMessage = 'AIとの通信に失敗しました。もう一度お試しください';
      });
    }
    _scrollToBottom();
  }

  Future<void> _retry() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _errorMessage = null;
    });
    await _requestAgent();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  void _registerCandidate() {
    final candidate = _candidate;
    if (candidate == null || candidate.expiryDate == null) return;
    Navigator.pop(
      context,
      FoodDraft(
        name: candidate.name,
        category: candidate.category,
        expiryDate: candidate.expiryDate!,
        registeredWithAi: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
        ),
        title: const Column(
          children: [
            Text(
              'AI Product Finder',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            Text(
              'DueBite Agent',
              style: TextStyle(color: _muted, fontSize: 10),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                children: [
                  _AgentIntroCard(isDemo: !widget.service.isConfigured),
                  const SizedBox(height: 18),
                  for (final message in _messages) ...[
                    _AgentMessageBubble(message: message),
                    const SizedBox(height: 10),
                  ],
                  if (_sending) ...[
                    const _AgentTypingBubble(),
                    const SizedBox(height: 10),
                  ],
                  if (_errorMessage != null) ...[
                    _AgentErrorCard(message: _errorMessage!, onRetry: _retry),
                    const SizedBox(height: 10),
                  ],
                  if (_candidate != null) ...[
                    const SizedBox(height: 4),
                    _AgentCandidateCard(
                      candidate: _candidate!,
                      onRegister: _registerCandidate,
                    ),
                  ],
                ],
              ),
            ),
            _AgentComposer(
              controller: _inputController,
              enabled: !_sending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentIntroCard extends StatelessWidget {
  const _AgentIntroCard({required this.isDemo});

  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEDE7F7), Color(0xFFFFF1E9)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: _surface,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFF6750A4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isDemo ? 'デモエージェント' : 'Gemini エージェント',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isDemo ? 'DEMO' : 'ONLINE',
                        style: const TextStyle(
                          color: Color(0xFF6750A4),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  '分からない部分を質問し、登録に必要な情報を整理します。',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentMessageBubble extends StatelessWidget {
  const _AgentMessageBubble({required this.message});

  final ProductChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? _orange : _surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          border: isUser ? null : Border.all(color: const Color(0xFFE8E5DE)),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser ? Colors.white : _ink,
            height: 1.45,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _AgentTypingBubble extends StatelessWidget {
  const _AgentTypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8E5DE)),
        ),
        child: const SizedBox(
          width: 48,
          child: LinearProgressIndicator(
            minHeight: 3,
            color: Color(0xFF6750A4),
            backgroundColor: Color(0xFFEDE7F7),
          ),
        ),
      ),
    );
  }
}

class _AgentErrorCard extends StatelessWidget {
  const _AgentErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFECE8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('再試行')),
        ],
      ),
    );
  }
}

class _AgentCandidateCard extends StatelessWidget {
  const _AgentCandidateCard({
    required this.candidate,
    required this.onRegister,
  });

  final ProductAgentResult candidate;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final expiryDate = candidate.expiryDate!;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _greenSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _green.withValues(alpha: .16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.task_alt_rounded, color: _green),
              SizedBox(width: 8),
              Text(
                '商品を特定しました',
                style: TextStyle(color: _green, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            candidate.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AgentResultChip(
                icon: Icons.event_rounded,
                label: _formatDateLong(expiryDate),
              ),
              _AgentResultChip(
                icon: Icons.category_outlined,
                label: candidate.category,
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRegister,
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              'この内容で登録',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentResultChip extends StatelessWidget {
  const _AgentResultChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _green),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _AgentComposer extends StatelessWidget {
  const _AgentComposer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        12,
        14,
        MediaQuery.paddingOf(context).bottom + 10,
      ),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: Color(0xFFE8E5DE))),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('agent-message-field'),
                  controller: controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: const InputDecoration(
                    hintText: '例：青いパックの牛乳です',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              IconButton.filled(
                key: const Key('agent-send-button'),
                onPressed: enabled ? onSend : null,
                style: IconButton.styleFrom(
                  backgroundColor: _orange,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFD7D3CD),
                  minimumSize: const Size(50, 50),
                ),
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            '入力内容は商品特定のためAIへ送信されます。期限は必ず表示と照合してください。',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}

class FoodDraft {
  const FoodDraft({
    required this.name,
    required this.category,
    required this.expiryDate,
    required this.registeredWithAi,
  });

  final String name;
  final String category;
  final DateTime expiryDate;
  final bool registeredWithAi;
}

class FoodEditorPage extends StatefulWidget {
  const FoodEditorPage({super.key, this.photo, this.aiResult});

  final XFile? photo;
  final AiExpiryResult? aiResult;

  @override
  State<FoodEditorPage> createState() => _FoodEditorPageState();
}

class _FoodEditorPageState extends State<FoodEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late String _category;
  late DateTime _expiryDate;

  static const _categories = [
    '乳製品',
    '飲み物',
    '冷蔵品',
    '肉・魚',
    '野菜・果物',
    'お惣菜',
    'その他',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.aiResult?.name ?? '');
    _category = _categories.contains(widget.aiResult?.category)
        ? widget.aiResult!.category
        : 'その他';
    _expiryDate =
        widget.aiResult?.expiryDate ??
        DateTime.now().add(const Duration(days: 7));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: '賞味期限を選択',
      cancelText: 'キャンセル',
      confirmText: '決定',
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      FoodDraft(
        name: _nameController.text.trim(),
        category: _category,
        expiryDate: _expiryDate,
        registeredWithAi: widget.aiResult != null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.aiResult;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(result == null ? '食品を入力' : '読み取り結果を確認'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              if (widget.photo != null) _PhotoPreview(photo: widget.photo!),
              if (result != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: result.isDemo ? const Color(0xFFFFF4DB) : _greenSoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: result.isDemo ? const Color(0xFFA76C00) : _green,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          result.isDemo
                              ? 'デモ解析結果です。API設定後は実際の写真を解析します。'
                              : 'AI読み取り精度 ${(result.confidence * 100).round()}%。内容をご確認ください。',
                          style: TextStyle(
                            color: result.isDemo
                                ? const Color(0xFF825B12)
                                : const Color(0xFF456B5C),
                            fontSize: 12.5,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 25),
              const _InputLabel(label: '商品名', required: true),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('food-name-field'),
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: '例：プレーンヨーグルト',
                  prefixIcon: Icon(Icons.shopping_bag_outlined),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? '商品名を入力してください'
                    : null,
              ),
              const SizedBox(height: 21),
              const _InputLabel(label: '賞味期限', required: true),
              const SizedBox(height: 8),
              InkWell(
                key: const Key('expiry-date-field'),
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(16),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 17,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F0EB),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_outlined, color: _muted),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Text(
                          _formatDateLong(_expiryDate),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: _muted),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 21),
              const _InputLabel(label: 'カテゴリー'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: _categories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _category = value ?? 'その他'),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                key: const Key('save-food-button'),
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: _orange,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                icon: const Icon(Icons.check_rounded),
                label: const Text(
                  'この内容で登録する',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'AIの読み取り結果は間違う場合があります。保存前に日付をご確認ください。',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.photo});

  final XFile photo;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 184,
        child: FutureBuilder<Uint8List>(
          future: photo.readAsBytes(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return Image.memory(
                snapshot.data!,
                width: double.infinity,
                fit: BoxFit.cover,
              );
            }
            return const ColoredBox(
              color: Color(0xFFEDEAE4),
              child: Center(child: CircularProgressIndicator(color: _orange)),
            );
          },
        ),
      ),
    );
  }
}

class _InputLabel extends StatelessWidget {
  const _InputLabel({required this.label, this.required = false});

  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        if (required) ...[
          const SizedBox(width: 6),
          const Text(
            '必須',
            style: TextStyle(
              color: _orange,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ],
    );
  }
}

class _PointEarnedDialog extends StatelessWidget {
  const _PointEarnedDialog({required this.points, required this.totalPoints});

  final int points;
  final int totalPoints;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 30, 26, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                color: Color(0xFFFFF3CF),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.stars_rounded, color: _yellow, size: 46),
            ),
            const SizedBox(height: 18),
            const Text(
              '食べきり達成！',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              '+$points ポイント',
              style: const TextStyle(
                color: _orange,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text('合計 $totalPoints P', style: const TextStyle(color: _muted)),
            const SizedBox(height: 22),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _ink,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'やった！',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _AddAction { camera, gallery, agent, manual }

enum _FoodFilter { active, consumed, all }

class _ExpiryStatus {
  const _ExpiryStatus(this.label, this.color, this.softColor);

  final String label;
  final Color color;
  final Color softColor;

  factory _ExpiryStatus.from(int days) {
    if (days < 0) {
      return const _ExpiryStatus('期限切れ', Color(0xFFD44545), Color(0xFFFFE7E7));
    }
    if (days == 0) {
      return const _ExpiryStatus('今日まで', Color(0xFFD44545), Color(0xFFFFE7E7));
    }
    if (days == 1) return const _ExpiryStatus('あと1日', _orange, _orangeSoft);
    if (days <= 3) return _ExpiryStatus('あと$days日', _orange, _orangeSoft);
    return _ExpiryStatus('あと$days日', _green, _greenSoft);
  }
}

String _foodEmoji(String category) => switch (category) {
  '乳製品' => '🥛',
  '飲み物' => '🧃',
  '冷蔵品' => '🧊',
  '肉・魚' => '🐟',
  '野菜・果物' => '🥕',
  'お惣菜' => '🍱',
  _ => '🍽️',
};

String _formatDate(DateTime date) => '${date.month}月${date.day}日';

String _formatDateLong(DateTime date) {
  const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
  return '${date.year}年${date.month}月${date.day}日（${weekdays[date.weekday - 1]}）';
}
