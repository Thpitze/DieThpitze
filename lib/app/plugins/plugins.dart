import 'ui_plugin.dart';
import 'records_lite/records_lite_plugin.dart';

List<UiPlugin> buildPlugins() {
  return [
    const RecordsLitePlugin(),
  ];
}
