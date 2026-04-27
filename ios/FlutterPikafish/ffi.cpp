#include <cerrno>
#include <cstring>
#include <iostream>
#include <stdio.h>
#include <unistd.h>

#include "../Pikafish/src/bitboard.h"
#include "../Pikafish/src/position.h"
#include "../Pikafish/src/search.h"
#include "../Pikafish/src/thread.h"
#include "../Pikafish/src/tt.h"
#include "../Pikafish/src/uci.h"

#include "ffi.h"

// https://jineshkj.wordpress.com/2006/12/22/how-to-capture-stdin-stdout-and-stderr-of-child-program/
#define NUM_PIPES 2
#define PARENT_WRITE_PIPE 0
#define PARENT_READ_PIPE 1
#define READ_FD 0
#define WRITE_FD 1
#define PARENT_READ_FD (pipes[PARENT_READ_PIPE][READ_FD])
#define PARENT_WRITE_FD (pipes[PARENT_WRITE_PIPE][WRITE_FD])
#define CHILD_READ_FD (pipes[PARENT_WRITE_PIPE][READ_FD])
#define CHILD_WRITE_FD (pipes[PARENT_READ_PIPE][WRITE_FD])

int main(int, char **);

const char *Bye = "bye\n";
int pipes[NUM_PIPES][2] = {{-1, -1}, {-1, -1}};
char buffer[4096];

void close_fd(int &fd)
{
    if (fd >= 0)
    {
        close(fd);
        fd = -1;
    }
}

void close_pipes()
{
    for (int pipeIndex = 0; pipeIndex < NUM_PIPES; ++pipeIndex)
    {
        close_fd(pipes[pipeIndex][READ_FD]);
        close_fd(pipes[pipeIndex][WRITE_FD]);
    }
}

int pikafish_init()
{
    close_pipes();

    if (pipe(pipes[PARENT_READ_PIPE]) != 0)
    {
        close_pipes();
        return errno == 0 ? -1 : errno;
    }

    if (pipe(pipes[PARENT_WRITE_PIPE]) != 0)
    {
        close_pipes();
        return errno == 0 ? -1 : errno;
    }

    return 0;
}

int pikafish_main()
{
    if (CHILD_READ_FD < 0 || CHILD_WRITE_FD < 0)
    {
        return EINVAL;
    }

    if (dup2(CHILD_READ_FD, STDIN_FILENO) < 0 || dup2(CHILD_WRITE_FD, STDOUT_FILENO) < 0)
    {
        return errno == 0 ? -1 : errno;
    }

    int argc = 1;
    char arg0[] = "";
    char *argv[] = {arg0, NULL};
    int exitCode = main(argc, argv);
    
    std::cout << Bye << std::flush;
    
    return exitCode;
}

ssize_t pikafish_stdin_write(char *data)
{
    if (data == NULL || PARENT_WRITE_FD < 0)
    {
        return -1;
    }

    return write(PARENT_WRITE_FD, data, strlen(data));
}

char *pikafish_stdout_read()
{
    if (PARENT_READ_FD < 0)
    {
        return NULL;
    }

    ssize_t count = -1;
    do
    {
        count = read(PARENT_READ_FD, buffer, sizeof(buffer) - 1);
    } while (count < 0 && errno == EINTR);

    if (count < 0)
    {
        return NULL;
    }
    
    buffer[count] = 0;
    if (strcmp(buffer, Bye) == 0)
    {
        return NULL;
    }
    
    return buffer;
}

void pikafish_shutdown()
{
    close_pipes();
}
