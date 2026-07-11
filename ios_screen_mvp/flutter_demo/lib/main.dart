import 'package:flutter/material.dart';

import 'mvp_runtime_control.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerMvpRuntimeControl();
  runApp(const MvpDemoApp());
}

class MvpDemoApp extends StatelessWidget {
  const MvpDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const GestureDemoPage(),
    );
  }
}

class GestureDemoPage extends StatefulWidget {
  const GestureDemoPage({super.key});

  @override
  State<GestureDemoPage> createState() => _GestureDemoPageState();
}

class _GestureDemoPageState extends State<GestureDemoPage> {
  int _clicks = 0;
  int _longPresses = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('iOS Screen MVP')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FilledButton.icon(
            onPressed: () => setState(() => _clicks++),
            icon: const Icon(Icons.touch_app),
            label: Text('Clicks: $_clicks'),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onLongPress: () => setState(() => _longPresses++),
            child: Container(
              height: 140,
              alignment: Alignment.center,
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Text('Hold here\nLong presses: $_longPresses'),
            ),
          ),
          const SizedBox(height: 20),
          for (var index = 1; index <= 30; index++)
            ListTile(
              leading: CircleAvatar(child: Text('$index')),
              title: Text('Scrollable item $index'),
            ),
        ],
      ),
    );
  }
}
