// CL V0.8 visual assets
class ChronoAssets {
  const ChronoAssets._();

  static const String root = 'assets/images/v08';

  static const String menu = '$root/menu_v08.png';
  static const String logo = '$root/chrono_logo.png';
  static const String battlefield = '$root/battlefield_v08.png';
  static const String resourceBattleIcons = '$root/icons_resources_battle.png';
  static const String uiIcons = '$root/icons_ui.png';
  static const String scipio = '$root/scipio.png';
  static const String hannibal = '$root/hannibal.png';
  static const String hannibalGold = '$root/hannibal_gold.png';
  static const String cards = '$root/cards';

  static String cardArt(String code) => '$cards/$code.png';
}
