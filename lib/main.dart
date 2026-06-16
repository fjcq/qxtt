import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

/// 应用入口
void main()
{
    WidgetsFlutterBinding.ensureInitialized();

    runApp(
        const ProviderScope(
            child: App(),
        ),
    );
}
