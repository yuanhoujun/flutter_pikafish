import {
  FlutterPlugin,
  FlutterPluginBinding,
} from '@ohos/flutter_ohos';

export default class PikafishEnginePlugin implements FlutterPlugin {
  getUniqueClassName(): string {
    return 'PikafishEnginePlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
  }
}
