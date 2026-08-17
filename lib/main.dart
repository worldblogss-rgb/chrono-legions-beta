import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme/chrono_assets.dart';
import 'theme/chrono_theme.dart';
import 'widgets/battlefield_backdrop.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const WcoApp());
}

enum GameMode { freeTest, bot }

enum BotDifficulty { easy, normal }

enum Faction { rome, carthage }

enum ResourceType { earth, sea, air }

enum OrderEffect { none, forceTwo, healTwo, damageOne, drawOne, diceForce }

const List<Color> _attackColors = [
  Color(0xFFFF5252),
  Color(0xFF40C4FF),
  Color(0xFFFFD740),
  Color(0xFF69F0AE),
  Color(0xFFE040FB),
  Color(0xFFFF6E40),
];

const int _maxRounds = 15;
const int _maxHandSize = 7;

bool _isWall(CardDefinition card) => card.wall;

String _cardArtPath(String code) => 'assets/images/v08/$code.png';

bool _commanderIsProtected(
  List<CardInstance> battle,
  List<CardInstance> support,
) =>
    battle.isNotEmpty || support.any((card) => _isWall(card.card));

extension FactionText on Faction {
  String get name => this == Faction.rome ? 'Roma' : 'Cartago';

  String get commander => this == Faction.rome
      ? 'Escipión el Africano'
      : 'Aníbal Barca';

  Color get color =>
      this == Faction.rome ? const Color(0xFF8C2F2B) : const Color(0xFF275D59);

  Faction get opponent =>
      this == Faction.rome ? Faction.carthage : Faction.rome;
}

extension FactionArt on Faction {
  String get commanderPortrait =>
      this == Faction.rome ? ChronoAssets.scipio : ChronoAssets.hannibal;

  String get showcasePortrait =>
      this == Faction.rome ? ChronoAssets.scipio : ChronoAssets.hannibalGold;
}

bool _canAttackFromSupport(CardDefinition card) =>
    card.longRange ||
    (card.type == 'Fortificación' && (card.force ?? 0) > 0);

int _supportDefenseCapacity(CardDefinition card) {
  if (!_isWall(card)) return 1;
  return (card.defense ?? 0) >= 7 ? 3 : 2;
}

class CardDefinition {
  const CardDefinition({
    required this.code,
    required this.name,
    required this.type,
    required this.copies,
    required this.cost,
    required this.earth,
    required this.sea,
    required this.generic,
    required this.role,
    required this.force,
    required this.defense,
    required this.line,
    required this.effect,
    required this.icons,
    required this.domain,
    required this.attacksEarth,
    required this.attacksSea,
    required this.longRange,
    required this.precision,
    required this.maneuver,
    required this.wall,
    required this.orderEffect,
  });

  factory CardDefinition.fromJson(Map<String, dynamic> json) {
    int number(String key) => (json[key] as num?)?.toInt() ?? 0;

    return CardDefinition(
      code: json['code'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      copies: number('copies'),
      cost: number('cost'),
      earth: number('earth'),
      sea: number('sea'),
      generic: number('generic'),
      role: json['role'] as String? ?? '',
      force: (json['force'] as num?)?.toInt(),
      defense: (json['defense'] as num?)?.toInt(),
      line: json['line'] as String? ?? '',
      effect: json['effect'] as String? ?? '',
      icons: json['icons'] as String? ?? '',
      domain: json['domain'] as String? ?? 'Sin dominio',
      attacksEarth: json['attacksEarth'] as bool? ?? false,
      attacksSea: json['attacksSea'] as bool? ?? false,
      longRange: json['longRange'] as bool? ?? false,
      precision: json['precision'] as bool? ?? false,
      maneuver: json['maneuver'] as bool? ?? false,
      wall: json['wall'] as bool? ?? false,
      orderEffect: OrderEffect.values.firstWhere(
        (effect) => effect.name == (json['orderEffect'] as String? ?? 'none'),
        orElse: () => OrderEffect.none,
      ),
    );
  }

  final String code;
  final String name;
  final String type;
  final int copies;
  final int cost;
  final int earth;
  final int sea;
  final int generic;
  final String role;
  final int? force;
  final int? defense;
  final String line;
  final String effect;
  final String icons;
  final String domain;
  final bool attacksEarth;
  final bool attacksSea;
  final bool longRange;
  final bool precision;
  final bool maneuver;
  final bool wall;
  final OrderEffect orderEffect;
}

class ResourceToken {
  const ResourceToken(this.type, {this.used = false});

  final ResourceType type;
  final bool used;

  ResourceToken copyWith({bool? used}) =>
      ResourceToken(type, used: used ?? this.used);
}

class CardInstance {
  CardInstance(this.card, {this.preparing = true});

  final CardDefinition card;
  bool preparing;
  bool tapped = false;
  int damage = 0;
  int turnForceBonus = 0;
  int nextAttackForceBonus = 0;

  int get effectiveForce =>
      max(0, (card.force ?? 0) + turnForceBonus + nextAttackForceBonus);

  String get orderBadge {
    if (nextAttackForceBonus > 0) return '🎲⚔+$nextAttackForceBonus';
    if (turnForceBonus > 0) return '⚔+$turnForceBonus';
    return '';
  }

  void clearOrderBonuses() {
    turnForceBonus = 0;
    nextAttackForceBonus = 0;
  }
}

class PendingOrder {
  const PendingOrder({required this.card, required this.playerSide});

  final CardDefinition card;
  final bool playerSide;
}

int diceOrderBonus(int roll) {
  if (roll < 1 || roll > 6) {
    throw RangeError.range(roll, 1, 6, 'roll');
  }
  return (roll + 1) ~/ 2;
}

class AttackAssignment {
  const AttackAssignment({required this.attacker, this.target});

  final CardInstance attacker;
  final CardInstance? target;
}

class CombatReport {
  const CombatReport({
    required this.title,
    required this.round,
    required this.lines,
  });

  final String title;
  final int round;
  final List<CombatReportLine> lines;
}

class CombatReportLine {
  const CombatReportLine(this.text, {this.color = Colors.white});

  final String text;
  final Color color;
}

class WcoApp extends StatelessWidget {
  const WcoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chrono Legions — Roma vs Cartago',
      theme: ChronoTheme.dark,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GameMode _mode = GameMode.bot;
  BotDifficulty _botDifficulty = BotDifficulty.easy;
  String _playerName = 'Jugador';

  Future<void> _editPlayerName() async {
    final controller = TextEditingController(text: _playerName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nombre del jugador'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          inputFormatters: [LengthLimitingTextInputFormatter(18)],
          decoration: const InputDecoration(
            labelText: 'Nombre local',
            hintText: 'Ejemplo: Diego',
            helperText: 'Por ahora se usa solamente en este dispositivo.',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('GUARDAR'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || result == null || result.isEmpty) return;
    setState(() => _playerName = result);
  }

  void _chooseFaction() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FactionScreen(
          mode: _mode,
          botDifficulty: _botDifficulty,
        ),
      ),
    );
  }

  void _startWith(Faction faction) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          mode: _mode,
          playerFaction: faction,
          botDifficulty: _botDifficulty,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BattlefieldBackdrop(
        assetPath: ChronoAssets.menu,
        overlayOpacity: .42,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 930;
              final topBar = _V08TopBar(
                playerName: _playerName,
                onEditPlayer: _editPlayerName,
              );
              final duel = _DuelShowcase(
                onRome: () => _startWith(Faction.rome),
                onCarthage: () => _startWith(Faction.carthage),
                onChoose: _chooseFaction,
              );
              final settings = _BattleSettingsPanel(
                playerName: _playerName,
                mode: _mode,
                difficulty: _botDifficulty,
                onEditPlayer: _editPlayerName,
                onModeChanged: (value) => setState(() => _mode = value),
                onDifficultyChanged: (value) =>
                    setState(() => _botDifficulty = value),
                onChoose: _chooseFaction,
              );
              final decks = _QuickDeckPanel(
                onRome: () => _startWith(Faction.rome),
                onCarthage: () => _startWith(Faction.carthage),
              );

              if (wide) {
                return Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    children: [
                      topBar,
                      const SizedBox(height: 13),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 7, child: duel),
                            const SizedBox(width: 13),
                            Expanded(
                              flex: 4,
                              child: Column(
                                children: [
                                  settings,
                                  const SizedBox(height: 13),
                                  Expanded(child: decks),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    topBar,
                    const SizedBox(height: 12),
                    SizedBox(height: 430, child: duel),
                    const SizedBox(height: 12),
                    settings,
                    const SizedBox(height: 12),
                    decks,
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // Referencia funcional de la pantalla anterior durante la beta.
  // ignore: unused_element
  Widget _legacyBuild(BuildContext context) {
    Widget playerControls() {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ChronoPalette.panel.withAlpha(235),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ChronoPalette.gold.withAlpha(90)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PREPARAR BATALLA',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
                color: ChronoPalette.parchment,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: ChronoPalette.rome,
                  child: Text(
                    _playerName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'JUGADOR LOCAL',
                        style: TextStyle(
                          fontSize: 8,
                          color: ChronoPalette.muted,
                          letterSpacing: 1.1,
                        ),
                      ),
                      Text(
                        _playerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Cambiar nombre',
                  onPressed: _editPlayerName,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  avatar: const Icon(Icons.smart_toy_outlined, size: 17),
                  label: const Text('Contra bot'),
                  selected: _mode == GameMode.bot,
                  onSelected: (_) => setState(() => _mode = GameMode.bot),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.swap_horiz, size: 17),
                  label: const Text('Prueba libre'),
                  selected: _mode == GameMode.freeTest,
                  onSelected: (_) =>
                      setState(() => _mode = GameMode.freeTest),
                ),
                if (_mode == GameMode.bot)
                  SegmentedButton<BotDifficulty>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: BotDifficulty.easy,
                        label: Text('Fácil'),
                      ),
                      ButtonSegment(
                        value: BotDifficulty.normal,
                        label: Text('Normal'),
                      ),
                    ],
                    selected: {_botDifficulty},
                    onSelectionChanged: (selection) => setState(
                      () => _botDifficulty = selection.first,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _chooseFaction,
                icon: const Icon(Icons.sports_martial_arts),
                label: const Text('ELEGIR CIVILIZACIÓN Y COMENZAR'),
              ),
            ),
          ],
        ),
      );
    }

    Widget deckShelf() {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ChronoPalette.panel.withAlpha(220),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.style, size: 18, color: ChronoPalette.gold),
                SizedBox(width: 7),
                Text(
                  'MAZOS DE PRUEBA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                Spacer(),
                Text(
                  '30 CARTAS',
                  style: TextStyle(
                    fontSize: 9,
                    color: ChronoPalette.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 154,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _FavoriteDeckCard(
                    faction: Faction.rome,
                    onPlay: () => _startWith(Faction.rome),
                  ),
                  const SizedBox(width: 10),
                  _FavoriteDeckCard(
                    faction: Faction.carthage,
                    onPlay: () => _startWith(Faction.carthage),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: BattlefieldBackdrop(
        assetPath: ChronoAssets.menu,
        overlayOpacity: .60,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;

              final hero = Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      ChronoPalette.rome.withAlpha(105),
                      ChronoPalette.panel.withAlpha(225),
                      ChronoPalette.carthage.withAlpha(80),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: ChronoPalette.gold.withAlpha(120)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        _ChronoMark(size: 62),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CHRONO LEGIONS',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2.4,
                                ),
                              ),
                              Text(
                                'LA HISTORIA ENTRA EN BATALLA',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: ChronoPalette.parchment,
                                  letterSpacing: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Text(
                      'ANTIGÜEDAD',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: ChronoPalette.gold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'ROMA  VS  CARTAGO',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 9),
                    const Text(
                      'Dos civilizaciones. Dos comandantes. Un campo de batalla dividido en Batalla y Apoyo.',
                      style: TextStyle(
                        color: ChronoPalette.parchmentMuted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 38,
                      child: Image.asset(
                        ChronoAssets.uiIcons,
                        fit: BoxFit.contain,
                        alignment: Alignment.centerLeft,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _HomeFactionBadge(
                            faction: Faction.rome,
                            subtitle: 'Disciplina y resistencia',
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: _HomeFactionBadge(
                            faction: Faction.carthage,
                            subtitle: 'Movilidad y presión',
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Text(
                      'CL_V0.8 · EDGE BETA · INTERFAZ TÁCTICA',
                      style: TextStyle(
                        fontSize: 9,
                        color: ChronoPalette.muted,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              );

              final controls = Column(
                children: [
                  playerControls(),
                  const SizedBox(height: 12),
                  deckShelf(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: ChronoPalette.panel.withAlpha(205),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CAMPAÑA ACTIVA',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              color: ChronoPalette.parchment,
                            ),
                          ),
                          SizedBox(height: 10),
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: _EraCard(
                                    title: 'ANTIGÜEDAD',
                                    subtitle: 'Roma vs Cartago',
                                    icon: Icons.account_balance,
                                    active: true,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: _EraCard(
                                    title: 'EDAD MEDIA',
                                    subtitle: 'Próximamente',
                                    icon: Icons.shield_outlined,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );

              if (wide) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(flex: 5, child: hero),
                      const SizedBox(width: 14),
                      Expanded(flex: 6, child: controls),
                    ],
                  ),
                );
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    SizedBox(height: 390, child: hero),
                    const SizedBox(height: 12),
                    SizedBox(height: 540, child: controls),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}


class _V08TopBar extends StatelessWidget {
  const _V08TopBar({
    required this.playerName,
    required this.onEditPlayer,
  });

  final String playerName;
  final VoidCallback onEditPlayer;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 17),
      decoration: BoxDecoration(
        color: const Color(0xE8121715),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ChronoPalette.gold.withAlpha(85)),
      ),
      child: Row(
        children: [
          const _ChronoMark(size: 48),
          const SizedBox(width: 11),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CHRONO LEGIONS',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.1,
                ),
              ),
              Text(
                'LA HISTORIA ENTRA EN BATALLA',
                style: TextStyle(
                  fontSize: 8,
                  color: ChronoPalette.parchmentMuted,
                  letterSpacing: 1.35,
                ),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: 180,
            height: 34,
            child: Image.asset(
              ChronoAssets.uiIcons,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onEditPlayer,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: ChronoPalette.gold.withAlpha(24),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: ChronoPalette.gold.withAlpha(90)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_outline, size: 14),
                  const SizedBox(width: 5),
                  Text(
                    playerName,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 9),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: ChronoPalette.gold.withAlpha(28),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ChronoPalette.gold.withAlpha(100)),
            ),
            child: const Text(
              'CL V0.8 · VISUAL',
              style: TextStyle(
                fontSize: 8,
                letterSpacing: 1.05,
                fontWeight: FontWeight.w900,
                color: ChronoPalette.gold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BattleSettingsPanel extends StatelessWidget {
  const _BattleSettingsPanel({
    required this.playerName,
    required this.mode,
    required this.difficulty,
    required this.onEditPlayer,
    required this.onModeChanged,
    required this.onDifficultyChanged,
    required this.onChoose,
  });

  final String playerName;
  final GameMode mode;
  final BotDifficulty difficulty;
  final VoidCallback onEditPlayer;
  final ValueChanged<GameMode> onModeChanged;
  final ValueChanged<BotDifficulty> onDifficultyChanged;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final cleanName = playerName.trim();
    final initial = cleanName.isEmpty ? 'J' : cleanName[0].toUpperCase();
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xEE141917),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ChronoPalette.gold.withAlpha(105)),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 22, offset: Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [ChronoPalette.rome, Color(0xFF4B1715)],
                  ),
                  border: Border.all(color: ChronoPalette.gold),
                ),
                child: Text(
                  initial,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'COMANDANTE LOCAL',
                      style: TextStyle(
                        fontSize: 8,
                        letterSpacing: 1.3,
                        color: ChronoPalette.gold,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      cleanName.isEmpty ? 'Jugador' : cleanName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Editar comandante',
                onPressed: onEditPlayer,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'MODO DE PARTIDA',
            style: TextStyle(
              fontSize: 8,
              letterSpacing: 1.25,
              fontWeight: FontWeight.w900,
              color: ChronoPalette.parchmentMuted,
            ),
          ),
          const SizedBox(height: 7),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<GameMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: GameMode.bot,
                  icon: Icon(Icons.smart_toy_outlined, size: 16),
                  label: Text('Bot'),
                ),
                ButtonSegment(
                  value: GameMode.freeTest,
                  icon: Icon(Icons.swap_horiz, size: 16),
                  label: Text('Prueba libre'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) => onModeChanged(selection.first),
            ),
          ),
          if (mode == GameMode.bot) ...[
            const SizedBox(height: 9),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'DIFICULTAD',
                    style: TextStyle(
                      fontSize: 8,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w900,
                      color: ChronoPalette.parchmentMuted,
                    ),
                  ),
                ),
                SegmentedButton<BotDifficulty>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: BotDifficulty.easy, label: Text('Fácil')),
                    ButtonSegment(
                      value: BotDifficulty.normal,
                      label: Text('Normal'),
                    ),
                  ],
                  selected: {difficulty},
                  onSelectionChanged: (selection) =>
                      onDifficultyChanged(selection.first),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onChoose,
              icon: const Icon(Icons.sports_martial_arts),
              label: const Text('ELEGIR CIVILIZACIÓN'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DuelShowcase extends StatelessWidget {
  const _DuelShowcase({
    required this.onRome,
    required this.onCarthage,
    required this.onChoose,
  });

  final VoidCallback onRome;
  final VoidCallback onCarthage;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xE8151917),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ChronoPalette.gold.withAlpha(125)),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 26, offset: Offset(0, 12)),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: _CommanderHalf(
                    faction: Faction.rome,
                    subtitle: 'DISCIPLINA · FORMACIÓN · RESISTENCIA',
                    onTap: onRome,
                  ),
                ),
                Expanded(
                  child: _CommanderHalf(
                    faction: Faction.carthage,
                    subtitle: 'MOVILIDAD · MANIOBRA · PRESIÓN',
                    onTap: onCarthage,
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withAlpha(65),
                      Colors.transparent,
                      Colors.black.withAlpha(120),
                    ],
                    stops: const [0, .54, 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 18,
            left: 20,
            right: 20,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(145),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: ChronoPalette.gold.withAlpha(90)),
                  ),
                  child: const Text(
                    'CAMPAÑA · ANTIGÜEDAD',
                    style: TextStyle(
                      fontSize: 8,
                      letterSpacing: 1.35,
                      color: ChronoPalette.gold,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const Spacer(),
                const Text(
                  '30 CARTAS POR MAZO',
                  style: TextStyle(
                    fontSize: 8,
                    letterSpacing: 1.1,
                    color: ChronoPalette.parchmentMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 78,
              height: 78,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xE5121715),
                border: Border.all(color: ChronoPalette.gold, width: 2),
                boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 18)],
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'VS',
                    style: TextStyle(
                      fontSize: 24,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w900,
                      color: ChronoPalette.gold,
                    ),
                  ),
                  Text(
                    '218 A.C.',
                    style: TextStyle(
                      fontSize: 7,
                      letterSpacing: .9,
                      color: ChronoPalette.parchmentMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 92,
            child: Center(
              child: FilledButton.icon(
                onPressed: onChoose,
                icon: const Icon(Icons.shield_outlined),
                label: const Text('ENTRAR AL CAMPO DE BATALLA'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommanderHalf extends StatelessWidget {
  const _CommanderHalf({
    required this.faction,
    required this.subtitle,
    required this.onTap,
  });

  final Faction faction;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: faction.color,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              faction.showcasePortrait,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, _, _) => ColoredBox(color: faction.color),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    faction.color.withAlpha(20),
                    Colors.transparent,
                    const Color(0xF00D1110),
                  ],
                  stops: const [0, .52, 1],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Column(
                crossAxisAlignment: faction == Faction.rome
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: faction == Faction.rome
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.end,
                    children: [
                      Icon(
                        faction == Faction.rome
                            ? Icons.account_balance
                            : Icons.change_history,
                        size: 17,
                        color: ChronoPalette.gold,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        faction.name.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.8,
                          color: ChronoPalette.gold,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    faction.commander,
                    textAlign:
                        faction == Faction.rome ? TextAlign.left : TextAlign.right,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      shadows: [Shadow(color: Colors.black, blurRadius: 7)],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    textAlign:
                        faction == Faction.rome ? TextAlign.left : TextAlign.right,
                    style: const TextStyle(
                      fontSize: 7,
                      letterSpacing: .9,
                      color: ChronoPalette.parchmentMuted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickDeckPanel extends StatelessWidget {
  const _QuickDeckPanel({required this.onRome, required this.onCarthage});

  final VoidCallback onRome;
  final VoidCallback onCarthage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xE5141917),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.style, size: 18, color: ChronoPalette.gold),
              SizedBox(width: 7),
              Text(
                'ACCESO RÁPIDO A MAZOS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.15,
                ),
              ),
              Spacer(),
              Text(
                'V0.8',
                style: TextStyle(
                  fontSize: 9,
                  color: ChronoPalette.gold,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _QuickDeckTile(faction: Faction.rome, onTap: onRome),
          const SizedBox(height: 9),
          _QuickDeckTile(faction: Faction.carthage, onTap: onCarthage),
          const SizedBox(height: 10),
          const Row(
            children: [
              Icon(Icons.image_outlined, size: 14, color: ChronoPalette.gold),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Cada carta incluye ahora una ilustración individual.',
                  style: TextStyle(
                    fontSize: 8,
                    color: ChronoPalette.parchmentMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickDeckTile extends StatelessWidget {
  const _QuickDeckTile({required this.faction, required this.onTap});

  final Faction faction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: Material(
        color: faction.color.withAlpha(190),
        borderRadius: BorderRadius.circular(15),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                right: 0,
                top: -34,
                width: 135,
                height: 176,
                child: Image.asset(
                  faction.commanderPortrait,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      faction.color,
                      faction.color.withAlpha(225),
                      const Color(0x24121715),
                    ],
                    stops: const [0, .57, 1],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MAZO ${faction.name.toUpperCase()}',
                            style: const TextStyle(
                              fontSize: 11,
                              letterSpacing: 1.05,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            faction.commander,
                            style: const TextStyle(
                              fontSize: 9,
                              color: ChronoPalette.parchmentMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '30 cartas · listo para jugar',
                            style: TextStyle(fontSize: 8, color: ChronoPalette.gold),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.play_circle_fill, color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeFactionBadge extends StatelessWidget {
  const _HomeFactionBadge({
    required this.faction,
    required this.subtitle,
  });

  final Faction faction;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: faction.color.withAlpha(125),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: ChronoPalette.gold.withAlpha(90)),
      ),
      child: Row(
        children: [
          ClipOval(
            child: Container(
              width: 34,
              height: 34,
              color: Colors.black26,
              child: Image.asset(
                faction.commanderPortrait,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  faction == Faction.rome
                      ? Icons.account_balance
                      : Icons.change_history,
                  color: ChronoPalette.parchment,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  faction.name.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 8,
                    color: ChronoPalette.parchmentMuted,
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

class _ChronoMark extends StatelessWidget {
  const _ChronoMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        ChronoAssets.logo,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) => Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.hourglass_bottom,
              size: size,
              color: ChronoPalette.gold,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Icon(
                Icons.shield,
                size: size * .43,
                color: ChronoPalette.rome,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoriteDeckCard extends StatelessWidget {
  const _FavoriteDeckCard({required this.faction, required this.onPlay});

  final Faction faction;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 310,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [faction.color, const Color(0xFF202724)],
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 104,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ChronoPalette.gold.withAlpha(150)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  faction.showcasePortrait,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    faction == Faction.rome
                        ? Icons.account_balance
                        : Icons.change_history,
                    size: 42,
                    color: ChronoPalette.parchment,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.star,
                          size: 16,
                          color: Color(0xFFFFD740),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          faction.name.toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      faction.commander,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('JUGAR'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EraCard extends StatelessWidget {
  const _EraCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.active = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Card(
        color: active ? const Color(0xFF4B3826) : const Color(0xFF202724),
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: active ? const Color(0xFFD6A25E) : Colors.white12,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(
                active ? icon : Icons.lock_outline,
                color: active ? const Color(0xFFD6A25E) : Colors.white38,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FactionScreen extends StatelessWidget {
  const FactionScreen({
    super.key,
    required this.mode,
    required this.botDifficulty,
  });

  final GameMode mode;
  final BotDifficulty botDifficulty;

  void _start(BuildContext context, Faction faction) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          mode: mode,
          playerFaction: faction,
          botDifficulty: botDifficulty,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Elige tu civilización')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Wrap(
            spacing: 24,
            runSpacing: 24,
            alignment: WrapAlignment.center,
            children: [
              _FactionCard(
                faction: Faction.rome,
                description: 'Formación, resistencia, disciplina y reparación.',
                onTap: () => _start(context, Faction.rome),
              ),
              _FactionCard(
                faction: Faction.carthage,
                description: 'Movilidad, flanqueo y coordinación de clases.',
                onTap: () => _start(context, Faction.carthage),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FactionCard extends StatelessWidget {
  const _FactionCard({
    required this.faction,
    required this.description,
    required this.onTap,
  });

  final Faction faction;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 410,
      height: 218,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  faction.color,
                  faction.color.withAlpha(220),
                  const Color(0xFF171C1A),
                ],
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 116,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: ChronoPalette.gold, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    faction.showcasePortrait,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    errorBuilder: (_, _, _) => Icon(
                      faction == Faction.rome
                          ? Icons.account_balance
                          : Icons.change_history,
                      size: 54,
                      color: ChronoPalette.parchment,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        faction.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        faction.commander,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFFD89A),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.25,
                          color: ChronoPalette.parchmentMuted,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: onTap,
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text('ELEGIR Y JUGAR'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.mode,
    required this.playerFaction,
    required this.botDifficulty,
  });

  final GameMode mode;
  final Faction playerFaction;
  final BotDifficulty botDifficulty;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final Random _random = Random();
  late final List<CardDefinition> _playerDeck;
  late final List<CardDefinition> _opponentDeck;
  final List<CardDefinition> _playerHand = [];
  final List<CardDefinition> _opponentHand = [];
  final List<CardDefinition> _playerDiscard = [];
  final List<CardDefinition> _opponentDiscard = [];
  final List<ResourceToken> _playerResources = [];
  final List<ResourceToken> _opponentResources = [];
  final List<CardInstance> _playerBattle = [];
  final List<CardInstance> _playerSupport = [];
  final List<CardInstance> _opponentBattle = [];
  final List<CardInstance> _opponentSupport = [];
  final List<String> _events = [];
  final List<String> _actionHistory = [];
  final List<CombatReport> _combatHistory = [];
  final List<AttackAssignment> _attackPlan = [];
  late final List<int> _playerInitiativeDice;
  late final List<int> _opponentInitiativeDice;
  late final bool _initiativePlayerSide;
  int _initiativeAttempts = 0;

  int _round = 1;
  bool _playerActive = true;
  bool _offensiveUsed = false;
  bool _orderUsedThisTurn = false;
  bool _transitionBusy = true;
  bool _turnClockPaused = false;
  bool _allowExit = false;
  Timer? _turnTimer;
  int _secondsLeft = 45;
  CardInstance? _selectedAttacker;
  PendingOrder? _pendingOrder;
  int _playerCommanderDamage = 0;
  int _opponentCommanderDamage = 0;
  int _playerEliminations = 0;
  int _opponentEliminations = 0;
  bool _roundLimitFinished = false;
  Faction? _roundLimitWinner;
  String _notice = 'Selecciona una carta de la mano para comenzar.';

  @override
  void initState() {
    super.initState();
    _playerDeck = _buildDeck(widget.playerFaction)..shuffle(_random);
    _opponentDeck = _buildDeck(widget.playerFaction.opponent)..shuffle(_random);
    _draw(_playerDeck, _playerHand, 6);
    _draw(_opponentDeck, _opponentHand, 6);
    _playerResources.add(ResourceToken(_randomResource(widget.playerFaction)));
    _opponentResources
        .add(ResourceToken(_randomResource(widget.playerFaction.opponent)));
    late List<int> playerDice;
    late List<int> opponentDice;
    do {
      _initiativeAttempts++;
      playerDice = List.generate(3, (_) => _random.nextInt(6) + 1);
      opponentDice = List.generate(3, (_) => _random.nextInt(6) + 1);
    } while (playerDice.reduce((a, b) => a + b) ==
        opponentDice.reduce((a, b) => a + b));
    _playerInitiativeDice = playerDice;
    _opponentInitiativeDice = opponentDice;
    _initiativePlayerSide =
        _playerInitiativeDice.reduce((a, b) => a + b) >
            _opponentInitiativeDice.reduce((a, b) => a + b);
    _playerActive = _initiativePlayerSide;
    final starter =
        _playerActive ? widget.playerFaction : widget.playerFaction.opponent;
    final initiativeMessage =
        'Iniciativa: ${starter.name} obtiene el total más alto y comienza.';
    _events.add(initiativeMessage);
    _actionHistory.add(initiativeMessage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_beginMatch());
    });
  }

  @override
  void dispose() {
    _turnTimer?.cancel();
    super.dispose();
  }

  void _startTurnTimer() {
    _turnTimer?.cancel();
    if (!mounted) return;
    setState(() => _secondsLeft = 45);
    _turnTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_transitionBusy || _turnClockPaused) return;
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() {
          _secondsLeft = 0;
          _notice = 'Tiempo agotado. El turno termina automáticamente.';
        });
        unawaited(_endTurn(automatic: true));
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  void _stopTurnTimer() {
    _turnTimer?.cancel();
    _turnTimer = null;
  }

  Future<void> _confirmAbandon() async {
    if (!mounted || _allowExit) return;
    _turnClockPaused = true;
    final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.logout, color: Color(0xFFD6A25E)),
            title: const Text('¿Abandonar la partida?'),
            content: const Text(
              'La partida actual no está guardada y volverás al menú principal.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('CONTINUAR'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('ABANDONAR'),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted) return;
    if (leave) {
      _stopTurnTimer();
      setState(() => _allowExit = true);
      Navigator.of(context).pop();
      return;
    }
    setState(() => _turnClockPaused = false);
  }

  Future<void> _showTimedDialog({
    required Duration duration,
    required Widget Function(BuildContext) builder,
  }) async {
    if (!mounted) return;
    BuildContext? dialogContext;
    final timer = Timer(duration, () {
      final current = dialogContext;
      if (current != null && current.mounted) {
        Navigator.of(current).pop();
      }
    });
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        dialogContext = context;
        return builder(context);
      },
    );
    timer.cancel();
  }

  Future<void> _showTurnAnnouncement(Faction faction) {
    return _showTimedDialog(
      duration: const Duration(seconds: 2),
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.hourglass_bottom, color: faction.color, size: 42),
        title: Text('TURNO DE ${faction.name.toUpperCase()}'),
        content: Text(
          'Ronda $_round',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, color: Color(0xFFD6A25E)),
        ),
      ),
    );
  }

  Future<void> _showInitiative() {
    final playerTotal = _playerInitiativeDice.reduce((a, b) => a + b);
    final opponentTotal = _opponentInitiativeDice.reduce((a, b) => a + b);
    final starter =
        _initiativePlayerSide ? widget.playerFaction : widget.playerFaction.opponent;
    return _showTimedDialog(
      duration: const Duration(seconds: 3),
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.casino, color: Color(0xFFD6A25E), size: 46),
        title: const Text('TIRADA DE INICIATIVA'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _InitiativeDiceRow(
                faction: widget.playerFaction,
                dice: _playerInitiativeDice,
                total: playerTotal,
              ),
              const SizedBox(height: 12),
              _InitiativeDiceRow(
                faction: widget.playerFaction.opponent,
                dice: _opponentInitiativeDice,
                total: opponentTotal,
              ),
              const SizedBox(height: 16),
              Text(
                '${starter.name.toUpperCase()} COMIENZA',
                style: TextStyle(
                  color: starter.color,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (_initiativeAttempts > 1)
                Text(
                  'Empate resuelto después de $_initiativeAttempts tiradas.',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('COMENZAR AHORA'),
          ),
        ],
      ),
    );
  }

  Future<void> _beginMatch() async {
    await _showInitiative();
    if (!mounted) return;
    final activeFaction =
        _playerActive ? widget.playerFaction : widget.playerFaction.opponent;
    await _showTurnAnnouncement(activeFaction);
    if (!mounted) return;
    if (widget.mode == GameMode.bot && !_playerActive) {
      await _runBotTurn();
      return;
    }
    setState(() => _transitionBusy = false);
    _startTurnTimer();
  }

  Future<void> _showCombatReport(CombatReport report) {
    return _showTimedDialog(
      duration: const Duration(seconds: 3),
      builder: (dialogContext) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 18, 8, 0),
        title: Row(
          children: [
            const Icon(Icons.flash_on, color: Color(0xFFD6A25E)),
            const SizedBox(width: 8),
            Expanded(child: Text(report.title)),
            IconButton(
              tooltip: 'Cerrar ahora',
              onPressed: () => Navigator.of(dialogContext).pop(),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in report.lines) ...[
                  Text(
                    line.text,
                    style: TextStyle(
                      color: line.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                ],
                const Divider(),
                const Text(
                  'Esta ventana se cierra automáticamente en 3 segundos.',
                  style: TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<CardDefinition> _buildDeck(Faction faction) {
    final raw = jsonDecode(_deckJson) as Map<String, dynamic>;
    final key = faction == Faction.rome ? 'roma' : 'cartago';
    final definitions = (raw[key] as List<dynamic>)
        .map((item) => CardDefinition.fromJson(item as Map<String, dynamic>))
        .where(
          (card) =>
              card.type == 'Unidad' ||
              card.type == 'Fortificación' ||
              (card.type == 'Orden' && card.orderEffect != OrderEffect.none),
        );
    return [
      for (final card in definitions)
        for (var copy = 0; copy < card.copies; copy++) card,
    ];
  }

  ResourceType _randomResource(Faction faction) {
    final earthChance = faction == Faction.rome ? 13 / 18 : 14 / 18;
    return _random.nextDouble() < earthChance
        ? ResourceType.earth
        : ResourceType.sea;
  }

  void _draw(
    List<CardDefinition> deck,
    List<CardDefinition> hand,
    int amount,
  ) {
    for (var i = 0; i < amount && deck.isNotEmpty; i++) {
      hand.add(deck.removeLast());
    }
  }

  bool _canAfford(CardDefinition card, List<ResourceToken> resources) {
    final available = resources.where((resource) => !resource.used).toList();
    final earth =
        available.where((resource) => resource.type == ResourceType.earth).length;
    final sea =
        available.where((resource) => resource.type == ResourceType.sea).length;
    return earth >= card.earth &&
        sea >= card.sea &&
        available.length >= card.earth + card.sea + card.generic;
  }

  bool _payResources(CardDefinition card, List<ResourceToken> resources) {
    if (!_canAfford(card, resources)) return false;

    final selected = <int>[];
    void selectType(ResourceType type, int amount) {
      for (var i = 0; i < resources.length && amount > 0; i++) {
        if (!resources[i].used &&
            !selected.contains(i) &&
            resources[i].type == type) {
          selected.add(i);
          amount--;
        }
      }
    }

    selectType(ResourceType.earth, card.earth);
    selectType(ResourceType.sea, card.sea);
    var generic = card.generic;
    for (var i = 0; i < resources.length && generic > 0; i++) {
      if (!resources[i].used && !selected.contains(i)) {
        selected.add(i);
        generic--;
      }
    }
    for (final index in selected) {
      resources[index] = resources[index].copyWith(used: true);
    }
    return true;
  }

  void _readyCards(List<CardInstance> battle, List<CardInstance> support) {
    for (final instance in [...battle, ...support]) {
      instance.preparing = false;
      instance.tapped = false;
    }
  }

  void _finishPreparation(
    List<CardInstance> battle,
    List<CardInstance> support,
  ) {
    for (final instance in [...battle, ...support]) {
      instance.preparing = false;
    }
  }

  void _clearOrderBonuses(
    List<CardInstance> battle,
    List<CardInstance> support,
  ) {
    for (final instance in [...battle, ...support]) {
      instance.clearOrderBonuses();
    }
  }

  List<CardInstance> _orderTargets(PendingOrder pending) {
    final ownBattle = pending.playerSide ? _playerBattle : _opponentBattle;
    final ownSupport = pending.playerSide ? _playerSupport : _opponentSupport;
    final enemyBattle = pending.playerSide ? _opponentBattle : _playerBattle;
    final enemySupport = pending.playerSide ? _opponentSupport : _playerSupport;
    return switch (pending.card.orderEffect) {
      OrderEffect.forceTwo || OrderEffect.diceForce => [
          ...ownBattle.where(
            (card) =>
                card.card.type == 'Unidad' &&
                _isEligibleAttacker(card, inSupport: false),
          ),
          ...ownSupport.where(
            (card) =>
                card.card.type == 'Unidad' &&
                _isEligibleAttacker(card, inSupport: true),
          ),
        ],
      OrderEffect.healTwo => [
          ...ownBattle.where(
            (card) => card.card.type == 'Unidad' && card.damage > 0,
          ),
          ...ownSupport.where(
            (card) => card.card.type == 'Unidad' && card.damage > 0,
          ),
        ],
      OrderEffect.damageOne => [
          ...enemyBattle.where((card) => card.card.type == 'Unidad'),
          ...enemySupport.where((card) => card.card.type == 'Unidad'),
        ],
      OrderEffect.none || OrderEffect.drawOne => const [],
    };
  }

  bool _isValidOrderTarget(CardInstance instance) {
    final pending = _pendingOrder;
    return pending != null && _orderTargets(pending).contains(instance);
  }

  void _activateOrder({
    required bool playerSide,
    required CardDefinition card,
  }) {
    if (_transitionBusy) return;
    if (playerSide != _playerActive) {
      _message('Solo el jugador activo puede utilizar una Orden.');
      return;
    }
    if (_orderUsedThisTurn) {
      _message('Ya utilizaste una Orden durante este turno.');
      return;
    }
    if (_offensiveUsed || _selectedAttacker != null || _attackPlan.isNotEmpty) {
      _message('Las Órdenes deben activarse antes de declarar la ofensiva.');
      return;
    }
    final resources = playerSide ? _playerResources : _opponentResources;
    if (!_canAfford(card, resources)) {
      _message('No hay recursos disponibles suficientes para esta Orden.');
      return;
    }

    if (card.orderEffect == OrderEffect.drawOne) {
      final hand = playerSide ? _playerHand : _opponentHand;
      final deck = playerSide ? _playerDeck : _opponentDeck;
      if (deck.isEmpty) {
        _message('El mazo está vacío; esta Orden no puede activarse.');
        return;
      }
      final discard = playerSide ? _playerDiscard : _opponentDiscard;
      final faction =
          playerSide ? widget.playerFaction : widget.playerFaction.opponent;
      setState(() {
        _payResources(card, resources);
        hand.remove(card);
        discard.add(card);
        _draw(deck, hand, 1);
        _orderUsedThisTurn = true;
        final entry =
            'Ronda $_round · ${faction.name} activa ${card.name}: roba 1 carta.';
        _events.insert(0, entry);
        _actionHistory.insert(0, entry);
        _notice = entry;
      });
      Navigator.of(context).pop();
      return;
    }

    final pending = PendingOrder(card: card, playerSide: playerSide);
    if (_orderTargets(pending).isEmpty) {
      _message('No existe un objetivo válido para ${card.name}.');
      return;
    }
    setState(() {
      _pendingOrder = pending;
      _notice = 'ORDEN: ${card.name}. Selecciona una unidad iluminada.';
    });
    Navigator.of(context).pop();
  }

  void _cancelPendingOrder() {
    if (_pendingOrder == null || _transitionBusy) return;
    setState(() {
      _pendingOrder = null;
      _notice = 'Orden cancelada. No se gastaron recursos.';
    });
  }

  Future<void> _resolveOrderTarget(
    CardInstance target, {
    bool automated = false,
  }) async {
    final pending = _pendingOrder;
    if (pending == null || (_transitionBusy && !automated)) return;
    final wasTransitionBusy = _transitionBusy;
    if (!_isValidOrderTarget(target)) {
      _message('Esa carta no es un objetivo válido para la Orden.');
      return;
    }
    final resources =
        pending.playerSide ? _playerResources : _opponentResources;
    if (!_canAfford(pending.card, resources)) {
      _cancelPendingOrder();
      _message('Los recursos disponibles cambiaron y la Orden fue cancelada.');
      return;
    }
    final hand = pending.playerSide ? _playerHand : _opponentHand;
    final discard =
        pending.playerSide ? _playerDiscard : _opponentDiscard;
    final faction = pending.playerSide
        ? widget.playerFaction
        : widget.playerFaction.opponent;
    var result = '';
    int? die;
    int? dieBonus;
    setState(() {
      _payResources(pending.card, resources);
      hand.remove(pending.card);
      discard.add(pending.card);
      switch (pending.card.orderEffect) {
        case OrderEffect.forceTwo:
          target.turnForceBonus += 2;
          result = '${target.card.name} obtiene +2 Fuerza este turno';
          break;
        case OrderEffect.healTwo:
          final restored = min(2, target.damage);
          target.damage -= restored;
          result = '${target.card.name} restaura $restored de daño';
          break;
        case OrderEffect.damageOne:
          target.damage += 1;
          final destroyed = _removeDestroyed().contains(target);
          if (destroyed) {
            if (pending.playerSide) {
              _playerEliminations++;
            } else {
              _opponentEliminations++;
            }
          }
          result = destroyed
              ? '${target.card.name} recibe 1 daño y es destruida'
              : '${target.card.name} recibe 1 daño';
          break;
        case OrderEffect.diceForce:
          die = _random.nextInt(6) + 1;
          dieBonus = diceOrderBonus(die!);
          target.nextAttackForceBonus += dieBonus!;
          result =
              '${target.card.name} obtiene +$dieBonus Fuerza en su próximo ataque';
          break;
        case OrderEffect.none:
        case OrderEffect.drawOne:
          break;
      }
      _orderUsedThisTurn = true;
      _pendingOrder = null;
      final entry =
          'Ronda $_round · ${faction.name} activa ${pending.card.name}: $result.';
      _events.insert(0, entry);
      _actionHistory.insert(0, entry);
      _notice = entry;
      if (die != null) _transitionBusy = true;
    });
    if (die != null && mounted) {
      await _showOrderDie(die!, dieBonus!, target.card.name);
      if (!mounted) return;
      setState(() => _transitionBusy = wasTransitionBusy);
    }
  }

  Future<void> _showOrderDie(int die, int bonus, String targetName) {
    return _showTimedDialog(
      duration: const Duration(seconds: 2),
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.casino, color: Color(0xFFD6A25E), size: 44),
        title: const Text('ORDEN DE DADOS'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DieFace(value: die, size: 64),
            const SizedBox(height: 12),
            Text(
              '$targetName obtiene ⚔+$bonus',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('CERRAR'),
          ),
        ],
      ),
    );
  }

  void _deployCard({
    required bool playerSide,
    required CardDefinition card,
    required bool toSupport,
  }) {
    if (_transitionBusy) return;
    final isActiveSide = playerSide == _playerActive;
    if (!isActiveSide) {
      _message('Solo puedes jugar durante el turno de esa civilización.');
      return;
    }
    if (card.type != 'Unidad' && card.type != 'Fortificación') {
      _message('${card.type} se implementará en el siguiente bloque de reglas.');
      return;
    }
    if (card.type == 'Fortificación' && !toSupport) {
      _message('Las Fortificaciones solo pueden desplegarse en Apoyo.');
      return;
    }

    final hand = playerSide ? _playerHand : _opponentHand;
    final resources = playerSide ? _playerResources : _opponentResources;
    final line = playerSide
        ? (toSupport ? _playerSupport : _playerBattle)
        : (toSupport ? _opponentSupport : _opponentBattle);
    if (line.length >= 5) {
      _message('La línea ya tiene sus 5 espacios ocupados.');
      return;
    }
    if (!_canAfford(card, resources)) {
      _message('No hay recursos disponibles suficientes para pagar esta carta.');
      return;
    }

    setState(() {
      _payResources(card, resources);
      hand.remove(card);
      line.add(CardInstance(card));
      final owner = playerSide ? widget.playerFaction : widget.playerFaction.opponent;
      _events.insert(
        0,
        '${owner.name} despliega ${card.name} en ${toSupport ? 'Apoyo' : 'Batalla'}.',
      );
    });
    Navigator.of(context).pop();
  }

  void _message(String message) {
    if (!mounted) return;
    setState(() => _notice = message);
  }

  void _botDeploy() {
    bool toSupport(CardDefinition card) =>
        card.type == 'Fortificación' || card.line.contains('Apoyo');
    var deployed = 0;
    while (deployed < 12) {
      final options = _opponentHand.where((card) {
        if (card.type != 'Unidad' && card.type != 'Fortificación') return false;
        if (!_canAfford(card, _opponentResources)) return false;
        final line = toSupport(card) ? _opponentSupport : _opponentBattle;
        return line.length < 5;
      }).toList();

      if (options.isEmpty) break;
      if (widget.botDifficulty == BotDifficulty.normal) {
        int score(CardDefinition card) =>
            (card.force ?? 0) * 4 +
            (card.defense ?? 0) * 2 +
            (_canAttackFromSupport(card) ? 4 : 0) +
            (card.type == 'Fortificación' ? 2 : 0) -
            card.cost;
        options.sort((a, b) => score(b).compareTo(score(a)));
      }

      final card = options.first;
      final support = toSupport(card);
      final line = support ? _opponentSupport : _opponentBattle;
      _payResources(card, _opponentResources);
      _opponentHand.remove(card);
      line.add(CardInstance(card));
      deployed++;
      _events.insert(
        0,
        'El bot despliega ${card.name} en ${support ? 'Apoyo' : 'Batalla'}.',
      );
    }
    if (deployed == 0) {
      _events.insert(0, 'El bot no pudo desplegar una carta este turno.');
    } else {
      _events.insert(0, 'El bot desplegó $deployed carta(s) este turno.');
    }
  }

  Future<void> _botUseOrder() async {
    if (_orderUsedThisTurn) return;
    final candidates = _opponentHand.where(
      (card) =>
          card.type == 'Orden' &&
          card.orderEffect != OrderEffect.none &&
          _canAfford(card, _opponentResources),
    ).toList();
    if (candidates.isEmpty) return;

    CardDefinition? selected;
    CardInstance? selectedTarget;
    var bestScore = -10000;
    for (final card in candidates) {
      if (_round == 1 && card.orderEffect == OrderEffect.drawOne) continue;
      if (card.orderEffect == OrderEffect.drawOne && _opponentDeck.isEmpty) {
        continue;
      }
      final pending = PendingOrder(card: card, playerSide: false);
      final targets = _orderTargets(pending);
      if (card.orderEffect != OrderEffect.drawOne && targets.isEmpty) continue;
      CardInstance? target;
      var score = 0;
      switch (card.orderEffect) {
        case OrderEffect.forceTwo:
        case OrderEffect.diceForce:
          targets.sort(
            (a, b) => b.effectiveForce.compareTo(a.effectiveForce),
          );
          target = targets.first;
          score = target.effectiveForce * 4 +
              (card.orderEffect == OrderEffect.diceForce ? 3 : 4);
          break;
        case OrderEffect.healTwo:
          targets.sort((a, b) => b.damage.compareTo(a.damage));
          target = targets.first;
          score = target.damage * 5 + target.effectiveForce;
          break;
        case OrderEffect.damageOne:
          targets.sort((a, b) {
            final aRemaining = (a.card.defense ?? 0) - a.damage;
            final bRemaining = (b.card.defense ?? 0) - b.damage;
            return aRemaining.compareTo(bRemaining);
          });
          target = targets.first;
          final remaining = (target.card.defense ?? 0) - target.damage;
          score = remaining <= 1 ? 30 : 8 + target.effectiveForce;
          break;
        case OrderEffect.drawOne:
          score = 10;
          break;
        case OrderEffect.none:
          break;
      }
      if (score > bestScore) {
        bestScore = score;
        selected = card;
        selectedTarget = target;
      }
    }
    if (selected == null) return;
    final order = selected;

    if (order.orderEffect == OrderEffect.drawOne) {
      setState(() {
        _payResources(order, _opponentResources);
        _opponentHand.remove(order);
        _opponentDiscard.add(order);
        _draw(_opponentDeck, _opponentHand, 1);
        _orderUsedThisTurn = true;
        final entry =
            'Ronda $_round · ${widget.playerFaction.opponent.name} activa ${order.name}: roba 1 carta.';
        _events.insert(0, entry);
        _actionHistory.insert(0, entry);
        _notice = entry;
      });
      return;
    }
    _pendingOrder = PendingOrder(card: order, playerSide: false);
    await _resolveOrderTarget(selectedTarget!, automated: true);
  }

  bool _canAttackDomain(CardDefinition attacker, CardDefinition target) {
    if (target.domain == 'Naval') return attacker.attacksSea;
    return attacker.attacksEarth;
  }

  bool _isEligibleAttacker(CardInstance instance, {required bool inSupport}) {
    final attackType = instance.card.type == 'Unidad' ||
        (instance.card.type == 'Fortificación' && inSupport);
    return attackType &&
        instance.effectiveForce > 0 &&
        !instance.preparing &&
        !instance.tapped &&
        (!inSupport || _canAttackFromSupport(instance.card));
  }

  void _tapBoardCard({
    required CardInstance instance,
    required bool ownerPlayerSide,
    required bool inSupport,
  }) {
    if (_transitionBusy) return;
    if (_pendingOrder != null) {
      unawaited(_resolveOrderTarget(instance));
      return;
    }
    final activeOwner = ownerPlayerSide == _playerActive;
    if (activeOwner) {
      if (_offensiveUsed) {
        _message('La ofensiva de este turno ya fue utilizada.');
        return;
      }
      if (!_isEligibleAttacker(instance, inSupport: inSupport)) {
        _showBoardCard(instance);
        return;
      }
      setState(() {
        _attackPlan.removeWhere((item) => identical(item.attacker, instance));
        _selectedAttacker = instance;
      });
      _message('Atacante seleccionado. Ahora toca un objetivo enemigo.');
      return;
    }

    final attacker = _selectedAttacker;
    if (attacker == null) {
      _showBoardCard(instance);
      return;
    }
    final enemyBattle = _playerActive ? _opponentBattle : _playerBattle;
    final enemySupport = _playerActive ? _opponentSupport : _playerSupport;
    final attackerInSupport = _playerActive
        ? _playerSupport.contains(attacker)
        : _opponentSupport.contains(attacker);
    if (!attackerInSupport &&
        enemyBattle.isNotEmpty &&
        !enemyBattle.contains(instance)) {
      _message('Mientras Batalla tenga cartas, debes atacar esa línea.');
      return;
    }
    if (!attackerInSupport &&
        enemyBattle.isEmpty &&
        enemySupport.isNotEmpty &&
        !enemySupport.contains(instance)) {
      _message('Selecciona una carta de Apoyo.');
      return;
    }
    var target = instance;
    if (enemySupport.contains(instance)) {
      if (widget.mode == GameMode.bot && !attacker.card.precision) {
        final chosen = _chooseBotSupportDefender(attacker, enemySupport);
        if (chosen == null) {
          _message('El Apoyo rival ya completó su capacidad de defensa.');
          return;
        }
        target = chosen;
      }
      if (_incomingAttackCount(target) >=
          _supportDefenseCapacity(target.card)) {
        _message(
          '${target.card.name} ya recibió el máximo de ataques de esta ofensiva.',
        );
        return;
      }
    }
    if (!_canAttackDomain(attacker.card, target.card)) {
      _message('Esa unidad no puede atacar el dominio del objetivo.');
      return;
    }
    setState(() {
      _attackPlan.add(AttackAssignment(attacker: attacker, target: target));
      _selectedAttacker = null;
      _notice = '${attacker.card.name} atacará a ${target.card.name}.';
    });
  }

  void _tapCommander(bool commanderBelongsToPlayer) {
    if (_transitionBusy) return;
    if (_pendingOrder != null) {
      _message('La Orden seleccionada solo puede apuntar a una unidad.');
      return;
    }
    if (commanderBelongsToPlayer == _playerActive || _selectedAttacker == null) {
      return;
    }
    final enemyBattle = _playerActive ? _opponentBattle : _playerBattle;
    final enemySupport = _playerActive ? _opponentSupport : _playerSupport;
    if (_commanderIsProtected(enemyBattle, enemySupport)) {
      _message(
        enemyBattle.isNotEmpty
            ? 'El Comandante está protegido por la línea de Batalla.'
            : 'El Comandante está protegido por una muralla en Apoyo.',
      );
      return;
    }
    if (_attackPlan.any((assignment) => assignment.target == null)) {
      _message('Ya declaraste el ataque directo de esta ofensiva.');
      return;
    }
    setState(() {
      _attackPlan.add(
        AttackAssignment(attacker: _selectedAttacker!, target: null),
      );
      _notice = '${_selectedAttacker!.card.name} atacará al Comandante.';
      _selectedAttacker = null;
    });
  }

  void _cancelAttackPlan() {
    if (_transitionBusy) return;
    setState(() {
      _selectedAttacker = null;
      _attackPlan.clear();
    });
  }

  List<int> _attackMarkers(CardInstance card) {
    final markers = <int>[];
    for (var i = 0; i < _attackPlan.length; i++) {
      final assignment = _attackPlan[i];
      if (identical(assignment.attacker, card) ||
          identical(assignment.target, card)) {
        markers.add(i + 1);
      }
    }
    return markers;
  }

  int _incomingAttackCount(CardInstance card) => _attackPlan
      .where((assignment) => identical(assignment.target, card))
      .length;

  CardInstance? _chooseBotSupportDefender(
    CardInstance attacker,
    List<CardInstance> defenders,
  ) {
    final candidates = defenders.where(
      (defender) =>
          _canAttackDomain(attacker.card, defender.card) &&
          _incomingAttackCount(defender) <
              _supportDefenseCapacity(defender.card),
    ).toList();
    if (candidates.isEmpty) return null;
    if (widget.botDifficulty == BotDifficulty.normal) {
      int score(CardInstance defender) {
        final remaining =
            max(0, (defender.card.defense ?? 0) - defender.damage);
        return remaining * 4 - defender.effectiveForce * 2;
      }
      candidates.sort((a, b) => score(b).compareTo(score(a)));
    }
    return candidates.first;
  }

  String _attackMarkerLabel(int marker) {
    if (marker < 1 || marker > _attackPlan.length) return 'A?';
    final force = _attackPlan[marker - 1].attacker.effectiveForce;
    return 'A$force';
  }

  Future<void> _resolvePlayerOffensive({bool automatic = false}) async {
    if (_transitionBusy) return;
    if (_attackPlan.isEmpty) {
      _message('Primero selecciona al menos un atacante y su objetivo.');
      return;
    }
    _stopTurnTimer();
    late CombatReport report;
    setState(() {
      _transitionBusy = true;
      report = _resolveAssignments(
        List<AttackAssignment>.from(_attackPlan),
        attackerPlayerSide: _playerActive,
      );
      _attackPlan.clear();
      _selectedAttacker = null;
      _offensiveUsed = true;
      _notice = _events.isEmpty ? 'Ofensiva resuelta.' : _events.first;
    });
    await _showCombatReport(report);
    if (!mounted) return;
    if (_hasVictory) {
      await _showVictory();
      return;
    }
    final handReady = await _enforceHandLimit(automatic: automatic);
    if (!handReady || !mounted) return;
    await _advanceTurn();
  }

  CombatReport _resolveAssignments(
    List<AttackAssignment> assignments, {
    required bool attackerPlayerSide,
  }) {
    final attackerFaction = attackerPlayerSide
        ? widget.playerFaction
        : widget.playerFaction.opponent;
    final defendingBattle =
        attackerPlayerSide ? _opponentBattle : _playerBattle;
    final defendingSupport =
        attackerPlayerSide ? _opponentSupport : _playerSupport;
    final commanderWasProtected =
        _commanderIsProtected(defendingBattle, defendingSupport);
    final totalForce = assignments.fold<int>(
      0,
      (total, assignment) =>
          total + assignment.attacker.effectiveForce,
    );
    final reportLines = <CombatReportLine>[
      CombatReportLine(
        '⚔ ${assignments.length} atacante(s) · Fuerza total $totalForce',
        color: const Color(0xFFD6A25E),
      ),
    ];
    for (final assignment in assignments) {
      assignment.attacker.tapped = true;
    }

    final commanderAttacks =
        assignments.where((item) => item.target == null).toList();
    if (commanderAttacks.isNotEmpty) {
      const damage = 1;
      if (attackerPlayerSide) {
        _opponentCommanderDamage += damage;
      } else {
        _playerCommanderDamage += damage;
      }
      _events.insert(
        0,
        '${commanderAttacks.first.attacker.card.name} causa 1 daño directo al Comandante.',
      );
      reportLines.add(
        const CombatReportLine(
          '◆ Ataque directo: el Comandante recibe 1 daño.',
          color: Color(0xFFFFD166),
        ),
      );
    }

    final targets = <CardInstance>{
      for (final assignment in assignments)
        if (assignment.target != null) assignment.target!,
    };
    var counterattacks = 0;
    for (final target in targets) {
      final group = assignments.where((item) => identical(item.target, target)).toList();
      final defenseBefore = max(0, (target.card.defense ?? 0) - target.damage);
      final incoming = group.fold<int>(
        0,
        (total, item) => total + item.attacker.effectiveForce,
      );
      target.damage += incoming;
      final defenseAfter = max(0, (target.card.defense ?? 0) - target.damage);
      final destroyed = defenseAfter == 0;
      final damaged = defenseAfter < (target.card.defense ?? 0);
      reportLines.add(
        CombatReportLine(
          '${destroyed ? '●' : '■'} ${target.card.name}: 🛡 $defenseBefore → $defenseAfter · '
          '${destroyed ? 'DESTRUIDA' : damaged ? 'DAÑADA' : 'SOBREVIVE'}',
          color: destroyed
              ? const Color(0xFFFF6B6B)
              : damaged
                  ? const Color(0xFFFFD740)
                  : const Color(0xFF69F0AE),
        ),
      );

      if (!target.preparing && !target.tapped && target.effectiveForce > 0) {
        CardInstance? counterTarget;
        for (final item in group) {
          if (_canAttackDomain(target.card, item.attacker.card)) {
            counterTarget = item.attacker;
            break;
          }
        }
        if (counterTarget != null) {
          counterattacks++;
          final counterDamage = target.effectiveForce;
          counterTarget.damage += counterDamage;
          _events.insert(
            0,
            '${target.card.name} contraataca a ${counterTarget.card.name}.',
          );
        }
      }
      _events.insert(0, '${target.card.name} recibe $incoming de daño.');
    }
    for (final assignment in assignments) {
      assignment.attacker.nextAttackForceBonus = 0;
    }
    final destroyed = _removeDestroyed();
    final commanderExposedAfter =
        !_commanderIsProtected(defendingBattle, defendingSupport);
    if (commanderWasProtected && commanderExposedAfter) {
      if (attackerPlayerSide) {
        _opponentCommanderDamage++;
      } else {
        _playerCommanderDamage++;
      }
      reportLines.add(
        const CombatReportLine(
          '🏰 BRECHA: el Comandante recibe 1 daño.',
          color: Color(0xFFFFD166),
        ),
      );
      _events.insert(
        0,
        '${attackerFaction.name} abre una Brecha y causa 1 daño al Comandante.',
      );
    }
    final destroyedDefenders = destroyed.where(targets.contains).length;
    final destroyedAttackers = destroyed.where(
      (card) => assignments.any(
        (assignment) => identical(assignment.attacker, card),
      ),
    ).length;
    if (attackerPlayerSide) {
      _playerEliminations += destroyedDefenders;
      _opponentEliminations += destroyedAttackers;
    } else {
      _opponentEliminations += destroyedDefenders;
      _playerEliminations += destroyedAttackers;
    }
    if (counterattacks > 0) {
      reportLines.add(
        CombatReportLine(
          '↩ Contraataques: $counterattacks · Atacantes eliminados: $destroyedAttackers',
          color: destroyedAttackers > 0
              ? const Color(0xFFFF6B6B)
              : Colors.white70,
        ),
      );
    }
    reportLines.add(
      CombatReportLine(
        '☠ Total de cartas eliminadas: ${destroyed.length}',
        color: destroyed.isEmpty ? Colors.white70 : const Color(0xFFFF6B6B),
      ),
    );
    final report = CombatReport(
      title: 'Resultado · ${attackerFaction.name}',
      round: _round,
      lines: reportLines,
    );
    _combatHistory.insert(0, report);
    return report;
  }

  List<CardInstance> _removeDestroyed() {
    final removed = <CardInstance>[];
    for (final line in [
      _playerBattle,
      _playerSupport,
      _opponentBattle,
      _opponentSupport,
    ]) {
      final destroyed = line.where(
        (instance) =>
            instance.card.defense != null &&
            instance.damage >= instance.card.defense!,
      ).toList();
      for (final instance in destroyed) {
        removed.add(instance);
        _events.insert(0, '${instance.card.name} fue destruida.');
      }
      line.removeWhere(destroyed.contains);
    }
    return removed;
  }

  Future<CombatReport?> _botAttack() async {
    final attackers = <CardInstance>[
      ..._opponentBattle.where(
        (card) => _isEligibleAttacker(card, inSupport: false),
      ),
      ..._opponentSupport.where(
        (card) => _isEligibleAttacker(card, inSupport: true),
      ),
    ];
    final assignments = <AttackAssignment>[];
    final commanderExposed =
        !_commanderIsProtected(_playerBattle, _playerSupport);

    if (commanderExposed) {
      if (attackers.isNotEmpty) {
        assignments.add(AttackAssignment(attacker: attackers.first));
      }
    } else if (_playerBattle.isNotEmpty &&
        widget.botDifficulty == BotDifficulty.easy) {
      for (final attacker in attackers) {
        final candidates = _playerBattle;
        CardInstance? target;
        for (final candidate in candidates) {
          if (_canAttackDomain(attacker.card, candidate.card)) {
            target = candidate;
            break;
          }
        }
        if (target != null) {
          assignments.add(AttackAssignment(attacker: attacker, target: target));
        }
      }
    } else if (_playerBattle.isNotEmpty) {
      attackers.sort(
        (a, b) => b.effectiveForce.compareTo(a.effectiveForce),
      );
      final plannedDamage = <CardInstance, int>{};
      for (final attacker in attackers) {
        final compatible = _playerBattle.where(
          (target) => _canAttackDomain(attacker.card, target.card),
        );
        CardInstance? bestTarget;
        var bestScore = -10000;
        for (final target in compatible) {
          final remaining = max(
            0,
            (target.card.defense ?? 0) -
                target.damage -
                (plannedDamage[target] ?? 0),
          );
          final attackForce = attacker.effectiveForce;
          final counterForce = !target.preparing && !target.tapped
              ? target.effectiveForce
              : 0;
          final attackerRemaining =
              max(0, (attacker.card.defense ?? 0) - attacker.damage);
          final destroys = attackForce >= remaining;
          final survives = counterForce < attackerRemaining;
          if (!destroys && !survives) continue;
          final score =
              (destroys ? 100 : 20) +
              (survives ? 30 : -20) +
              target.effectiveForce * 3 -
              remaining;
          if (score > bestScore) {
            bestScore = score;
            bestTarget = target;
          }
        }
        if (bestTarget != null) {
          assignments.add(
            AttackAssignment(attacker: attacker, target: bestTarget),
          );
          plannedDamage[bestTarget] =
              (plannedDamage[bestTarget] ?? 0) + attacker.effectiveForce;
        }
      }
    } else {
      final usedCapacity = <CardInstance, int>{};
      final defenderChooses = <CardInstance>[];
      for (final attacker in attackers) {
        final available = _playerSupport.where(
          (target) =>
              _canAttackDomain(attacker.card, target.card) &&
              (usedCapacity[target] ?? 0) <
                  _supportDefenseCapacity(target.card),
        ).toList();
        if (available.isEmpty) continue;
        if (widget.botDifficulty == BotDifficulty.normal &&
            !available.any(
              (target) => _botAttackIsReasonable(attacker, target),
            )) {
          continue;
        }
        if (attacker.card.precision) {
          final target = _bestBotSupportTarget(attacker, available);
          assignments.add(AttackAssignment(attacker: attacker, target: target));
          usedCapacity[target] = (usedCapacity[target] ?? 0) + 1;
        } else {
          defenderChooses.add(attacker);
        }
      }
      if (defenderChooses.isNotEmpty) {
        final selected = await _askPlayerSupportDefenses(
          defenderChooses,
          usedCapacity,
        );
        if (!mounted) return null;
        assignments.addAll(selected);
      }
    }
    if (assignments.isNotEmpty) {
      late CombatReport report;
      setState(() {
        report = _resolveAssignments(assignments, attackerPlayerSide: false);
        _events.insert(
          0,
          'El bot resuelve una ofensiva con ${assignments.length} atacante(s).',
        );
      });
      return report;
    }
    return null;
  }

  bool _botAttackIsReasonable(
    CardInstance attacker,
    CardInstance target,
  ) {
    final remaining = max(0, (target.card.defense ?? 0) - target.damage);
    final attackForce = attacker.effectiveForce;
    final counterForce = !target.preparing && !target.tapped
        ? target.effectiveForce
        : 0;
    final attackerRemaining =
        max(0, (attacker.card.defense ?? 0) - attacker.damage);
    return attackForce >= remaining || counterForce < attackerRemaining;
  }

  CardInstance _bestBotSupportTarget(
    CardInstance attacker,
    List<CardInstance> targets,
  ) {
    if (widget.botDifficulty == BotDifficulty.easy) return targets.first;
    int score(CardInstance target) {
      final remaining = max(0, (target.card.defense ?? 0) - target.damage);
      final destroys = attacker.effectiveForce >= remaining;
      return (destroys ? 100 : 0) +
          target.effectiveForce * 3 -
          remaining;
    }
    targets.sort((a, b) => score(b).compareTo(score(a)));
    return targets.first;
  }

  Future<List<AttackAssignment>> _askPlayerSupportDefenses(
    List<CardInstance> attackers,
    Map<CardInstance, int> initialCapacity,
  ) async {
    if (!mounted) return const [];
    return await showDialog<List<AttackAssignment>>(
          context: context,
          barrierDismissible: false,
          builder: (context) => _SupportDefenseDialog(
            attackers: attackers,
            defenders: _playerSupport,
            initialCapacity: initialCapacity,
            canAttackDomain: _canAttackDomain,
          ),
        ) ??
        const [];
  }

  bool get _hasVictory =>
      _playerCommanderDamage >= 10 ||
      _opponentCommanderDamage >= 10 ||
      _roundLimitFinished;

  void _finishByRoundLimit() {
    _roundLimitFinished = true;
    if (_playerCommanderDamage != _opponentCommanderDamage) {
      _roundLimitWinner = _playerCommanderDamage < _opponentCommanderDamage
          ? widget.playerFaction
          : widget.playerFaction.opponent;
      return;
    }
    if (_playerEliminations != _opponentEliminations) {
      _roundLimitWinner = _playerEliminations > _opponentEliminations
          ? widget.playerFaction
          : widget.playerFaction.opponent;
      return;
    }
    _roundLimitWinner = null;
  }

  Future<void> _showVictory() async {
    if (!_hasVictory || !mounted) return;
    _stopTurnTimer();
    final winnerFaction = _roundLimitFinished
        ? _roundLimitWinner
        : _opponentCommanderDamage >= 10
            ? widget.playerFaction
            : widget.playerFaction.opponent;
    final isDraw = winnerFaction == null;
    final winner = winnerFaction?.name ?? 'Ningún bando';
    final playerWon = winnerFaction == widget.playerFaction;
    final freeTest = widget.mode == GameMode.freeTest;
    final resultText = _roundLimitFinished
        ? 'Se completaron $_maxRounds rondas.\n\n'
            '${widget.playerFaction.name}: Resistencia ${max(0, 10 - _playerCommanderDamage)}/10 · '
            'Eliminadas $_playerEliminations\n'
            '${widget.playerFaction.opponent.name}: Resistencia ${max(0, 10 - _opponentCommanderDamage)}/10 · '
            'Eliminadas $_opponentEliminations\n\n'
            '${isDraw ? 'La partida termina en empate.' : '$winner gana por resistencia y control del campo.'}'
        : '$winner ha derrotado al Comandante enemigo en la ronda $_round.';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: Icon(
          isDraw
              ? Icons.handshake_outlined
              : playerWon || freeTest
                  ? Icons.emoji_events
                  : Icons.shield_outlined,
          color: isDraw || playerWon || freeTest
              ? const Color(0xFFD6A25E)
              : const Color(0xFFFF6B6B),
          size: 52,
        ),
        title: Text(
          isDraw
              ? 'EMPATE'
              : freeTest
                  ? 'VICTORIA DE ${winner.toUpperCase()}'
                  : playerWon
                      ? '¡VICTORIA!'
                      : 'DERROTA',
        ),
        content: Text(resultText),
        actions: [
          FilledButton(
            onPressed: () {
              setState(() => _allowExit = true);
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('VOLVER AL MENÚ'),
          ),
        ],
      ),
    );
  }

  void _toggleResource(bool playerSide, int index) {
    if (_transitionBusy) return;
    if (playerSide != _playerActive) return;
    final list = playerSide ? _playerResources : _opponentResources;
    setState(() {
      list[index] = list[index].copyWith(used: !list[index].used);
    });
  }

  int _discardRandomExcess(
    List<CardDefinition> hand,
    List<CardDefinition> discard,
  ) {
    var discarded = 0;
    while (hand.length > _maxHandSize) {
      discard.add(hand.removeAt(_random.nextInt(hand.length)));
      discarded++;
    }
    return discarded;
  }

  void _discardSelectedCards(
    List<CardDefinition> hand,
    List<CardDefinition> discard,
    List<int> selectedIndexes,
  ) {
    final ordered = selectedIndexes.toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    for (final index in ordered) {
      if (index >= 0 && index < hand.length) {
        discard.add(hand.removeAt(index));
      }
    }
  }

  Future<bool> _enforceHandLimit({required bool automatic}) async {
    final playerSide = _playerActive;
    final hand = playerSide ? _playerHand : _opponentHand;
    final discard = playerSide ? _playerDiscard : _opponentDiscard;
    final excess = hand.length - _maxHandSize;
    if (excess <= 0) return true;

    final faction =
        playerSide ? widget.playerFaction : widget.playerFaction.opponent;
    if (automatic || (widget.mode == GameMode.bot && !playerSide)) {
      final discarded = _discardRandomExcess(hand, discard);
      if (!mounted) return false;
      setState(() {
        final entry =
            '${faction.name} descarta automáticamente $discarded carta(s) por superar el límite de $_maxHandSize.';
        _events.insert(0, entry);
        _actionHistory.insert(0, entry);
        _notice = entry;
      });
      return true;
    }

    _turnClockPaused = true;
    final selected = await showDialog<List<int>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _DiscardHandDialog(
        cards: List<CardDefinition>.from(hand),
        requiredCount: excess,
      ),
    );
    if (!mounted) return false;
    _turnClockPaused = false;
    if (selected == null || selected.length != excess) return false;

    setState(() {
      _discardSelectedCards(hand, discard, selected);
      final entry =
          '${faction.name} descarta $excess carta(s) y queda con $_maxHandSize en la mano.';
      _events.insert(0, entry);
      _actionHistory.insert(0, entry);
      _notice = entry;
    });
    return true;
  }

  Future<void> _endTurn({bool automatic = false}) async {
    if (_transitionBusy) return;
    if (_attackPlan.isNotEmpty) {
      await _resolvePlayerOffensive(automatic: automatic);
      return;
    }
    final handReady = await _enforceHandLimit(automatic: automatic);
    if (!handReady || !mounted) return;
    _stopTurnTimer();
    setState(() {
      _transitionBusy = true;
      _attackPlan.clear();
      _selectedAttacker = null;
    });
    await _advanceTurn();
  }

  Future<void> _advanceTurn() async {
    if (!mounted) return;
    final roundCompleted = _playerActive != _initiativePlayerSide;
    final endingBattle = _playerActive ? _playerBattle : _opponentBattle;
    final endingSupport = _playerActive ? _playerSupport : _opponentSupport;
    final endingHand = _playerActive ? _playerHand : _opponentHand;
    final endingDiscard =
        _playerActive ? _playerDiscard : _opponentDiscard;
    final endingFaction =
        _playerActive ? widget.playerFaction : widget.playerFaction.opponent;
    final forcedDiscards = _discardRandomExcess(endingHand, endingDiscard);
    setState(() {
      _finishPreparation(endingBattle, endingSupport);
      _clearOrderBonuses(endingBattle, endingSupport);
      _pendingOrder = null;
      _attackPlan.clear();
      _selectedAttacker = null;
      if (forcedDiscards > 0) {
        final entry =
            '${endingFaction.name} descarta automáticamente $forcedDiscards carta(s) por superar el límite de $_maxHandSize.';
        _events.insert(0, entry);
        _actionHistory.insert(0, entry);
      }
    });
    if (roundCompleted && _round >= _maxRounds) {
      setState(_finishByRoundLimit);
      await _showVictory();
      return;
    }

    setState(() {
      _playerActive = !_playerActive;
      if (_playerActive == _initiativePlayerSide) _round++;
      final faction =
          _playerActive ? widget.playerFaction : widget.playerFaction.opponent;
      final resources =
          _playerActive ? _playerResources : _opponentResources;
      final deck = _playerActive ? _playerDeck : _opponentDeck;
      final hand = _playerActive ? _playerHand : _opponentHand;
      final battle = _playerActive ? _playerBattle : _opponentBattle;
      final support = _playerActive ? _playerSupport : _opponentSupport;
      if (_round > 1) {
        _refreshAndGrow(resources, faction);
        _readyCards(battle, support);
        _draw(deck, hand, 1);
      }
      _offensiveUsed = false;
      _orderUsedThisTurn = false;
      final entry = hand.length > _maxHandSize
          ? 'Ronda $_round · turno de ${faction.name}. Mano ${hand.length}/$_maxHandSize: juega o descarta antes de cerrar.'
          : 'Ronda $_round · turno de ${faction.name}.';
      _events.insert(0, entry);
      _notice = entry;
    });
    final activeFaction =
        _playerActive ? widget.playerFaction : widget.playerFaction.opponent;
    await _showTurnAnnouncement(activeFaction);
    if (!mounted) return;
    if (widget.mode == GameMode.bot && !_playerActive) {
      await _runBotTurn();
      return;
    }
    setState(() => _transitionBusy = false);
    _startTurnTimer();
  }

  Future<void> _runBotTurn() async {
    if (!mounted) return;
    await _botUseOrder();
    if (!mounted) return;
    setState(() {
      _botDeploy();
      _notice = _events.first;
    });
    await _botUseOrder();
    if (!mounted) return;
    final botReport = await _botAttack();
    if (!mounted) return;
    setState(() {
      _events.insert(
        0,
        'El bot de ${widget.playerFaction.opponent.name} completó su turno.',
      );
      _notice = _events.first;
    });
    if (botReport != null) {
      await _showCombatReport(botReport);
      if (!mounted) return;
    }
    if (_hasVictory) {
      await _showVictory();
      return;
    }
    await _advanceTurn();
  }

  void _refreshAndGrow(List<ResourceToken> resources, Faction faction) {
    for (var i = 0; i < resources.length; i++) {
      resources[i] = resources[i].copyWith(used: false);
    }
    resources.add(ResourceToken(_randomResource(faction)));
  }

  Future<void> _showCard(
    CardDefinition card, {
    required bool playerSide,
  }) async {
    if (_transitionBusy) return;
    _turnClockPaused = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black87,
        builder: (sheetContext) {
          final screen = MediaQuery.sizeOf(sheetContext);
          return SafeArea(
            minimum: const EdgeInsets.all(14),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Container(
                  height: min(410.0, screen.height - 38),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ChronoPalette.panel,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: ChronoPalette.gold.withAlpha(110),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black87,
                        blurRadius: 26,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        flex: 5,
                        child: _CardArtHero(
                          card: card,
                          height: double.infinity,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    card.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(sheetContext)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          height: 1.05,
                                        ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Cerrar',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () =>
                                      Navigator.of(sheetContext).pop(),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                            Text(
                              '${card.code} · ${card.type} · ${card.line}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: ChronoPalette.parchmentMuted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 12,
                              runSpacing: 7,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Coste  '),
                                    _CostCoins(card: card, diameter: 20),
                                  ],
                                ),
                                if (card.force != null ||
                                    card.defense != null)
                                  _DetailChip(
                                    icon: Icons.sports_martial_arts,
                                    text:
                                        'F ${card.force ?? 0} · D ${card.defense ?? 0}',
                                  ),
                                if (_isWall(card))
                                  const _DetailChip(
                                    icon: Icons.fort,
                                    text: 'PROTEGE',
                                  ),
                                if (_canAttackFromSupport(card))
                                  const _DetailChip(
                                    icon: Icons.gps_fixed,
                                    text: 'ALCANCE',
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (card.type == 'Fortificación' ||
                                card.line.contains('Apoyo'))
                              Text(
                                'Apoyo: resiste ${_supportDefenseCapacity(card)} ataque(s) por ofensiva.',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(11),
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: Text(
                                    card.type == 'Orden'
                                        ? card.effect
                                        : 'Las habilidades particulares de unidades y Fortificaciones permanecen desactivadas.',
                                    maxLines: 5,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: ChronoPalette.gold,
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (card.type == 'Unidad')
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _deployCard(
                                        playerSide: playerSide,
                                        card: card,
                                        toSupport: false,
                                      ),
                                      icon: const Icon(Icons.shield),
                                      label: const Text('BATALLA'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () => _deployCard(
                                        playerSide: playerSide,
                                        card: card,
                                        toSupport: true,
                                      ),
                                      icon: const Icon(Icons.security),
                                      label: const Text('APOYO'),
                                    ),
                                  ),
                                ],
                              )
                            else if (card.type == 'Fortificación')
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () => _deployCard(
                                    playerSide: playerSide,
                                    card: card,
                                    toSupport: true,
                                  ),
                                  icon: const Icon(Icons.fort),
                                  label: const Text('DESPLEGAR EN APOYO'),
                                ),
                              )
                            else if (card.type == 'Orden')
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () => _activateOrder(
                                    playerSide: playerSide,
                                    card: card,
                                  ),
                                  icon: const Icon(Icons.auto_awesome),
                                  label: const Text('ACTIVAR ORDEN'),
                                ),
                              )
                            else
                              Text(
                                '${card.type}: su resolución se añadirá en el siguiente bloque.',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: ChronoPalette.gold,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      _turnClockPaused = false;
    }
  }

  Future<void> _showBoardCard(CardInstance instance) async {
    if (_transitionBusy) return;
    final card = instance.card;
    final inSupport =
        _playerSupport.contains(instance) || _opponentSupport.contains(instance);
    _turnClockPaused = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black87,
        builder: (sheetContext) {
          final screen = MediaQuery.sizeOf(sheetContext);
          return SafeArea(
            minimum: const EdgeInsets.all(14),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Container(
                  height: min(330.0, screen.height - 38),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ChronoPalette.panel,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: ChronoPalette.gold.withAlpha(110),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        flex: 5,
                        child: _CardArtHero(
                          card: card,
                          height: double.infinity,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    card.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(sheetContext)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Cerrar',
                                  onPressed: () =>
                                      Navigator.of(sheetContext).pop(),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                            Text('${card.code} · ${card.type}'),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: [
                                _DetailChip(
                                  icon: Icons.sports_martial_arts,
                                  text: 'F ${instance.effectiveForce}',
                                ),
                                _DetailChip(
                                  icon: Icons.shield,
                                  text: 'D ${card.defense ?? 0}',
                                ),
                                _DetailChip(
                                  icon: Icons.broken_image_outlined,
                                  text: 'DAÑO ${instance.damage}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              instance.preparing
                                  ? 'Estado: en Preparación; todavía no puede atacar.'
                                  : instance.tapped
                                      ? 'Estado: girada.'
                                      : 'Estado: lista.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (instance.orderBadge.isNotEmpty)
                              Text(
                                'Orden activa: ${instance.orderBadge}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFE7B7FF),
                                ),
                              ),
                            if (inSupport)
                              Text(
                                _isWall(card)
                                    ? 'Muralla: recibe ${_supportDefenseCapacity(card)} ataques por ofensiva y protege al Comandante.'
                                    : 'Apoyo: recibe 1 ataque y no protege al Comandante.',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            const Spacer(),
                            const Text(
                              'Habilidades particulares desactivadas en esta prueba.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: ChronoPalette.gold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      _turnClockPaused = false;
    }
  }

  Future<void> _showHistory() async {
    if (_transitionBusy || !mounted) return;
    setState(() => _transitionBusy = true);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.history, color: Color(0xFFD6A25E)),
            SizedBox(width: 8),
            Text('Historial de partida'),
          ],
        ),
        content: SizedBox(
          width: 520,
          height: min(380.0, MediaQuery.sizeOf(context).height * .62),
          child: _combatHistory.isEmpty && _actionHistory.isEmpty
              ? const Center(child: Text('Todavía no hay acciones registradas.'))
              : ListView(
                  children: [
                    if (_actionHistory.isNotEmpty) ...[
                      const Text(
                        'INICIATIVA Y ÓRDENES',
                        style: TextStyle(
                          color: Color(0xFFE7B7FF),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final entry in _actionHistory)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Text('• $entry'),
                        ),
                      const Divider(height: 22),
                    ],
                    for (final report in _combatHistory) ...[
                      Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: const Color(0xFF202724),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ronda ${report.round} · ${report.title}',
                            style: const TextStyle(
                              color: Color(0xFFD6A25E),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          for (final line in report.lines)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                line.text,
                                style: TextStyle(
                                  color: line.color,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CERRAR'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _transitionBusy = false);
  }

  Future<void> _showRules() async {
    if (_transitionBusy || !mounted) return;
    setState(() => _transitionBusy = true);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.menu_book, color: Color(0xFFD6A25E)),
            SizedBox(width: 8),
            Text('Reglamento básico'),
          ],
        ),
        content: SizedBox(
          width: 650,
          height: min(520.0, MediaQuery.sizeOf(context).height * .66),
          child: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BoardDiagram(),
                SizedBox(height: 18),
                _RuleItem(
                  number: '1',
                  text: 'Cada mazo tiene 30 cartas: 20 unidades, 5 Fortificaciones y 5 Órdenes. Cada civilización comienza con 6 cartas, 1 recurso y un Comandante con 10 de resistencia.',
                ),
                _RuleItem(
                  number: '2',
                  text: 'Cada jugador lanza 3 dados al inicio. El total más alto comienza; si empatan, ambos vuelven a lanzar.',
                ),
                _RuleItem(
                  number: '3',
                  text: 'Desde la ronda 2, al comenzar tu turno se enderezan tus cartas, robas 1 carta y recibes 1 recurso aleatorio.',
                ),
                _RuleItem(
                  number: '4',
                  text: 'Paga las monedas indicadas para desplegar. Preparación impide atacar ese turno, pero termina al cerrar el turno y la carta podrá defenderse.',
                ),
                _RuleItem(
                  number: '5',
                  text: 'Puedes activar como máximo 1 Orden por turno antes de declarar la ofensiva. Los recursos se pagan después de elegir un objetivo válido y la Orden va al descarte.',
                ),
                _RuleItem(
                  number: '6',
                  text: 'En Apoyo, las cartas normales defienden 1 ataque y no protegen al Comandante. Solo las Fortificaciones con icono de muralla protegen al Comandante y defienden ×2, o ×3 si tienen Defensa 7 o más.',
                ),
                _RuleItem(
                  number: '7',
                  text: 'Batalla y las murallas protegen al Comandante. Si una ofensiva elimina la última protección, abre una Brecha y causa 1 daño. Si comienza Expuesto, puede recibir 1 ataque directo. Máximo 1 daño al Comandante por ofensiva.',
                ),
                _RuleItem(
                  number: '8',
                  text: 'Causar 10 daños gana la partida. Si termina la ronda 15, gana quien conserve más resistencia; un empate se decide por cartas enemigas eliminadas.',
                ),
                _RuleItem(
                  number: '9',
                  text: 'El daño permanece y una carta girada no contraataca. Dispones de 45 segundos antes del cierre automático del turno.',
                ),
                SizedBox(height: 8),
                Text(
                  'CL_V0.8: interfaz táctica renovada. Órdenes simples activadas. Reacciones, Leyendas y habilidades particulares permanecen desactivadas.',
                  style: TextStyle(color: Color(0xFFD6A25E)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ENTENDIDO'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _transitionBusy = false);
  }

  String get _phaseLabel {
    if (_pendingOrder != null) return 'ORDEN · ELEGIR OBJETIVO';
    if (_selectedAttacker != null) return 'OFENSIVA · ELEGIR OBJETIVO';
    if (_attackPlan.isNotEmpty) return 'OFENSIVA · DECLARADA';
    final activeHand = _playerActive ? _playerHand : _opponentHand;
    if (activeHand.length > _maxHandSize) {
      return 'MANO ${activeHand.length}/$_maxHandSize · DESCARTE OBLIGATORIO';
    }
    if (_offensiveUsed) return 'CIERRE DE TURNO';
    return 'DESPLIEGUE Y ÓRDENES';
  }

  @override
  Widget build(BuildContext context) {
    final opponent = widget.playerFaction.opponent;
    final showingOpponentHand =
        widget.mode == GameMode.freeTest && !_playerActive;
    final visibleHand = showingOpponentHand ? _opponentHand : _playerHand;
    final visibleFaction =
        showingOpponentHand ? opponent : widget.playerFaction;
    final visibleResources =
        showingOpponentHand ? _opponentResources : _playerResources;

    Widget battleLine({
      required String label,
      required bool inSupport,
      required Faction faction,
      required List<CardInstance> cards,
      required bool ownerPlayerSide,
    }) {
      return _BattleLine(
        label: label,
        inSupport: inSupport,
        faction: faction,
        cards: cards,
        onCardTap: (card) => _tapBoardCard(
          instance: card,
          ownerPlayerSide: ownerPlayerSide,
          inSupport: inSupport,
        ),
        isSelected: (card) =>
            identical(card, _selectedAttacker) ||
            _attackPlan.any((item) => identical(item.attacker, card)),
        markerNumbers: _attackMarkers,
        markerLabel: _attackMarkerLabel,
        incomingCount: _incomingAttackCount,
        orderSelecting: _pendingOrder != null,
        isOrderTarget: _isValidOrderTarget,
        isAttackTarget: (card) {
          final attacker = _selectedAttacker;
          if (attacker == null || ownerPlayerSide == _playerActive) return false;
          final enemyBattle =
              _playerActive ? _opponentBattle : _playerBattle;
          final enemySupport =
              _playerActive ? _opponentSupport : _playerSupport;
          final attackerInSupport = _playerActive
              ? _playerSupport.contains(attacker)
              : _opponentSupport.contains(attacker);
          if (!attackerInSupport &&
              enemyBattle.isNotEmpty &&
              !enemyBattle.contains(card)) {
            return false;
          }
          if (!attackerInSupport &&
              enemyBattle.isEmpty &&
              enemySupport.isNotEmpty &&
              !enemySupport.contains(card)) {
            return false;
          }
          if (enemySupport.contains(card) &&
              _incomingAttackCount(card) >=
                  _supportDefenseCapacity(card.card)) {
            return false;
          }
          return _canAttackDomain(attacker.card, card.card);
        },
      );
    }

    Widget actionDock() {
      if (_pendingOrder != null) {
        return _ActionStrip(
          icon: Icons.auto_awesome,
          accent: ChronoPalette.order,
          text:
              '${_pendingOrder!.card.name}: selecciona una unidad iluminada.',
          primaryLabel: 'CANCELAR',
          onPrimary: _cancelPendingOrder,
        );
      }
      if (_selectedAttacker != null || _attackPlan.isNotEmpty) {
        return _ActionStrip(
          icon: Icons.flash_on,
          accent: Colors.redAccent,
          text: _selectedAttacker != null
              ? 'Seleccionado: ${_selectedAttacker!.card.name}. Toca su objetivo.'
              : '${_attackPlan.length} ataque(s) declarados. Usa RESOLVER DAÑO para cerrar el turno.',
          primaryLabel: 'CANCELAR',
          onPrimary: _cancelAttackPlan,
        );
      }
      return const SizedBox.shrink();
    }

    Widget commanderPanel({required bool playerSide}) {
      final faction = playerSide ? widget.playerFaction : opponent;
      final battle = playerSide ? _playerBattle : _opponentBattle;
      final support = playerSide ? _playerSupport : _opponentSupport;
      final damage =
          playerSide ? _playerCommanderDamage : _opponentCommanderDamage;
      final eliminations =
          playerSide ? _playerEliminations : _opponentEliminations;
      final handCount = playerSide ? _playerHand.length : _opponentHand.length;
      final deckCount = playerSide ? _playerDeck.length : _opponentDeck.length;
      final discardCount =
          playerSide ? _playerDiscard.length : _opponentDiscard.length;
      final commanderProtected = _commanderIsProtected(battle, support);
      final targetable = playerSide
          ? !_playerActive &&
              _selectedAttacker != null &&
              !commanderProtected &&
              !_attackPlan.any((assignment) => assignment.target == null)
          : _playerActive &&
              _selectedAttacker != null &&
              !commanderProtected &&
              !_attackPlan.any((assignment) => assignment.target == null);

      return _CompactCommanderPanel(
        faction: faction,
        commanderDamage: damage,
        commanderProtected: commanderProtected,
        eliminations: eliminations,
        handCount: handCount,
        deckCount: deckCount,
        discardCount: discardCount,
        active: playerSide == _playerActive,
        targetable: targetable,
        onTap: () => _tapCommander(playerSide),
      );
    }

    return PopScope(
      canPop: _allowExit,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_confirmAbandon());
      },
      child: Scaffold(
        body: BattlefieldBackdrop(
          assetPath: ChronoAssets.battlefield,
          overlayOpacity: .27,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final activeFaction =
                    _playerActive ? widget.playerFaction : opponent;
                final commanderWidth =
                    min(190.0, max(154.0, constraints.maxWidth * .145));
                final handHeight =
                    constraints.maxHeight < 720 ? 122.0 : 146.0;

                final header = _TacticalHeader(
                  faction: activeFaction,
                  phase: _phaseLabel,
                  round: _round,
                  maxRounds: _maxRounds,
                  secondsLeft: _secondsLeft,
                  notice: _notice,
                  onBack: _transitionBusy ? null : _confirmAbandon,
                  onHistory: _transitionBusy ? null : _showHistory,
                  onRules: _transitionBusy ? null : _showRules,
                );

                final opponentZone = Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: commanderWidth,
                      child: commanderPanel(playerSide: false),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: battleLine(
                              label:
                                  'APOYO OPONENTE · ${opponent.name.toUpperCase()}',
                              inSupport: true,
                              faction: opponent,
                              cards: _opponentSupport,
                              ownerPlayerSide: false,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Expanded(
                            child: battleLine(
                              label:
                                  'BATALLA OPONENTE · ${opponent.name.toUpperCase()}',
                              inSupport: false,
                              faction: opponent,
                              cards: _opponentBattle,
                              ownerPlayerSide: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );

                final playerZone = Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: battleLine(
                              label:
                                  'BATALLA MÍA · ${widget.playerFaction.name.toUpperCase()}',
                              inSupport: false,
                              faction: widget.playerFaction,
                              cards: _playerBattle,
                              ownerPlayerSide: true,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Expanded(
                            child: battleLine(
                              label:
                                  'APOYO MÍO · ${widget.playerFaction.name.toUpperCase()}',
                              inSupport: true,
                              faction: widget.playerFaction,
                              cards: _playerSupport,
                              ownerPlayerSide: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: commanderWidth,
                      child: commanderPanel(playerSide: true),
                    ),
                  ],
                );

                final handDock = _CompactHandDock(
                  title: showingOpponentHand
                      ? 'MANO · ${visibleFaction.name.toUpperCase()}'
                      : 'MI MANO Y RECURSOS',
                  cards: visibleHand,
                  faction: visibleFaction,
                  resources: visibleResources,
                  onResourceTap: (index) =>
                      _toggleResource(!showingOpponentHand, index),
                  event: _events.isEmpty ? _notice : _events.first,
                  onCardTap: (card) => _showCard(
                    card,
                    playerSide: !showingOpponentHand,
                  ),
                  onEndTurn:
                      _transitionBusy ? null : () => unawaited(_endTurn()),
                  resolvingAttack: _attackPlan.isNotEmpty,
                );

                return Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    children: [
                      header,
                      const SizedBox(height: 6),
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(child: opponentZone),
                            const _CombatDivider(),
                            Expanded(child: playerZone),
                          ],
                        ),
                      ),
                      actionDock(),
                      const SizedBox(height: 5),
                      SizedBox(height: handHeight, child: handDock),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}


class _CompactCommanderPanel extends StatelessWidget {
  const _CompactCommanderPanel({
    required this.faction,
    required this.commanderDamage,
    required this.commanderProtected,
    required this.eliminations,
    required this.handCount,
    required this.deckCount,
    required this.discardCount,
    required this.active,
    required this.targetable,
    required this.onTap,
  });

  final Faction faction;
  final int commanderDamage;
  final bool commanderProtected;
  final int eliminations;
  final int handCount;
  final int deckCount;
  final int discardCount;
  final bool active;
  final bool targetable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final resistance = max(0, 10 - commanderDamage);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            faction.color.withAlpha(active ? 220 : 145),
            ChronoPalette.panelRaised.withAlpha(245),
          ],
        ),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: targetable
              ? ChronoPalette.valid
              : active
                  ? ChronoPalette.gold
                  : Colors.white12,
          width: targetable || active ? 2 : 1,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Column(
              children: [
                Text(
                  'COMANDANTE · ${faction.name.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 8,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w900,
                    color: ChronoPalette.gold,
                  ),
                ),
                const SizedBox(height: 5),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black26,
                        border: Border.all(
                          color: targetable
                              ? ChronoPalette.valid
                              : ChronoPalette.gold,
                          width: 2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        faction.commanderPortrait,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.shield_outlined,
                          size: 38,
                          color: ChronoPalette.parchment,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  faction.commander,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'RESISTENCIA $resistance/10',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: resistance <= 3
                              ? ChronoPalette.damage
                              : ChronoPalette.parchment,
                        ),
                      ),
                      Text(
                        commanderProtected ? 'PROTEGIDO' : 'EXPUESTO',
                        style: TextStyle(
                          fontSize: 8,
                          letterSpacing: .7,
                          fontWeight: FontWeight.w900,
                          color: commanderProtected
                              ? ChronoPalette.valid
                              : ChronoPalette.warning,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Mazo $deckCount', style: const TextStyle(fontSize: 8)),
                      const SizedBox(width: 7),
                      Text(
                        'Descarte $discardCount',
                        style: const TextStyle(fontSize: 8),
                      ),
                      const SizedBox(width: 7),
                      Text('Mano $handCount', style: const TextStyle(fontSize: 8)),
                      const SizedBox(width: 7),
                      Text('☠ $eliminations', style: const TextStyle(fontSize: 8)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscardHandDialog extends StatefulWidget {
  const _DiscardHandDialog({
    required this.cards,
    required this.requiredCount,
  });

  final List<CardDefinition> cards;
  final int requiredCount;

  @override
  State<_DiscardHandDialog> createState() => _DiscardHandDialogState();
}

class _DiscardHandDialogState extends State<_DiscardHandDialog> {
  final Set<int> _selected = <int>{};

  void _toggle(int index) {
    setState(() {
      if (_selected.remove(index)) return;
      if (_selected.length < widget.requiredCount) _selected.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.requiredCount - _selected.length;
    return AlertDialog(
      icon: const Icon(
        Icons.warning_amber_rounded,
        color: ChronoPalette.warning,
        size: 34,
      ),
      title: const Text('LÍMITE DE MANO'),
      content: SizedBox(
        width: min(880.0, MediaQuery.sizeOf(context).width * .9),
        height: min(245.0, MediaQuery.sizeOf(context).height * .52),
        child: Column(
          children: [
            Text(
              remaining == 0
                  ? 'Selección completa. Confirma el descarte.'
                  : 'Debes elegir $remaining carta(s) más. El máximo permitido es $_maxHandSize.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: remaining == 0
                    ? ChronoPalette.valid
                    : ChronoPalette.parchment,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0;
                      index < widget.cards.length;
                      index++) ...[
                    Expanded(
                      child: _DiscardChoiceCard(
                        card: widget.cards[index],
                        selected: _selected.contains(index),
                        onTap: () => _toggle(index),
                      ),
                    ),
                    if (index != widget.cards.length - 1)
                      const SizedBox(width: 5),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: _selected.length == widget.requiredCount
              ? () => Navigator.of(context).pop(_selected.toList())
              : null,
          icon: const Icon(Icons.delete_outline),
          label: Text('DESCARTAR ${widget.requiredCount}'),
        ),
      ],
    );
  }
}

class _DiscardChoiceCard extends StatelessWidget {
  const _DiscardChoiceCard({
    required this.card,
    required this.selected,
    required this.onTap,
  });

  final CardDefinition card;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: ChronoPalette.panelRaised,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? ChronoPalette.warning : Colors.white24,
              width: selected ? 3 : 1,
            ),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x66FFB74D),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                _cardArtPath(card.code),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: ChronoPalette.panel,
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: ChronoPalette.muted,
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x22000000), Color(0xE6000000)],
                  ),
                ),
              ),
              Positioned(
                left: 5,
                right: 5,
                bottom: 5,
                child: Text(
                  card.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (selected)
                const Positioned(
                  top: 5,
                  right: 5,
                  child: CircleAvatar(
                    radius: 11,
                    backgroundColor: ChronoPalette.warning,
                    child: Icon(Icons.check, size: 15, color: Colors.black),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactHandDock extends StatelessWidget {
  const _CompactHandDock({
    required this.title,
    required this.cards,
    required this.faction,
    required this.resources,
    required this.onResourceTap,
    required this.event,
    required this.onCardTap,
    required this.onEndTurn,
    required this.resolvingAttack,
  });

  final String title;
  final List<CardDefinition> cards;
  final Faction faction;
  final List<ResourceToken> resources;
  final ValueChanged<int> onResourceTap;
  final String event;
  final ValueChanged<CardDefinition> onCardTap;
  final VoidCallback? onEndTurn;
  final bool resolvingAttack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            faction.color.withAlpha(150),
            ChronoPalette.panelRaised,
            ChronoPalette.panel,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ChronoPalette.gold.withAlpha(155)),
        boxShadow: const [
          BoxShadow(color: Colors.black87, blurRadius: 14, offset: Offset(0, 5)),
          BoxShadow(color: Color(0x332E7D6E), blurRadius: 8),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final resourceWidth =
              min(176.0, max(116.0, constraints.maxWidth * .15));
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: resourceWidth,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'RECURSOS',
                        style: TextStyle(
                          fontSize: 8,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w900,
                          color: ChronoPalette.gold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _ResourceRow(
                            resources: resources,
                            onTap: onResourceTap,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.style,
                          size: 13,
                          color: ChronoPalette.gold,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 9,
                            letterSpacing: .8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            event,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 8,
                              color: ChronoPalette.parchmentMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${cards.length}/$_maxHandSize CARTAS',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            color: cards.length > _maxHandSize
                                ? ChronoPalette.damage
                                : ChronoPalette.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: cards.isEmpty
                          ? const Center(
                              child: Text(
                                'SIN CARTAS EN LA MANO',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: ChronoPalette.muted,
                                ),
                              ),
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var index = 0;
                                    index < cards.length;
                                    index++) ...[
                                  Expanded(
                                    child: _HandCard(
                                      card: cards[index],
                                      faction: faction,
                                      onTap: () => onCardTap(cards[index]),
                                    ),
                                  ),
                                  if (index != cards.length - 1)
                                    const SizedBox(width: 4),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              SizedBox(
                width: 104,
                child: FilledButton(
                  onPressed: onEndTurn,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    backgroundColor: resolvingAttack
                        ? ChronoPalette.damage
                        : ChronoPalette.gold,
                    foregroundColor: resolvingAttack
                        ? Colors.white
                        : Colors.black87,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        resolvingAttack ? Icons.flash_on : Icons.skip_next,
                        size: 19,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        resolvingAttack
                            ? 'RESOLVER\nDAÑO'
                            : 'TERMINAR\nTURNO',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 9,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TacticalHeader extends StatelessWidget {
  const _TacticalHeader({
    required this.faction,
    required this.phase,
    required this.round,
    required this.maxRounds,
    required this.secondsLeft,
    required this.notice,
    required this.onBack,
    required this.onHistory,
    required this.onRules,
  });

  final Faction faction;
  final String phase;
  final int round;
  final int maxRounds;
  final int secondsLeft;
  final String notice;
  final VoidCallback? onBack;
  final VoidCallback? onHistory;
  final VoidCallback? onRules;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            faction.color.withAlpha(165),
            ChronoPalette.panelRaised.withAlpha(245),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ChronoPalette.gold.withAlpha(155)),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Abandonar partida',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          ),
          const _ChronoMark(size: 34),
          const SizedBox(width: 9),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CHRONO LEGIONS',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.7,
                ),
              ),
              Text(
                'CL_V0.8 · CAMPO TÁCTICO',
                style: TextStyle(
                  fontSize: 8,
                  color: ChronoPalette.parchmentMuted,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  faction.name.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: ChronoPalette.parchment,
                  ),
                ),
                Text(
                  phase,
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              'RONDA $round/$maxRounds',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              notice,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: secondsLeft <= 10
                  ? ChronoPalette.damage.withAlpha(150)
                  : Colors.black26,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: secondsLeft <= 10
                    ? ChronoPalette.damage
                    : Colors.white12,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, size: 16),
                const SizedBox(width: 4),
                Text(
                  '$secondsLeft s',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Historial',
            onPressed: onHistory,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Reglamento',
            onPressed: onRules,
            icon: const Icon(Icons.menu_book_outlined),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _CommanderDock extends StatelessWidget {
  const _CommanderDock({
    required this.faction,
    required this.commanderDamage,
    required this.commanderProtected,
    required this.eliminations,
    required this.handCount,
    required this.deckCount,
    required this.discardCount,
    required this.resources,
    required this.onResourceTap,
    required this.active,
    required this.targetable,
    required this.onCommanderTap,
  });

  final Faction faction;
  final int commanderDamage;
  final bool commanderProtected;
  final int eliminations;
  final int handCount;
  final int deckCount;
  final int discardCount;
  final List<ResourceToken> resources;
  final ValueChanged<int> onResourceTap;
  final bool active;
  final bool targetable;
  final VoidCallback onCommanderTap;

  @override
  Widget build(BuildContext context) {
    final resistance = max(0, 10 - commanderDamage);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            faction.color.withAlpha(active ? 220 : 125),
            ChronoPalette.panelRaised,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: targetable
              ? ChronoPalette.valid
              : active
                  ? ChronoPalette.gold
                  : Colors.white12,
          width: targetable || active ? 2 : 1,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onCommanderTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black26,
                        border: Border.all(
                          color: targetable
                              ? ChronoPalette.valid
                              : ChronoPalette.gold,
                          width: targetable ? 2.5 : 1.5,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        faction.commanderPortrait,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.shield_outlined,
                          color: ChronoPalette.parchment,
                        ),
                      ),
                    ),
                    if (targetable)
                      const Positioned(
                        right: 0,
                        bottom: 0,
                        child: CircleAvatar(
                          radius: 10,
                          backgroundColor: ChronoPalette.valid,
                          child: Icon(
                            Icons.gps_fixed,
                            size: 13,
                            color: Colors.black,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        faction.name.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                          color: ChronoPalette.parchmentMuted,
                        ),
                      ),
                      Text(
                        faction.commander,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _DockStat(
                    label: 'RESIST.',
                    value: '$resistance/10',
                    accent: resistance <= 3
                        ? ChronoPalette.damage
                        : ChronoPalette.parchment,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: _DockStat(
                    label: 'ESTADO',
                    value: commanderProtected ? 'PROTEGIDO' : 'EXPUESTO',
                    accent: commanderProtected
                        ? ChronoPalette.valid
                        : ChronoPalette.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 4,
              children: [
                Text('Mazo $deckCount', style: const TextStyle(fontSize: 9)),
                Text('Mano $handCount', style: const TextStyle(fontSize: 9)),
                Text('Descarte $discardCount', style: const TextStyle(fontSize: 9)),
                Text('☠ $eliminations', style: const TextStyle(fontSize: 9)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'RECURSOS',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: ChronoPalette.parchmentMuted,
              ),
            ),
            const SizedBox(height: 4),
            _ResourceRow(resources: resources, onTap: onResourceTap),
          ],
        ),
      ),
    );
  }
}

class _DockStat extends StatelessWidget {
  const _DockStat({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 7,
              color: ChronoPalette.muted,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              color: accent,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _BattleLogRail extends StatelessWidget {
  const _BattleLogRail({
    required this.events,
    required this.phase,
    required this.activeFaction,
    required this.playerEliminations,
    required this.opponentEliminations,
    required this.onHistory,
    required this.onRules,
  });

  final List<String> events;
  final String phase;
  final String activeFaction;
  final int playerEliminations;
  final int opponentEliminations;
  final VoidCallback? onHistory;
  final VoidCallback? onRules;

  @override
  Widget build(BuildContext context) {
    final recent = events.take(9).toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 9, 10, 9),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: ChronoPalette.panel.withAlpha(240),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ChronoPalette.gold.withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.insights, size: 18, color: ChronoPalette.gold),
              SizedBox(width: 6),
              Text(
                'PANEL TÁCTICO',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 34,
            width: double.infinity,
            child: Image.asset(
              ChronoAssets.resourceBattleIcons,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 8),
          _RailInfo(label: 'TURNO', value: activeFaction.toUpperCase()),
          const SizedBox(height: 5),
          _RailInfo(label: 'FASE', value: phase),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _DockStat(
                  label: 'TUS BAJAS',
                  value: '$playerEliminations',
                  accent: ChronoPalette.parchment,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: _DockStat(
                  label: 'BAJAS RIVAL',
                  value: '$opponentEliminations',
                  accent: ChronoPalette.parchment,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          const Text(
            'CRÓNICA DE BATALLA',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
              color: ChronoPalette.parchmentMuted,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: recent.isEmpty
                ? const Center(
                    child: Text(
                      'Sin acciones todavía.',
                      style: TextStyle(color: ChronoPalette.muted),
                    ),
                  )
                : ListView.separated(
                    itemCount: recent.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 5),
                    itemBuilder: (context, index) => Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: index == 0
                            ? ChronoPalette.panelRaised
                            : Colors.black12,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: index == 0
                              ? ChronoPalette.gold.withAlpha(70)
                              : Colors.white10,
                        ),
                      ),
                      child: Text(
                        recent[index],
                        style: TextStyle(
                          fontSize: 9.5,
                          height: 1.25,
                          color: index == 0
                              ? ChronoPalette.text
                              : ChronoPalette.parchmentMuted,
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onHistory,
                  child: const Text('HISTORIAL'),
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: OutlinedButton(
                  onPressed: onRules,
                  child: const Text('REGLAS'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RailInfo extends StatelessWidget {
  const _RailInfo({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 7,
              fontWeight: FontWeight.w900,
              color: ChronoPalette.muted,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _CombatDivider extends StatelessWidget {
  const _CombatDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: ChronoPalette.gold)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(Icons.flash_on, size: 14, color: ChronoPalette.gold),
                SizedBox(width: 4),
                Text(
                  'ZONA DE COMBATE',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: ChronoPalette.parchmentMuted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: Divider(color: ChronoPalette.gold)),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _HandTray extends StatelessWidget {
  const _HandTray({
    required this.title,
    required this.count,
    required this.child,
  });

  final String title;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 174,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 9),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [ChronoPalette.panelRaised, ChronoPalette.panel],
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ChronoPalette.gold.withAlpha(85)),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.style, size: 14, color: ChronoPalette.gold),
              const SizedBox(width: 5),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                '$count CARTAS',
                style: const TextStyle(
                  fontSize: 8,
                  color: ChronoPalette.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _ActionStrip extends StatelessWidget {
  const _ActionStrip({
    required this.icon,
    required this.accent,
    required this.text,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final Color accent;
  final String text;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withAlpha(38),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: accent),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 7),
          Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
          TextButton(onPressed: onPrimary, child: Text(primaryLabel)),
          if (secondaryLabel != null) ...[
            const SizedBox(width: 5),
            FilledButton(
              onPressed: onSecondary,
              child: Text(secondaryLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _InitiativeDiceRow extends StatelessWidget {
  const _InitiativeDiceRow({
    required this.faction,
    required this.dice,
    required this.total,
  });

  final Faction faction;
  final List<int> dice;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(
            faction.name.toUpperCase(),
            style: TextStyle(
              color: faction.color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        for (final value in dice) ...[
          _DieFace(value: value, size: 42),
          const SizedBox(width: 7),
        ],
        const Spacer(),
        Text(
          '= $total',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _DieFace extends StatelessWidget {
  const _DieFace({required this.value, required this.size});

  final int value;
  final double size;

  @override
  Widget build(BuildContext context) {
    const faces = ['⚀', '⚁', '⚂', '⚃', '⚄', '⚅'];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF4E3C1),
        borderRadius: BorderRadius.circular(size * .16),
        border: Border.all(color: const Color(0xFFD6A25E), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Text(
        faces[value - 1],
        style: TextStyle(
          color: const Color(0xFF241A10),
          fontSize: size * .78,
          height: 1,
        ),
      ),
    );
  }
}


class _SupportDefenseDialog extends StatefulWidget {
  const _SupportDefenseDialog({
    required this.attackers,
    required this.defenders,
    required this.initialCapacity,
    required this.canAttackDomain,
  });

  final List<CardInstance> attackers;
  final List<CardInstance> defenders;
  final Map<CardInstance, int> initialCapacity;
  final bool Function(CardDefinition, CardDefinition) canAttackDomain;

  @override
  State<_SupportDefenseDialog> createState() =>
      _SupportDefenseDialogState();
}

class _SupportDefenseDialogState extends State<_SupportDefenseDialog> {
  late final Map<CardInstance, int> _usedCapacity;
  final List<AttackAssignment> _assignments = [];
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _usedCapacity = Map<CardInstance, int>.from(widget.initialCapacity);
    WidgetsBinding.instance.addPostFrameCallback((_) => _skipUnavailable());
  }

  List<CardInstance> _availableFor(CardInstance attacker) =>
      widget.defenders.where((defender) {
        final compatible =
            widget.canAttackDomain(attacker.card, defender.card);
        final used = _usedCapacity[defender] ?? 0;
        return compatible && used < _supportDefenseCapacity(defender.card);
      }).toList();

  void _skipUnavailable() {
    if (!mounted) return;
    while (_index < widget.attackers.length &&
        _availableFor(widget.attackers[_index]).isEmpty) {
      _index++;
    }
    if (_index >= widget.attackers.length) {
      Navigator.of(context).pop(_assignments);
    } else {
      setState(() {});
    }
  }

  void _selectDefender(CardInstance defender) {
    final attacker = widget.attackers[_index];
    _assignments.add(AttackAssignment(attacker: attacker, target: defender));
    _usedCapacity[defender] = (_usedCapacity[defender] ?? 0) + 1;
    _index++;
    _skipUnavailable();
  }

  @override
  Widget build(BuildContext context) {
    if (_index >= widget.attackers.length) {
      return const AlertDialog(
        content: SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final attacker = widget.attackers[_index];
    final available = _availableFor(attacker);
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.security, color: Color(0xFFD6A25E)),
          SizedBox(width: 8),
          Expanded(child: Text('Elige quién defiende')),
        ],
      ),
      content: SizedBox(
        width: 540,
        height: min(390.0, MediaQuery.sizeOf(context).height * .62),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ataque ${_index + 1} de ${widget.attackers.length}',
              style: const TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 6),
            Text(
              '${attacker.card.name} · Fuerza ${attacker.effectiveForce}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            const Text('Selecciona una carta de Apoyo:'),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: widget.defenders.length,
                separatorBuilder: (_, _) => const SizedBox(height: 7),
                itemBuilder: (context, index) {
                  final defender = widget.defenders[index];
                  final enabled = available.contains(defender);
                  final used = _usedCapacity[defender] ?? 0;
                  final capacity = _supportDefenseCapacity(defender.card);
                  final remainingDefense = max(
                    0,
                    (defender.card.defense ?? 0) - defender.damage,
                  );
                  return OutlinedButton(
                    onPressed: enabled ? () => _selectDefender(defender) : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(11),
                      alignment: Alignment.centerLeft,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            defender.card.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text('🛡 $remainingDefense'),
                        const SizedBox(width: 12),
                        if (_isWall(defender.card)) ...[
                          const Icon(
                            Icons.fort,
                            size: 17,
                            color: Color(0xFFD6A25E),
                          ),
                          const SizedBox(width: 4),
                        ] else ...[
                          const Text(
                            'DEF',
                            style: TextStyle(fontSize: 10),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text('$used/$capacity'),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'La aplicación impide superar automáticamente la capacidad de cada defensor.',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardDiagram extends StatelessWidget {
  const _BoardDiagram();

  @override
  Widget build(BuildContext context) {
    Widget line(String label, Color color) => Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 9),
          margin: const EdgeInsets.only(bottom: 5),
          decoration: BoxDecoration(
            color: color.withAlpha(85),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withAlpha(180)),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF171D1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD6A25E)),
      ),
      child: Column(
        children: [
          line('APOYO RIVAL · 5 espacios', const Color(0xFF275D59)),
          line('BATALLA RIVAL · 5 espacios', const Color(0xFF275D59)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Divider(color: Color(0xFFD6A25E))),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'ZONA DE COMBATE',
                    style: TextStyle(fontSize: 9, color: Color(0xFFD6A25E)),
                  ),
                ),
                Expanded(child: Divider(color: Color(0xFFD6A25E))),
              ],
            ),
          ),
          line('BATALLA PROPIA · 5 espacios', const Color(0xFF8C2F2B)),
          line('APOYO PROPIO · 5 espacios', const Color(0xFF8C2F2B)),
          const SizedBox(height: 4),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _DiagramBadge(icon: Icons.style, label: 'Mano'),
              _DiagramBadge(icon: Icons.shield, label: 'Comandante'),
              _DiagramBadge(icon: Icons.paid, label: 'Recursos'),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiagramBadge extends StatelessWidget {
  const _DiagramBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFFD6A25E)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}

class _RuleItem extends StatelessWidget {
  const _RuleItem({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFD6A25E),
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _PlayerPanel extends StatelessWidget {
  const _PlayerPanel({
    required this.faction,
    required this.commanderDamage,
    required this.commanderProtected,
    required this.eliminations,
    required this.handCount,
    required this.deckCount,
    required this.discardCount,
    required this.resources,
    required this.onResourceTap,
    required this.active,
    required this.hiddenHand,
    required this.onCommanderTap,
  });

  final Faction faction;
  final int commanderDamage;
  final bool commanderProtected;
  final int eliminations;
  final int handCount;
  final int deckCount;
  final int discardCount;
  final List<ResourceToken> resources;
  final ValueChanged<int> onResourceTap;
  final bool active;
  final bool hiddenHand;
  final VoidCallback onCommanderTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: active ? faction.color : const Color(0xFF202724),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? const Color(0xFFD6A25E) : Colors.white12,
          width: active ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onCommanderTap,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: Color(0xFFFFD89A)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            faction.commander,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 3,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'Resistencia ${max(0, 10 - commanderDamage)}/10',
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: commanderProtected
                                      ? const Color(0xFF315A43)
                                      : const Color(0xFF7A2525),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      commanderProtected
                                          ? Icons.lock_outline
                                          : Icons.warning_amber,
                                      size: 12,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      commanderProtected
                                          ? 'PROTEGIDO'
                                          : 'EXPUESTO',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '☠ $eliminations',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: _ResourceRow(resources: resources, onTap: onResourceTap),
          ),
          const SizedBox(width: 8),
          Text('Mazo $deckCount'),
          const SizedBox(width: 10),
          Text('Descarte $discardCount'),
          const SizedBox(width: 10),
          Text('${hiddenHand ? 'Mano rival' : 'Mano'} $handCount'),
        ],
      ),
    );
  }
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({required this.resources, required this.onTap});

  final List<ResourceToken> resources;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final grouped = <ResourceType, List<int>>{
      for (final type in ResourceType.values) type: <int>[],
    };
    for (var index = 0; index < resources.length; index++) {
      grouped[resources[index].type]!.add(index);
    }

    return SizedBox(
      height: 50,
      child: Row(
        children: [
          for (final type in ResourceType.values) ...[
            Expanded(
              child: _ResourceGroup(
                type: type,
                indexes: grouped[type]!,
                resources: resources,
                onTap: onTap,
              ),
            ),
            if (type != ResourceType.values.last) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _ResourceGroup extends StatelessWidget {
  const _ResourceGroup({
    required this.type,
    required this.indexes,
    required this.resources,
    required this.onTap,
  });

  final ResourceType type;
  final List<int> indexes;
  final List<ResourceToken> resources;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final available =
        indexes.where((index) => !resources[index].used).toList();
    final used = indexes.where((index) => resources[index].used).toList();
    final color = switch (type) {
      ResourceType.earth => const Color(0xFF8B5A2B),
      ResourceType.sea => const Color(0xFF1769AA),
      ResourceType.air => const Color(0xFF78C7E8),
    };
    final icon = switch (type) {
      ResourceType.earth => Icons.landscape,
      ResourceType.sea => Icons.water_drop,
      ResourceType.air => Icons.air,
    };
    final label = switch (type) {
      ResourceType.earth => 'TIERRA',
      ResourceType.sea => 'MAR',
      ResourceType.air => 'AIRE',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withAlpha(125)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Tooltip(
              message: available.isEmpty
                  ? 'No quedan recursos $label disponibles'
                  : 'Gastar 1 recurso $label',
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap:
                    available.isEmpty ? null : () => onTap(available.first),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: available.isEmpty
                            ? const Color(0xFF303030)
                            : color,
                        border: Border.all(color: Colors.white38),
                      ),
                      child: Icon(icon, size: 11, color: Colors.white),
                    ),
                    const SizedBox(width: 2),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '×${available.length}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(
                    fontSize: 5.5,
                    letterSpacing: .3,
                    color: ChronoPalette.parchmentMuted,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Tooltip(
                message: used.isEmpty
                    ? 'No hay recursos $label gastados'
                    : 'Recuperar 1 recurso $label',
                child: InkWell(
                  borderRadius: BorderRadius.circular(7),
                  onTap: used.isEmpty ? null : () => onTap(used.last),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF303030),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      'G×${used.length}',
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.w900,
                        color: ChronoPalette.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BattleLine extends StatelessWidget {
  const _BattleLine({
    required this.label,
    required this.inSupport,
    required this.faction,
    required this.cards,
    required this.onCardTap,
    required this.isSelected,
    required this.markerNumbers,
    required this.markerLabel,
    required this.incomingCount,
    required this.orderSelecting,
    required this.isOrderTarget,
    required this.isAttackTarget,
  });

  final String label;
  final bool inSupport;
  final Faction faction;
  final List<CardInstance> cards;
  final ValueChanged<CardInstance> onCardTap;
  final bool Function(CardInstance) isSelected;
  final List<int> Function(CardInstance) markerNumbers;
  final String Function(int) markerLabel;
  final int Function(CardInstance) incomingCount;
  final bool orderSelecting;
  final bool Function(CardInstance) isOrderTarget;
  final bool Function(CardInstance) isAttackTarget;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            faction.color.withAlpha(inSupport ? 70 : 105),
            ChronoPalette.panel.withAlpha(205),
            Colors.black.withAlpha(190),
          ],
        ),
        border: Border.all(
          color: faction.color.withAlpha(inSupport ? 135 : 190),
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 4)),
          BoxShadow(color: Color(0x22D6A25E), blurRadius: 6),
        ],
      ),
      padding: const EdgeInsets.all(7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Colors.white60,
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Row(
              children: List.generate(5, (index) {
              final instance = index < cards.length ? cards[index] : null;
              final markers = instance == null ? <int>[] : markerNumbers(instance);
              final totalDefense = instance?.card.defense ?? 0;
              final remainingDefense =
                  instance == null ? 0 : max(0, totalDefense - instance.damage);
              final receivedAttacks =
                  instance == null ? 0 : incomingCount(instance);
              final validOrderTarget =
                  instance != null && orderSelecting && isOrderTarget(instance);
              final validAttackTarget =
                  instance != null && isAttackTarget(instance);
              final defenseColor = remainingDefense == totalDefense
                  ? const Color(0xFF69F0AE)
                  : remainingDefense <= max(1, totalDefense ~/ 3)
                      ? const Color(0xFFFF5252)
                      : const Color(0xFFFFD740);
              return Expanded(
                child: Container(
                  height: double.infinity,
                  margin: EdgeInsets.only(right: index == 4 ? 0 : 5),
                  decoration: BoxDecoration(
                    color: instance == null ? Colors.black26 : faction.color,
                    image: instance == null
                        ? null
                        : DecorationImage(
                            image: AssetImage(
                              _cardArtPath(instance.card.code),
                            ),
                            fit: BoxFit.cover,
                            colorFilter: ColorFilter.mode(
                              Colors.black.withAlpha(62),
                              BlendMode.darken,
                            ),
                          ),
                    borderRadius: BorderRadius.circular(7),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 5,
                        offset: Offset(0, 2),
                      ),
                    ],
                    border: Border.all(
                      color: validOrderTarget
                          ? ChronoPalette.order
                          : validAttackTarget
                              ? ChronoPalette.valid
                              : markers.isNotEmpty
                          ? _attackColors[(markers.first - 1) % _attackColors.length]
                          : instance != null && isSelected(instance)
                              ? Colors.redAccent
                              : instance?.preparing == true
                                  ? const Color(0xFFD6A25E)
                                  : Colors.white12,
                      width: instance != null &&
                              (validOrderTarget ||
                                  validAttackTarget ||
                                  markers.isNotEmpty ||
                                  isSelected(instance) ||
                                  instance.preparing)
                          ? 2
                          : 1,
                    ),
                  ),
                  child: instance == null
                      ? const Center(
                          child: Icon(Icons.add, size: 17, color: Colors.white24),
                        )
                      : Stack(
                          children: [
                            Positioned.fill(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(7),
                                onTap: () => onCardTap(instance),
                                child: Padding(
                                  padding: const EdgeInsets.all(5),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: EdgeInsets.only(
                                          right: markers.isEmpty ? 0 : 22,
                                        ),
                                        child: Text(
                                          instance.card.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      if (instance.preparing)
                                        const Text(
                                          'PREPARACIÓN',
                                          style: TextStyle(
                                            fontSize: 7,
                                            color: Color(0xFFFFD740),
                                          ),
                                        ),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Row(
                                          children: [
                                            const Text(
                                              '⚔',
                                              style: TextStyle(fontSize: 9),
                                            ),
                                            const SizedBox(width: 2),
                                            Text(
                                              '${instance.effectiveForce}',
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: instance.orderBadge.isNotEmpty
                                                    ? const Color(0xFFE7B7FF)
                                                    : Colors.white,
                                                fontWeight: instance.orderBadge.isNotEmpty
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            Icon(
                                              Icons.shield_outlined,
                                              size: 11,
                                              color: defenseColor,
                                            ),
                                            const SizedBox(width: 2),
                                            Text(
                                              '$remainingDefense/$totalDefense',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: defenseColor,
                                              ),
                                            ),
                                            if (inSupport &&
                                                _isWall(instance.card)) ...[
                                              const SizedBox(width: 5),
                                              const Icon(
                                                Icons.fort,
                                                size: 11,
                                                color: Colors.white70,
                                              ),
                                              const SizedBox(width: 2),
                                              Text(
                                                receivedAttacks == 0
                                                    ? '×${_supportDefenseCapacity(instance.card)}'
                                                    : '$receivedAttacks/${_supportDefenseCapacity(instance.card)}',
                                                style: const TextStyle(fontSize: 9),
                                              ),
                                            ],
                                            if (_canAttackFromSupport(instance.card)) ...[
                                              const SizedBox(width: 5),
                                              const _TargetRangeIcon(size: 12),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (instance.orderBadge.isNotEmpty)
                              Positioned(
                                top: 3,
                                left: 3,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF5B2C6F),
                                    borderRadius: BorderRadius.circular(7),
                                    border: Border.all(
                                      color: const Color(0xFFE7B7FF),
                                    ),
                                  ),
                                  child: Text(
                                    instance.orderBadge,
                                    style: const TextStyle(
                                      fontSize: 7,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            if (orderSelecting && !validOrderTarget)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withAlpha(110),
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                  ),
                                ),
                              ),
                            if (instance.tapped)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withAlpha(115),
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    child: const Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.rotate_right,
                                            size: 20,
                                            color: Color(0xFFFFD740),
                                          ),
                                          Text(
                                            'GIRADA',
                                            style: TextStyle(
                                              fontSize: 8,
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFFFFD740),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (markers.isNotEmpty)
                              Positioned(
                                top: 3,
                                right: 3,
                                child: Column(
                                  children: [
                                    for (final marker in markers.take(3))
                                      Container(
                                        constraints: const BoxConstraints(minWidth: 27),
                                        height: 18,
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        margin: const EdgeInsets.only(bottom: 2),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(9),
                                          color: _attackColors[(marker - 1) % _attackColors.length],
                                          border: Border.all(color: Colors.white, width: 1),
                                        ),
                                        child: Text(
                                          markerLabel(marker),
                                          style: const TextStyle(
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
              );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetRangeIcon extends StatelessWidget {
  const _TargetRangeIcon({this.size = 14});

  final double size;

  @override
  Widget build(BuildContext context) {
    final ring = size * .13;
    return Tooltip(
      message: 'Puede atacar desde Apoyo',
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(ring),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: Colors.black54, width: .5),
        ),
        child: Container(
          padding: EdgeInsets.all(ring),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFD32F2F),
          ),
          child: Container(
            padding: EdgeInsets.all(ring * .8),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFD32F2F),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CostCoins extends StatelessWidget {
  const _CostCoins({required this.card, required this.diameter});

  final CardDefinition card;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final types = <ResourceType?>[
      ...List<ResourceType>.filled(card.earth, ResourceType.earth),
      ...List<ResourceType>.filled(card.sea, ResourceType.sea),
      ...List<ResourceType?>.filled(card.generic, null),
    ];
    if (types.isEmpty) {
      return Container(
        width: diameter,
        height: diameter,
        alignment: Alignment.center,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFB0B0B0)),
        child: Text('0', style: TextStyle(fontSize: diameter * .55, color: Colors.black)),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < types.length; i++)
          Container(
            width: diameter,
            height: diameter,
            margin: EdgeInsets.only(left: i == 0 ? 0 : 1),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: types[i] == ResourceType.earth
                  ? const Color(0xFF8B5A2B)
                  : types[i] == ResourceType.sea
                      ? const Color(0xFF1769AA)
                      : const Color(0xFFC9A75D),
              border: Border.all(color: Colors.white54, width: .7),
            ),
            child: Icon(
              types[i] == ResourceType.earth
                  ? Icons.landscape
                  : types[i] == ResourceType.sea
                      ? Icons.water_drop
                      : Icons.circle,
              size: diameter * .55,
              color: types[i] == null ? const Color(0xFF5B4A28) : Colors.white,
            ),
          ),
      ],
    );
  }
}

class _CardArtHero extends StatelessWidget {
  const _CardArtHero({required this.card, this.height = 190});

  final CardDefinition card;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ChronoPalette.gold.withAlpha(125)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            _cardArtPath(card.code),
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, _, _) => const ColoredBox(
              color: ChronoPalette.panel,
              child: Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: ChronoPalette.muted,
                ),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xC9000000)],
              ),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(175),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ChronoPalette.gold.withAlpha(100)),
              ),
              child: Text(
                card.code,
                style: const TextStyle(
                  fontSize: 9,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w900,
                  color: ChronoPalette.gold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: ChronoPalette.gold),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _HandCard extends StatelessWidget {
  const _HandCard({
    required this.card,
    required this.faction,
    required this.onTap,
  });

  final CardDefinition card;
  final Faction faction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent =
        card.type == 'Orden' ? ChronoPalette.order : ChronoPalette.gold;
    return SizedBox(
      width: 112,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: faction.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(color: accent.withAlpha(165)),
        ),
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                _cardArtPath(card.code),
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: card.type == 'Orden'
                      ? const Color(0xFF5B2C6F)
                      : faction.color,
                  child: const Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      size: 22,
                      color: Colors.white24,
                    ),
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xB8000000),
                      Color(0x18000000),
                      Color(0xE6000000),
                    ],
                    stops: [0, .42, 1],
                  ),
                ),
              ),
              Positioned(
                top: 5,
                left: 6,
                right: 5,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        card.code,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        style: const TextStyle(
                          fontSize: 7,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topRight,
                        child: _CostCoins(card: card, diameter: 11),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      card.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            card.type,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 7,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        if (card.force != null || card.defense != null)
                          Text(
                            '⚔${card.force ?? 0}  🛡${card.defense ?? 0}',
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        if (_isWall(card)) ...[
                          const SizedBox(width: 3),
                          const Icon(Icons.fort, size: 9),
                        ],
                        if (_canAttackFromSupport(card)) ...[
                          const SizedBox(width: 3),
                          const _TargetRangeIcon(size: 9),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const String _deckJson = r'''{
  "roma": [
    {
      "code": "ROM-001",
      "name": "Manípulo de Hastati",
      "type": "Unidad",
      "copies": 2,
      "cost": 2,
      "earth": 1,
      "sea": 0,
      "generic": 1,
      "role": "Presencia de línea",
      "force": 1,
      "defense": 3,
      "line": "Batalla",
      "effect": "Mientras comparta línea con otra unidad romana de la misma clase, obtiene +1 Defensa.",
      "icons": "[FORMA] 🛡+1",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "ROM-003",
      "name": "Principes Veteranos",
      "type": "Unidad",
      "copies": 2,
      "cost": 4,
      "earth": 2,
      "sea": 0,
      "generic": 2,
      "role": "Presencia de línea",
      "force": 3,
      "defense": 5,
      "line": "Batalla",
      "effect": "Al entrar, restaura 1 daño de otra unidad romana de su línea.",
      "icons": "[ENTRA] ♻1",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "ROM-005",
      "name": "Triarii de la Reserva",
      "type": "Unidad",
      "copies": 1,
      "cost": 2,
      "earth": 1,
      "sea": 0,
      "generic": 1,
      "role": "Presencia de línea",
      "force": 1,
      "defense": 3,
      "line": "Batalla",
      "effect": "Cuando sea destruida, roba 1 carta y luego descarta 1 carta.",
      "icons": "[DESTRUIDA] ≡1",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "ROM-007",
      "name": "Velites de Vanguardia",
      "type": "Unidad",
      "copies": 2,
      "cost": 4,
      "earth": 2,
      "sea": 0,
      "generic": 2,
      "role": "Presencia de línea",
      "force": 3,
      "defense": 5,
      "line": "Batalla",
      "effect": "Obtiene +1 Fuerza durante el contraataque cuando defiende.",
      "icons": "[AL DEFENDER] ⚔+1",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "ROM-009",
      "name": "Equites Romanos",
      "type": "Unidad",
      "copies": 2,
      "cost": 3,
      "earth": 2,
      "sea": 0,
      "generic": 1,
      "role": "Movilidad y ataque",
      "force": 4,
      "defense": 3,
      "line": "Batalla",
      "effect": "Mientras esté preparada, obtiene +1 Defensa.",
      "icons": "[PREPARADA] 🛡+1",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": true
    },
    {
      "code": "ROM-011",
      "name": "Infantería Latina",
      "type": "Unidad",
      "copies": 2,
      "cost": 4,
      "earth": 2,
      "sea": 0,
      "generic": 2,
      "role": "Presencia de línea",
      "force": 3,
      "defense": 5,
      "line": "Batalla",
      "effect": "Mientras comparta línea con otra unidad romana de la misma clase, obtiene +1 Defensa.",
      "icons": "[FORMA] 🛡+1",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "ROM-016",
      "name": "Extraordinarii Pedites",
      "type": "Unidad",
      "copies": 2,
      "cost": 1,
      "earth": 1,
      "sea": 0,
      "generic": 0,
      "role": "Presencia de línea",
      "force": 1,
      "defense": 2,
      "line": "Batalla",
      "effect": "Mientras comparta línea con otra unidad romana de la misma clase, obtiene +1 Defensa.",
      "icons": "[FORMA] 🛡+1",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "ROM-022",
      "name": "Escorpiones Romanos",
      "type": "Unidad",
      "copies": 2,
      "cost": 5,
      "earth": 2,
      "sea": 0,
      "generic": 3,
      "role": "Presión desde Apoyo",
      "force": 5,
      "defense": 4,
      "line": "Apoyo",
      "effect": "Obtiene +1 Fuerza durante el contraataque cuando defiende.",
      "icons": "[AL DEFENDER] ⚔+1",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": true,
      "longRange": true,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "ROM-026",
      "name": "Quinquerreme Romana",
      "type": "Unidad",
      "copies": 2,
      "cost": 5,
      "earth": 0,
      "sea": 2,
      "generic": 3,
      "role": "Presencia de línea",
      "force": 6,
      "defense": 6,
      "line": "Batalla",
      "effect": "Mientras comparta línea con otra unidad romana de la misma clase, obtiene +1 Defensa.",
      "icons": "[FORMA] 🛡+1",
      "domain": "Naval",
      "attacksEarth": true,
      "attacksSea": true,
      "longRange": false,
      "precision": true,
      "maneuver": false
    },
    {
      "code": "ROM-033",
      "name": "Trirremes de Massalia",
      "type": "Unidad",
      "copies": 1,
      "cost": 4,
      "earth": 0,
      "sea": 2,
      "generic": 2,
      "role": "Presencia de línea",
      "force": 5,
      "defense": 5,
      "line": "Batalla",
      "effect": "Al entrar, restaura 1 daño de otra unidad romana de su línea.",
      "icons": "[ENTRA] ♻1",
      "domain": "Naval",
      "attacksEarth": true,
      "attacksSea": true,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "ROM-034",
      "name": "Supervivientes de Cannas",
      "type": "Unidad",
      "copies": 1,
      "cost": 3,
      "earth": 2,
      "sea": 0,
      "generic": 1,
      "role": "Presencia de línea",
      "force": 2,
      "defense": 4,
      "line": "Batalla",
      "effect": "Mientras esté preparada, obtiene +1 Defensa.",
      "icons": "[PREPARADA] 🛡+1",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "ROM-035",
      "name": "Defensores de Nola",
      "type": "Unidad",
      "copies": 1,
      "cost": 4,
      "earth": 2,
      "sea": 0,
      "generic": 2,
      "role": "Presencia de línea",
      "force": 3,
      "defense": 5,
      "line": "Batalla",
      "effect": "Cuando sea destruida, roba 1 carta y luego descarta 1 carta.",
      "icons": "[DESTRUIDA] ≡1",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "ROM-045",
      "name": "Quinto Fabio Máximo",
      "type": "Leyenda",
      "copies": 1,
      "cost": 1,
      "earth": 1,
      "sea": 0,
      "generic": 0,
      "role": "Mejora única acoplada",
      "force": null,
      "defense": null,
      "line": "Acoplada",
      "effect": "La unidad acoplada obtiene +2 Defensa. Después de defender, restaura 1 daño de esa unidad.",
      "icons": "[ACOPLA:T-I] 🛡+2 | [AL DEFENDER] ♻1",
      "domain": "Terrestre",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "ROM-047",
      "name": "Cayo Lelio",
      "type": "Leyenda",
      "copies": 1,
      "cost": 3,
      "earth": 2,
      "sea": 0,
      "generic": 1,
      "role": "Mejora única acoplada",
      "force": null,
      "defense": null,
      "line": "Acoplada",
      "effect": "La unidad acoplada obtiene Precisión y Maniobra.",
      "icons": "[ACOPLA:T-II/N-I/N-II] ◎ | ⇄",
      "domain": "Mixto",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "ROM-053",
      "name": "Castra Romana",
      "type": "Fortificación",
      "copies": 2,
      "cost": 3,
      "earth": 2,
      "sea": 0,
      "generic": 1,
      "role": "Defensa persistente de Apoyo",
      "force": 0,
      "defense": 5,
      "line": "Solo Apoyo",
      "effect": "La primera vez en una ofensiva que bloquee, obtiene +1 Defensa hasta terminar esa ofensiva.",
      "icons": "[BLOQUEA] 🛡+1 hasta fin ofensiva",
      "domain": "Terrestre",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false,
      "wall": true
    },
    {
      "code": "ROM-055",
      "name": "Torre de Vigilancia Republicana",
      "type": "Fortificación",
      "copies": 1,
      "cost": 5,
      "earth": 2,
      "sea": 0,
      "generic": 3,
      "role": "Defensa persistente de Apoyo",
      "force": 3,
      "defense": 7,
      "line": "Solo Apoyo",
      "effect": "Las unidades T-I en Apoyo junto a esta Fortificación obtienen +1 Defensa.",
      "icons": "[PROTEGE T-I] 🛡+1",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false,
      "wall": false
    },
    {
      "code": "ROM-058",
      "name": "Cabeza de Puente del Ebro",
      "type": "Fortificación",
      "copies": 1,
      "cost": 4,
      "earth": 2,
      "sea": 0,
      "generic": 2,
      "role": "Ataque desde Apoyo",
      "force": 2,
      "defense": 5,
      "line": "Solo Apoyo",
      "effect": "Puede atacar desde Apoyo.",
      "icons": "◎ ATAQUE DESDE APOYO",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false,
      "wall": false
    },
    {
      "code": "ROM-059",
      "name": "Campamento de Invierno",
      "type": "Fortificación",
      "copies": 1,
      "cost": 2,
      "earth": 1,
      "sea": 0,
      "generic": 1,
      "role": "Apoyo defensivo",
      "force": 0,
      "defense": 4,
      "line": "Solo Apoyo",
      "effect": "Fortificación de Apoyo; no protege al Comandante.",
      "icons": "APOYO",
      "domain": "Terrestre",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false,
      "wall": false
    },
    {
      "code": "ROM-061",
      "name": "Triple Línea Manipular",
      "type": "Orden",
      "copies": 1,
      "cost": 2,
      "earth": 1,
      "sea": 0,
      "generic": 1,
      "role": "Plan táctico",
      "force": null,
      "defense": null,
      "line": "No aplica",
      "effect": "Una unidad propia que pueda atacar obtiene +2 Fuerza hasta finalizar el turno.",
      "icons": "⚔+2 una unidad",
      "orderEffect": "forceTwo",
      "domain": "Sin dominio",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "ROM-062",
      "name": "Avance de los Hastati",
      "type": "Orden",
      "copies": 1,
      "cost": 2,
      "earth": 1,
      "sea": 0,
      "generic": 1,
      "role": "Plan táctico",
      "force": null,
      "defense": null,
      "line": "No aplica",
      "effect": "Restaura hasta 2 puntos de daño de una unidad propia.",
      "icons": "♻2 una unidad",
      "orderEffect": "healTwo",
      "domain": "Sin dominio",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "ROM-065",
      "name": "Disciplina de la Legión",
      "type": "Orden",
      "copies": 1,
      "cost": 2,
      "earth": 1,
      "sea": 0,
      "generic": 1,
      "role": "Plan táctico",
      "force": null,
      "defense": null,
      "line": "No aplica",
      "effect": "Elige una unidad que pueda atacar y lanza 1 dado: 1–2 otorga +1, 3–4 otorga +2 y 5–6 otorga +3 Fuerza en su próximo ataque.",
      "icons": "🎲 ⚔+1/+2/+3",
      "orderEffect": "diceForce",
      "domain": "Sin dominio",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "ROM-067",
      "name": "Estrategia Fabiana",
      "type": "Orden",
      "copies": 1,
      "cost": 2,
      "earth": 1,
      "sea": 0,
      "generic": 1,
      "role": "Plan táctico",
      "force": null,
      "defense": null,
      "line": "No aplica",
      "effect": "Causa 1 punto de daño a una unidad enemiga.",
      "icons": "☄1 daño",
      "orderEffect": "damageOne",
      "domain": "Sin dominio",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "ROM-069",
      "name": "Desembarco en África",
      "type": "Orden",
      "copies": 1,
      "cost": 1,
      "earth": 0,
      "sea": 0,
      "generic": 1,
      "role": "Plan táctico",
      "force": null,
      "defense": null,
      "line": "No aplica",
      "effect": "Roba 1 carta.",
      "icons": "≡1",
      "orderEffect": "drawOne",
      "domain": "Naval",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "ROM-076",
      "name": "Mantener la Línea",
      "type": "Reacción",
      "copies": 2,
      "cost": 2,
      "earth": 1,
      "sea": 0,
      "generic": 1,
      "role": "Respuesta enemiga",
      "force": null,
      "defense": null,
      "line": "No aplica",
      "effect": "Cuando una de tus líneas sea atacada, una carta defensora obtiene +2 Defensa durante esa ofensiva.",
      "icons": "[ATACAN tu línea] 🛡+2",
      "domain": "Sin dominio",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "ROM-078",
      "name": "Cerrar Filas",
      "type": "Reacción",
      "copies": 1,
      "cost": 2,
      "earth": 1,
      "sea": 0,
      "generic": 1,
      "role": "Respuesta enemiga",
      "force": null,
      "defense": null,
      "line": "No aplica",
      "effect": "Cuando una carta romana vaya a recibir daño, reduce ese daño en 2.",
      "icons": "[RECIBE daño] ⤵-2",
      "domain": "Sin dominio",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "ROM-080",
      "name": "Intervención de los Triarii",
      "type": "Reacción",
      "copies": 1,
      "cost": 0,
      "earth": 0,
      "sea": 0,
      "generic": 0,
      "role": "Respuesta enemiga",
      "force": null,
      "defense": null,
      "line": "No aplica",
      "effect": "Después de la declaración completa de atacantes, mueve 1 unidad con Maniobra; queda girada y puede defender.",
      "icons": "[OPONENTE declara] ⇄1",
      "domain": "Sin dominio",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "NEU-019",
      "name": "Terreno Elevado",
      "type": "Orden",
      "copies": 1,
      "cost": 2,
      "earth": 0,
      "sea": 0,
      "generic": 2,
      "role": "Plan táctico",
      "force": null,
      "defense": null,
      "line": "No aplica",
      "effect": "Una línea propia obtiene +2 Defensa repartida entre sus cartas hasta el final del turno.",
      "icons": "🛡+2 una línea",
      "domain": "Sin dominio",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "NEU-026",
      "name": "Cambio de Viento",
      "type": "Reacción",
      "copies": 1,
      "cost": 2,
      "earth": 0,
      "sea": 0,
      "generic": 2,
      "role": "Respuesta enemiga",
      "force": null,
      "defense": null,
      "line": "No aplica",
      "effect": "Cuando se declare un ataque naval, una unidad atacante obtiene -2 Fuerza este turno.",
      "icons": "[ATAQUE naval] ⚔-2",
      "domain": "Sin dominio",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    }
  ],
  "cartago": [
    {
      "code": "CAR-001",
      "name": "Infantería Libiofenicia",
      "type": "Unidad",
      "copies": 2,
      "cost": 2,
      "earth": 1,
      "sea": 0,
      "generic": 1,
      "role": "Presencia de línea",
      "force": 1,
      "defense": 3,
      "line": "Batalla",
      "effect": "Obtiene +1 Fuerza mientras ataca.",
      "icons": "[ATACA] ⚔+1",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "CAR-004",
      "name": "Veteranos de Italia",
      "type": "Unidad",
      "copies": 1,
      "cost": 1,
      "earth": 1,
      "sea": 0,
      "generic": 0,
      "role": "Presencia de línea",
      "force": 1,
      "defense": 2,
      "line": "Batalla",
      "effect": "La primera vez por turno que haga daño, restaura 1 daño propio.",
      "icons": "[DAÑA] ♻1",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "CAR-006",
      "name": "Scutarii Íberos",
      "type": "Unidad",
      "copies": 2,
      "cost": 3,
      "earth": 2,
      "sea": 0,
      "generic": 1,
      "role": "Presencia de línea",
      "force": 2,
      "defense": 4,
      "line": "Batalla",
      "effect": "Obtiene +1 Fuerza mientras ataca.",
      "icons": "[ATACA] ⚔+1",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "CAR-008",
      "name": "Guerreros Celtíberos",
      "type": "Unidad",
      "copies": 2,
      "cost": 1,
      "earth": 1,
      "sea": 0,
      "generic": 0,
      "role": "Presencia de línea",
      "force": 1,
      "defense": 2,
      "line": "Batalla",
      "effect": "Si entra en Apoyo, obtiene Precisión hasta el final del turno; no elimina Preparación.",
      "icons": "[ENTRA APOYO] ◎ este turno",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "CAR-012",
      "name": "Honderos Baleares",
      "type": "Unidad",
      "copies": 2,
      "cost": 1,
      "earth": 1,
      "sea": 0,
      "generic": 0,
      "role": "Presencia de línea",
      "force": 1,
      "defense": 2,
      "line": "Batalla",
      "effect": "Si otra unidad cartaginesa ataca al mismo objetivo, obtiene +1 Fuerza.",
      "icons": "[FLANCO] ⚔+1",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "CAR-014",
      "name": "Caballería Númida",
      "type": "Unidad",
      "copies": 2,
      "cost": 4,
      "earth": 2,
      "sea": 0,
      "generic": 2,
      "role": "Movilidad y ataque",
      "force": 5,
      "defense": 4,
      "line": "Batalla",
      "effect": "La primera vez por turno que haga daño, restaura 1 daño propio.",
      "icons": "[DAÑA] ♻1",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": true
    },
    {
      "code": "CAR-018",
      "name": "Elefantes de Guerra",
      "type": "Unidad",
      "copies": 2,
      "cost": 4,
      "earth": 2,
      "sea": 0,
      "generic": 2,
      "role": "Movilidad y ataque",
      "force": 5,
      "defense": 4,
      "line": "Batalla",
      "effect": "Si entra en Apoyo, obtiene Precisión hasta el final del turno; no elimina Preparación.",
      "icons": "[ENTRA APOYO] ◎ este turno",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": true
    },
    {
      "code": "CAR-021",
      "name": "Exploradores Númidas",
      "type": "Unidad",
      "copies": 2,
      "cost": 3,
      "earth": 2,
      "sea": 0,
      "generic": 1,
      "role": "Movilidad y ataque",
      "force": 4,
      "defense": 3,
      "line": "Batalla",
      "effect": "Obtiene +1 Fuerza mientras ataca.",
      "icons": "[ATACA] ⚔+1",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": true
    },
    {
      "code": "CAR-028",
      "name": "Quinquerreme Cartaginesa",
      "type": "Unidad",
      "copies": 2,
      "cost": 3,
      "earth": 0,
      "sea": 2,
      "generic": 1,
      "role": "Presión desde Apoyo",
      "force": 4,
      "defense": 4,
      "line": "Apoyo",
      "effect": "Si entra en Apoyo, obtiene Precisión hasta el final del turno; no elimina Preparación.",
      "icons": "[ENTRA APOYO] ◎ este turno",
      "domain": "Naval",
      "attacksEarth": true,
      "attacksSea": true,
      "longRange": true,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "CAR-035",
      "name": "Supervivientes de los Alpes",
      "type": "Unidad",
      "copies": 1,
      "cost": 4,
      "earth": 2,
      "sea": 0,
      "generic": 2,
      "role": "Presencia de línea",
      "force": 3,
      "defense": 5,
      "line": "Batalla",
      "effect": "Mientras comparta línea con una unidad cartaginesa de otra clase, obtiene +1 Defensa.",
      "icons": "[ALIADO distinto] 🛡+1",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "CAR-036",
      "name": "Centro Galo de Cannas",
      "type": "Unidad",
      "copies": 1,
      "cost": 1,
      "earth": 1,
      "sea": 0,
      "generic": 0,
      "role": "Presencia de línea",
      "force": 1,
      "defense": 2,
      "line": "Batalla",
      "effect": "Obtiene +1 Fuerza mientras ataca.",
      "icons": "[ATACA] ⚔+1",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "CAR-039",
      "name": "Veteranos de Trebia",
      "type": "Unidad",
      "copies": 1,
      "cost": 4,
      "earth": 2,
      "sea": 0,
      "generic": 2,
      "role": "Presencia de línea",
      "force": 3,
      "defense": 5,
      "line": "Batalla",
      "effect": "La primera vez por turno que haga daño, restaura 1 daño propio.",
      "icons": "[DAÑA] ♻1",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": true,
      "maneuver": false
    },
    {
      "code": "CAR-045",
      "name": "Maharbal",
      "type": "Leyenda",
      "copies": 1,
      "cost": 1,
      "earth": 1,
      "sea": 0,
      "generic": 0,
      "role": "Mejora única acoplada",
      "force": null,
      "defense": null,
      "line": "Acoplada",
      "effect": "La unidad acoplada obtiene +2 Fuerza mientras ataca.",
      "icons": "[ACOPLA:T-II] ⚔+2 [ATACA]",
      "domain": "Terrestre",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "CAR-046",
      "name": "Asdrúbal Barca",
      "type": "Leyenda",
      "copies": 1,
      "cost": 2,
      "earth": 1,
      "sea": 0,
      "generic": 1,
      "role": "Mejora única acoplada",
      "force": null,
      "defense": null,
      "line": "Acoplada",
      "effect": "La unidad acoplada obtiene Maniobra y +1 Fuerza.",
      "icons": "[ACOPLA:T-I/T-II] ⇄ | ⚔+1",
      "domain": "Terrestre",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "CAR-053",
      "name": "Campamento Púnico",
      "type": "Fortificación",
      "copies": 2,
      "cost": 3,
      "earth": 2,
      "sea": 0,
      "generic": 1,
      "role": "Defensa persistente de Apoyo",
      "force": 0,
      "defense": 5,
      "line": "Solo Apoyo",
      "effect": "Durante su único contraataque de la ofensiva obtiene +1 Fuerza.",
      "icons": "[BLOQUEA] ⚔+1 contraataca",
      "domain": "Terrestre",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false,
      "wall": true
    },
    {
      "code": "CAR-054",
      "name": "Empalizada de Sagunto",
      "type": "Fortificación",
      "copies": 1,
      "cost": 2,
      "earth": 1,
      "sea": 0,
      "generic": 1,
      "role": "Apoyo defensivo",
      "force": 0,
      "defense": 4,
      "line": "Solo Apoyo",
      "effect": "Fortificación de Apoyo; no protege al Comandante.",
      "icons": "APOYO",
      "domain": "Terrestre",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false,
      "wall": false
    },
    {
      "code": "CAR-055",
      "name": "Torre de Nueva Cartago",
      "type": "Fortificación",
      "copies": 1,
      "cost": 5,
      "earth": 2,
      "sea": 0,
      "generic": 3,
      "role": "Ataque desde Apoyo",
      "force": 3,
      "defense": 7,
      "line": "Solo Apoyo",
      "effect": "Puede atacar desde Apoyo.",
      "icons": "◎ ATAQUE DESDE APOYO",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false,
      "wall": false
    },
    {
      "code": "CAR-058",
      "name": "Campamento de los Alpes",
      "type": "Fortificación",
      "copies": 1,
      "cost": 4,
      "earth": 2,
      "sea": 0,
      "generic": 2,
      "role": "Ataque desde Apoyo",
      "force": 2,
      "defense": 5,
      "line": "Solo Apoyo",
      "effect": "Puede atacar desde Apoyo.",
      "icons": "◎ ATAQUE DESDE APOYO",
      "domain": "Terrestre",
      "attacksEarth": true,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false,
      "wall": false
    },
    {
      "code": "CAR-061",
      "name": "Cruce de los Alpes",
      "type": "Orden",
      "copies": 1,
      "cost": 2,
      "earth": 1,
      "sea": 0,
      "generic": 1,
      "role": "Plan táctico",
      "force": null,
      "defense": null,
      "line": "No aplica",
      "effect": "Restaura hasta 2 puntos de daño de una unidad propia.",
      "icons": "♻2 una unidad",
      "orderEffect": "healTwo",
      "domain": "Sin dominio",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "CAR-062",
      "name": "Doble Envolvimiento",
      "type": "Orden",
      "copies": 1,
      "cost": 2,
      "earth": 1,
      "sea": 0,
      "generic": 1,
      "role": "Plan táctico",
      "force": null,
      "defense": null,
      "line": "No aplica",
      "effect": "Una unidad propia que pueda atacar obtiene +2 Fuerza hasta finalizar el turno.",
      "icons": "⚔+2 una unidad",
      "orderEffect": "forceTwo",
      "domain": "Sin dominio",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "CAR-065",
      "name": "Carga de Elefantes",
      "type": "Orden",
      "copies": 1,
      "cost": 2,
      "earth": 1,
      "sea": 0,
      "generic": 1,
      "role": "Plan táctico",
      "force": null,
      "defense": null,
      "line": "No aplica",
      "effect": "Elige una unidad que pueda atacar y lanza 1 dado: 1–2 otorga +1, 3–4 otorga +2 y 5–6 otorga +3 Fuerza en su próximo ataque.",
      "icons": "🎲 ⚔+1/+2/+3",
      "orderEffect": "diceForce",
      "domain": "Sin dominio",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "CAR-066",
      "name": "Hostigamiento Númida",
      "type": "Orden",
      "copies": 1,
      "cost": 2,
      "earth": 1,
      "sea": 0,
      "generic": 1,
      "role": "Plan táctico",
      "force": null,
      "defense": null,
      "line": "No aplica",
      "effect": "Causa 1 punto de daño a una unidad enemiga.",
      "icons": "☄1 daño",
      "orderEffect": "damageOne",
      "domain": "Sin dominio",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "CAR-069",
      "name": "Reclutar Mercenarios",
      "type": "Orden",
      "copies": 1,
      "cost": 1,
      "earth": 0,
      "sea": 0,
      "generic": 1,
      "role": "Plan táctico",
      "force": null,
      "defense": null,
      "line": "No aplica",
      "effect": "Roba 1 carta.",
      "icons": "≡1",
      "orderEffect": "drawOne",
      "domain": "Sin dominio",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "CAR-076",
      "name": "Fingir Retirada",
      "type": "Reacción",
      "copies": 2,
      "cost": 2,
      "earth": 1,
      "sea": 0,
      "generic": 1,
      "role": "Respuesta enemiga",
      "force": null,
      "defense": null,
      "line": "No aplica",
      "effect": "Cuando una unidad cartaginesa sea bloqueada, devuélvela a tu mano antes del daño.",
      "icons": "[BLOQUEADA] ↶ propia",
      "domain": "Sin dominio",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "CAR-077",
      "name": "Carga por el Flanco",
      "type": "Reacción",
      "copies": 1,
      "cost": 1,
      "earth": 1,
      "sea": 0,
      "generic": 0,
      "role": "Respuesta enemiga",
      "force": null,
      "defense": null,
      "line": "No aplica",
      "effect": "Cuando dos unidades tuyas ataquen al mismo objetivo, una obtiene +2 Fuerza este turno.",
      "icons": "[DOS mismo objetivo] ⚔+2 una",
      "domain": "Sin dominio",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "CAR-079",
      "name": "Cerrar la Trampa",
      "type": "Reacción",
      "copies": 1,
      "cost": 1,
      "earth": 1,
      "sea": 0,
      "generic": 0,
      "role": "Respuesta enemiga",
      "force": null,
      "defense": null,
      "line": "No aplica",
      "effect": "Cuando una unidad cartaginesa sea destruida, el oponente descarta 1 carta al azar.",
      "icons": "[DESTRUIDA] oponente ↘1",
      "domain": "Sin dominio",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "NEU-019",
      "name": "Terreno Elevado",
      "type": "Orden",
      "copies": 1,
      "cost": 2,
      "earth": 0,
      "sea": 0,
      "generic": 2,
      "role": "Plan táctico",
      "force": null,
      "defense": null,
      "line": "No aplica",
      "effect": "Una línea propia obtiene +2 Defensa repartida entre sus cartas hasta el final del turno.",
      "icons": "🛡+2 una línea",
      "domain": "Sin dominio",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    },
    {
      "code": "NEU-028",
      "name": "Emboscada Local",
      "type": "Reacción",
      "copies": 1,
      "cost": 2,
      "earth": 0,
      "sea": 0,
      "generic": 2,
      "role": "Respuesta enemiga",
      "force": null,
      "defense": null,
      "line": "No aplica",
      "effect": "Cuando ataquen tu línea de Apoyo, una carta defensora obtiene +2 Defensa durante la ofensiva.",
      "icons": "[ATACAN apoyo] 🛡+2",
      "domain": "Sin dominio",
      "attacksEarth": false,
      "attacksSea": false,
      "longRange": false,
      "precision": false,
      "maneuver": false
    }
  ]
}''';

Map<String, int> debugDeckComposition(Faction faction) {
  final raw = jsonDecode(_deckJson) as Map<String, dynamic>;
  final key = faction == Faction.rome ? 'roma' : 'cartago';
  final result = <String, int>{};
  for (final item in raw[key] as List<dynamic>) {
    final card = CardDefinition.fromJson(item as Map<String, dynamic>);
    final included =
        card.type == 'Unidad' ||
        card.type == 'Fortificación' ||
        (card.type == 'Orden' && card.orderEffect != OrderEffect.none);
    if (!included) continue;
    result.update(
      card.type,
      (value) => value + card.copies,
      ifAbsent: () => card.copies,
    );
  }
  return result;
}

int debugWallCount(Faction faction) {
  final raw = jsonDecode(_deckJson) as Map<String, dynamic>;
  final key = faction == Faction.rome ? 'roma' : 'cartago';
  var total = 0;
  for (final item in raw[key] as List<dynamic>) {
    final card = CardDefinition.fromJson(item as Map<String, dynamic>);
    if (card.wall) total += card.copies;
  }
  return total;
}
