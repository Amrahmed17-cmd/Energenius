import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:energenius/screens/home_screen.dart';
import 'package:energenius/screens/devices_screen.dart';
import 'package:energenius/screens/history_screen.dart';
import 'package:energenius/screens/settings_screen.dart';
import 'package:energenius/localization/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:energenius/localization/language_provider.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  MainScreenState createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  String _currentLanguage = '';

  static final List<Widget> _screens = <Widget>[
    HomeScreen(),
    DevicesScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  // We'll build the titles dynamically based on the current locale
  final List<String> _titleKeys = [
    'nav_home',
    'nav_devices',
    'nav_history',
    'nav_settings',
  ];
  final List<IconData> _icons = [
    Icons.home,
    Icons.devices,
    Icons.history,
    Icons.settings,
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageProvider = Provider.of<LanguageProvider>(context);
    if (_currentLanguage != languageProvider.locale.languageCode) {
      _currentLanguage = languageProvider.locale.languageCode;
      // Force rebuild when language changes
      setState(() {});
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Get translated titles
    List<String> translatedTitles =
        _titleKeys.map((key) => key.tr(context)).toList();

    return Scaffold(
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: _screens[_selectedIndex],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CustomNavigationBar(
              selectedIndex: _selectedIndex,
              onItemTapped: _onItemTapped,
              titles: translatedTitles,
              icons: _icons,
            ),
          ),
        ],
      ),
    );
  }
}

class CustomNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemTapped;
  final List<String> titles;
  final List<IconData> icons;

  const CustomNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
    required this.titles,
    required this.icons,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(30),
        color: Colors.black.withAlpha(217),
        child: Container(
          height: 70,
          width: screenWidth,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.blueAccent.withAlpha(77)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(titles.length, (index) {
              return Expanded(child: _buildNavItem(context, index));
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, int index) {
    final bool isSelected = selectedIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onItemTapped(index),
      child: Container(
        alignment: Alignment.center,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: EdgeInsets.symmetric(
            horizontal: isSelected ? 4.0 : 0.0,
            vertical: 4.0,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 200),
                scale: isSelected ? 1.2 : 1.0,
                child: Icon(
                  icons[index],
                  size: 26,
                  color: isSelected ? Colors.blueAccent : Colors.white70,
                ),
              ),
              if (isSelected)
                Flexible(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Padding(
                        padding: const EdgeInsets.only(left: 4.0),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            titles[index],
                            maxLines: 1,
                            style: GoogleFonts.poppins(
                              color: Colors.blueAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
