#include <cerrno>
#include <sys/types.h>

extern "C" __attribute__((visibility("default"))) __attribute__((used))
int pikafish_init()
{
    return ENOTSUP;
}

extern "C" __attribute__((visibility("default"))) __attribute__((used))
int pikafish_main()
{
    return ENOTSUP;
}

extern "C" __attribute__((visibility("default"))) __attribute__((used))
ssize_t pikafish_stdin_write(char *)
{
    return -1;
}

extern "C" __attribute__((visibility("default"))) __attribute__((used))
char *pikafish_stdout_read()
{
    return nullptr;
}

extern "C" __attribute__((visibility("default"))) __attribute__((used))
void pikafish_shutdown()
{
}
