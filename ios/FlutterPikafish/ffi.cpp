#include <condition_variable>
#include <chrono>
#include <cstring>
#include <deque>
#include <iostream>
#include <memory>
#include <mutex>
#include <streambuf>
#include <string>
#include <thread>
#include <utility>

#include "../Pikafish/src/attacks.h"
#include "../Pikafish/src/misc.h"
#include "../Pikafish/src/position.h"
#include "../Pikafish/src/search.h"
#include "../Pikafish/src/thread.h"
#include "../Pikafish/src/tt.h"
#include "../Pikafish/src/tune.h"
#include "../Pikafish/src/uci.h"

#include "ffi.h"

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
bool engineRunning = false;
int engineExitCode = 0;

std::mutex engineThreadMutex;
std::condition_variable engineThreadCondition;

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
    void setLuOutput(bool enabled)
    {
        std::lock_guard<std::mutex> lock(outputMutex);
        luOutput = enabled;
    }

    void reset()
    {
        std::lock_guard<std::mutex> lock(outputMutex);
        luOutput = true;
        pending.clear();
        outputQueue.clear();
    }

    int overflow(int ch) override
    {
        if (ch == traits_type::eof())
        {
            return traits_type::not_eof(ch);
        }

        const char byte = static_cast<char>(ch);
        xsputn(&byte, 1);
        return ch;
    }

    std::streamsize xsputn(const char *s, std::streamsize n) override
    {
        {
            std::lock_guard<std::mutex> lock(outputMutex);
            if (luOutput && pending.empty())
            {
                outputQueue.insert(outputQueue.end(), s, s + n);
            }
            else
            {
                appendFilteredLines(s, n);
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

private:
    // UCI records may span several stream writes. Publish each complete
    // record when bounds are disabled; retain any unfinished line until then.
    void appendFilteredLines(const char *s, std::streamsize n)
    {
        const char *end = s + n;
        while (s < end)
        {
            const auto *newline = static_cast<const char *>(std::memchr(s, '\n', end - s));
            if (!newline)
            {
                pending.append(s, end - s);
                return;
            }
            pending.append(s, newline + 1 - s);
            if (luOutput || pending.compare(0, 11, "info depth ") != 0 ||
                (pending.find(" upperbound ") == std::string::npos &&
                 pending.find(" lowerbound ") == std::string::npos))
            {
                outputQueue.insert(outputQueue.end(), pending.begin(), pending.end());
            }
            pending.clear();
            s = newline + 1;
        }
    }

    bool luOutput = true;
    std::string pending;
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
    outputBuffer.reset();
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

char *readOutputLocked()
{
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

int runPikafishEngine()
{
    using namespace Stockfish;

    std::cout << engine_info() << std::endl;

    Attacks::init();
    Position::init();

    int argc = 1;
    char arg0[] = "";
    char *argv[] = {arg0, NULL};
    auto cli = CommandLine(argc, argv);
    auto uci = std::make_unique<UCIEngine>(std::move(cli));

    // This official engine release lacks the Android binary's LU_Output option.
    // Use its native option parser and keep the setting confined to UCI output.
    uci->engine_options().add("LU_Output", Option(true, [](const Option& value) {
        outputBuffer.setLuOutput(static_cast<int>(value) != 0);
        return std::nullopt;
    }));
    Tune::init(uci->engine_options());

    uci->loop();

    return 0;
}
} // namespace

int pikafish_init()
{
    shutdownRequested = false;
    engineExitCode = 0;
    clearQueues();
    return 0;
}

int pikafish_main()
{
    originalCin = std::cin.rdbuf(&inputBuffer);
    originalCout = std::cout.rdbuf(&outputBuffer);

    int exitCode = runPikafishEngine();

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

int pikafish_start_threaded()
{
    std::lock_guard<std::mutex> lock(engineThreadMutex);

    if (engineRunning)
    {
        return -1;
    }

    int initResult = pikafish_init();
    if (initResult != 0)
    {
        return initResult;
    }

    engineRunning = true;
    std::thread engineThread([] {
        int exitCode = pikafish_main();
        {
            std::lock_guard<std::mutex> lock(engineThreadMutex);
            engineExitCode = exitCode;
            engineRunning = false;
        }
        engineThreadCondition.notify_all();
    });
    engineThread.detach();

    return 0;
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

    return readOutputLocked();
}

char *pikafish_stdout_try_read()
{
    std::lock_guard<std::mutex> lock(outputMutex);
    return readOutputLocked();
}

int pikafish_is_running()
{
    std::lock_guard<std::mutex> lock(engineThreadMutex);
    return engineRunning ? 1 : 0;
}

int pikafish_exit_code()
{
    std::lock_guard<std::mutex> lock(engineThreadMutex);
    return engineExitCode;
}

void pikafish_join_threaded()
{
    std::unique_lock<std::mutex> lock(engineThreadMutex);
    engineThreadCondition.wait_for(lock, std::chrono::seconds(2), [] {
        return !engineRunning;
    });
}

void pikafish_shutdown()
{
    shutdownRequested = true;
    inputCondition.notify_all();
    outputCondition.notify_all();
}
