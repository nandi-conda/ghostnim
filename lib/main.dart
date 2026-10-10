import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/config.dart';
import 'src/options.dart';
import 'src/update.dart';

Future<void> main(List<String> args) async {
  final cli = parseCli(args);
  final opts = mergeOptions(loadConfig(cli.configPath), cli);
  startUpdateCheck();
  WidgetsFlutterBinding.ensureInitialized();
  final defaultConfig = await rootBundle.loadString('docs/config.kdl');
  runApp(GhostnimApp(cli: cli, opts: opts, defaultConfigText: defaultConfig));
}
