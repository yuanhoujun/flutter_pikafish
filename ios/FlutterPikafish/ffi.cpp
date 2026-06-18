#include <condition_variable>
#include <cstring>
#include <deque>
#include <iostream>
#include <mutex>
#include <streambuf>
#include <string>

#include "../Pikafish/src/bitboard.h"
#include "../Pikafish/src/position.h"
#include "../Pikafish/src/search.h"
#include "../Pikafish/src/thread.h"
#include "../Pikafish/src/tt.h"
#include "../Pikafish/src/uci.h"

#include "ffi.h"

int main(int, char **);

namespace
{
const char *Bye = "bye\n";
char readBuffer[4096];

std::mutex inputMutex;
std::condition_variable inputCondition;
std::deque<char> inputQueue;

std::mutex outputMutex;
std::condition_variable outputCondition;
std::deque<char> outputQueue;

bool shutdownRequested = false;

class InputBuffer : public std::streambuf
{
public:
    int underflow() override
    {
        std::unique_lock<std::mutex> lock(inputMutex);
        inputCondition.wait(lock, [] {
            return shutdownRequested || !inputQueue.empty();
        });

        if (inputQueue.empty())
        {
            return traits_type::eof();
        }

        current = inputQueue.front();
        inputQueue.pop_front();
        setg(&current, &current, &current + 1);
        return traits_type::to_int_type(current);
    }

private:
    char current = 0;
};

class OutputBuffer : public std::streambuf
{
public:
    int overflow(int ch) override
    {
        if (ch == traits_type::eof())
        {
            return traits_type::not_eof(ch);
        }

        {
            std::lock_guard<std::mutex> lock(outputMutex);
            outputQueue.push_back(static_cast<char>(ch));
        }
        outputCondition.notify_one();
        return ch;
    }

    std::streamsize xsputn(const char *s, std::streamsize n) override
    {
        {
            std::lock_guard<std::mutex> lock(outputMutex);
            for (std::streamsize i = 0; i < n; ++i)
            {
                outputQueue.push_back(s[i]);
            }
        }
        outputCondition.notify_one();
        return n;
    }

    int sync() override
    {
        outputCondition.notify_one();
        return 0;
    }
};

InputBuffer inputBuffer;
OutputBuffer outputBuffer;
std::streambuf *originalCin = nullptr;
std::streambuf *originalCout = nullptr;

void clearQueues()
{
    {
        std::lock_guard<std::mutex> lock(inputMutex);
        inputQueue.clear();
    }
    {
        std::lock_guard<std::mutex> lock(outputMutex);
        outputQueue.clear();
    }
}

void pushOutput(const char *data)
{
    if (data == nullptr)
    {
        return;
    }

    {
        std::lock_guard<std::mutex> lock(outputMutex);
        for (const char *cursor = data; *cursor != '\0'; ++cursor)
        {
            outputQueue.push_back(*cursor);
        }
    }
    outputCondition.notify_one();
}
} // namespace

int pikafish_init()
{
    shutdownRequested = false;
    clearQueues();
    return 0;
}

int pikafish_main()
{
    originalCin = std::cin.rdbuf(&inputBuffer);
    originalCout = std::cout.rdbuf(&outputBuffer);

    int argc = 1;
    char arg0[] = "";
    char *argv[] = {arg0, NULL};
    int exitCode = main(argc, argv);

    if (originalCin != nullptr)
    {
        std::cin.rdbuf(originalCin);
        originalCin = nullptr;
    }
    if (originalCout != nullptr)
    {
        std::cout.rdbuf(originalCout);
        originalCout = nullptr;
    }

    pushOutput(Bye);
    return exitCode;
}

ssize_t pikafish_stdin_write(char *data)
{
    if (data == NULL)
    {
        return -1;
    }

    const size_t length = strlen(data);
    {
        std::lock_guard<std::mutex> lock(inputMutex);
        for (size_t i = 0; i < length; ++i)
        {
            inputQueue.push_back(data[i]);
        }
    }
    inputCondition.notify_one();
    return static_cast<ssize_t>(length);
}

char *pikafish_stdout_read()
{
    std::unique_lock<std::mutex> lock(outputMutex);
    outputCondition.wait(lock, [] {
        return shutdownRequested || !outputQueue.empty();
    });

    if (outputQueue.empty())
    {
        return NULL;
    }

    size_t count = 0;
    while (count < sizeof(readBuffer) - 1 && !outputQueue.empty())
    {
        readBuffer[count++] = outputQueue.front();
        outputQueue.pop_front();
    }
    readBuffer[count] = 0;

    if (strcmp(readBuffer, Bye) == 0)
    {
        return NULL;
    }

    return readBuffer;
}

void pikafish_shutdown()
{
    shutdownRequested = true;
    inputCondition.notify_all();
    outputCondition.notify_all();
}
