#if defined(_WIN32)
#include <BaseTsd.h>
typedef SSIZE_T ssize_t;
#define PIKAFISH_FFI_EXPORT __declspec(dllexport)
#else
#include <sys/types.h>
#define PIKAFISH_FFI_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" PIKAFISH_FFI_EXPORT
#endif
int
pikafish_init();

#ifdef __cplusplus
extern "C" PIKAFISH_FFI_EXPORT
#endif
int
pikafish_main();

#ifdef __cplusplus
extern "C" PIKAFISH_FFI_EXPORT
#endif
int
pikafish_start_threaded();

#ifdef __cplusplus
extern "C" PIKAFISH_FFI_EXPORT
#endif
ssize_t
pikafish_stdin_write(char *data);

#ifdef __cplusplus
extern "C" PIKAFISH_FFI_EXPORT
#endif
char *
pikafish_stdout_read();

#ifdef __cplusplus
extern "C" PIKAFISH_FFI_EXPORT
#endif
char *
pikafish_stdout_try_read();

#ifdef __cplusplus
extern "C" PIKAFISH_FFI_EXPORT
#endif
int
pikafish_is_running();

#ifdef __cplusplus
extern "C" PIKAFISH_FFI_EXPORT
#endif
int
pikafish_exit_code();

#ifdef __cplusplus
extern "C" PIKAFISH_FFI_EXPORT
#endif
void
pikafish_join_threaded();

#ifdef __cplusplus
extern "C" PIKAFISH_FFI_EXPORT
#endif
void
pikafish_shutdown();
