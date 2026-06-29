#import "PikafishEnginePlugin.h"
#import "ffi.h"

@implementation PikafishEnginePlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    if (registrar == NULL) {
        // Avoid dead code stripping.
        pikafish_init();
        pikafish_main();
        pikafish_start_threaded();
        pikafish_stdin_write(NULL);
        pikafish_stdout_read();
        pikafish_stdout_try_read();
        pikafish_is_running();
        pikafish_exit_code();
        pikafish_join_threaded();
    }
}

@end
