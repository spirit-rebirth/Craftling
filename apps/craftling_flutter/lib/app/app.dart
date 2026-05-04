import 'package:flutter/material.dart';

import '../features/workspace/presentation/pages/task_workspace_page.dart';
import 'theme.dart';

class CraftlingApp extends StatelessWidget {
  const CraftlingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildCraftlingTheme(),
      home: const TaskWorkspacePage(),
    );
  }
}
