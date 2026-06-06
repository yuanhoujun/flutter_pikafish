package cn.chessroad.pikafish_engine;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.util.Locale;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Runs the official Pikafish Android executable as a child process. */
public class PikafishEnginePlugin
    implements FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
  private static final String METHOD_CHANNEL = "cn.chessroad.pikafish_engine/methods";
  private static final String EVENT_CHANNEL = "cn.chessroad.pikafish_engine/stdout";
  private static final String ARMV8_BINARY = "libpikafish_armv8_exec.so";
  private static final String DOTPROD_BINARY = "libpikafish_dotprod_exec.so";
  private static final String TAG = "PikafishEngine";

  private Context context;
  private MethodChannel methodChannel;
  private EventChannel eventChannel;
  private EventChannel.EventSink eventSink;
  private Process process;
  private BufferedWriter processInput;
  private Thread outputThread;
  private final Handler mainHandler = new Handler(Looper.getMainLooper());

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    context = binding.getApplicationContext();
    methodChannel = new MethodChannel(binding.getBinaryMessenger(), METHOD_CHANNEL);
    methodChannel.setMethodCallHandler(this);
    eventChannel = new EventChannel(binding.getBinaryMessenger(), EVENT_CHANNEL);
    eventChannel.setStreamHandler(this);
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    disposeProcess();
    methodChannel.setMethodCallHandler(null);
    eventChannel.setStreamHandler(null);
    methodChannel = null;
    eventChannel = null;
    context = null;
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
    switch (call.method) {
      case "start":
        start(call.argument("mode"), result);
        break;
      case "write":
        write(call.argument("line"), result);
        break;
      case "dispose":
        disposeProcess();
        result.success(null);
        break;
      default:
        result.notImplemented();
    }
  }

  @Override
  public void onListen(Object arguments, EventChannel.EventSink events) {
    eventSink = events;
  }

  @Override
  public void onCancel(Object arguments) {
    eventSink = null;
  }

  private synchronized void start(String mode, MethodChannel.Result result) {
    if (process != null && process.isAlive()) {
      result.error("already_running", "Pikafish is already running", null);
      return;
    }

    String binaryName;
    if ("officialArmv8".equals(mode)) {
      binaryName = ARMV8_BINARY;
    } else if ("officialDotProd".equals(mode)) {
      if (!supportsDotProd()) {
        result.error("unsupported_cpu", "This device does not support ARM DotProd", null);
        return;
      }
      binaryName = DOTPROD_BINARY;
    } else {
      binaryName = supportsDotProd() ? DOTPROD_BINARY : ARMV8_BINARY;
    }

    String engineVariant = DOTPROD_BINARY.equals(binaryName) ? "DotProd" : "ARMv8";
    String selectionMessage = "Using official Pikafish " + engineVariant + " engine";
    Log.i(TAG, selectionMessage);

    File binary = new File(context.getApplicationInfo().nativeLibraryDir, binaryName);
    if (!binary.canExecute()) {
      result.error("not_executable", "Bundled engine is not executable: " + binary, null);
      return;
    }

    try {
      ProcessBuilder builder = new ProcessBuilder(binary.getAbsolutePath());
      builder.redirectErrorStream(true);
      process = builder.start();
      processInput = new BufferedWriter(new OutputStreamWriter(process.getOutputStream()));
      startOutputThread(process);
      EventChannel.EventSink sink = eventSink;
      if (sink != null) {
        sink.success("[pikafish] " + selectionMessage);
      }
      result.success(true);
    } catch (IOException error) {
      disposeProcess();
      result.error("start_failed", error.getMessage(), null);
    }
  }

  private synchronized void write(String line, MethodChannel.Result result) {
    if (process == null || !process.isAlive() || processInput == null) {
      result.error("not_running", "Pikafish is not running", null);
      return;
    }

    try {
      processInput.write(line);
      processInput.newLine();
      processInput.flush();
      result.success(null);
    } catch (IOException error) {
      result.error("write_failed", error.getMessage(), null);
    }
  }

  private void startOutputThread(Process runningProcess) {
    outputThread = new Thread(() -> {
      try (BufferedReader reader =
          new BufferedReader(new InputStreamReader(runningProcess.getInputStream()))) {
        String line;
        while ((line = reader.readLine()) != null) {
          String outputLine = line;
          mainHandler.post(() -> sendOutputIfCurrent(runningProcess, outputLine));
        }
        runningProcess.waitFor();
      } catch (IOException | InterruptedException error) {
        Thread.currentThread().interrupt();
        mainHandler.post(() -> sendErrorIfCurrent(runningProcess, error));
      } finally {
        mainHandler.post(() -> endOutputIfCurrent(runningProcess));
      }
    }, "pikafish-output");
    outputThread.start();
  }

  private synchronized void sendOutputIfCurrent(Process runningProcess, String line) {
    if (process == runningProcess && eventSink != null) {
      eventSink.success(line);
    }
  }

  private synchronized void sendErrorIfCurrent(Process runningProcess, Exception error) {
    if (process == runningProcess && eventSink != null) {
      eventSink.error("output_failed", error.getMessage(), null);
    }
  }

  private synchronized void endOutputIfCurrent(Process runningProcess) {
    if (process == runningProcess && eventSink != null) {
      eventSink.endOfStream();
    }
  }

  private synchronized void disposeProcess() {
    if (processInput != null) {
      try {
        processInput.close();
      } catch (IOException ignored) {
        // Process shutdown continues.
      }
      processInput = null;
    }
    if (process != null) {
      process.destroy();
      process = null;
    }
    if (outputThread != null) {
      outputThread.interrupt();
      outputThread = null;
    }
  }

  private boolean supportsDotProd() {
    try {
      Process cpuInfo = new ProcessBuilder("sh", "-c", "grep -m1 Features /proc/cpuinfo").start();
      try (BufferedReader reader = new BufferedReader(new InputStreamReader(cpuInfo.getInputStream()))) {
        String features = reader.readLine();
        return features != null
            && features.toLowerCase(Locale.US).contains("asimddp");
      }
    } catch (IOException ignored) {
      return false;
    }
  }
}
