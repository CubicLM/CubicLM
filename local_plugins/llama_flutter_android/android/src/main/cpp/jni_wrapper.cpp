#include <jni.h>
#include <string>
#include <vector>
#include <atomic>
#include <ctime>
#include <cstring>
#include <fstream>
#include <mutex>
#include <csignal>
#include <unistd.h>
#include <fcntl.h>
#include <unwind.h>
#include <dlfcn.h>
#include <android/log.h>
#include "llama.cpp/include/llama.h"
#define LOG_TAG "LlamaJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ── Multi-model slot registry ────────────────────────────────────────────────
// Multiple GGUF models can stay resident at once; generation always targets
// the ACTIVE slot. Kotlin picks the slot index and owns residency bookkeeping.
#define MAX_SLOTS 2

struct ModelSlot {
    llama_model* model = nullptr;
    llama_context* ctx = nullptr;
    const llama_vocab* vocab = nullptr;
    llama_sampler* sampler = nullptr;
    int n_past = 0;
};

static ModelSlot g_slots[MAX_SLOTS];
static std::atomic<int> g_active_slot{-1};
static std::atomic<bool> g_stop_flag{false};
static std::mutex g_load_log_mutex;
static std::string g_load_error;
static bool g_capture_load_error = false;
// Prompt-processing batch for the next nativeLoadModel (set from Dart
// via nativeSetBatchSize; default preserves the historic 512).
static int g_batch_size = 512;
// Batch thread count for the parallel prompt pass (same setter channel).
// 1 thread = slowest but smallest transient spike; used on <2.5GB phones.
static int g_batch_threads = -1;

// ── Native crash tombstone (for in-app System Logs, no adb) ─────────
// A segfault/abort inside the engine kills the process with zero Dart
// evidence. This handler writes signal + fault address + raw PCs to a
// file the Dart layer picks up on next boot; PCs are symbolized offline
// against the unstripped libllama_jni.so from the same build.
// SAFETY: only fires for crashes whose PC is inside our own library
// (ART uses SIGSEGV internally for null checks — those chain straight
// through). After writing, chains to the previous handler so the system
// still records the death normally.
static char g_crash_dir[1024] = {0};
static struct sigaction g_old_crash_handlers[5];
static const int g_crash_signals[5] = {SIGSEGV, SIGABRT, SIGFPE, SIGILL, SIGBUS};

static void crash_write_str(int fd, const char* s) {
    size_t n = 0;
    while (s[n] != '\0') n++;
    if (n > 0) (void) write(fd, s, n);
}

static void crash_write_hex(int fd, uintptr_t v) {
    char buf[19];
    buf[0] = '0'; buf[1] = 'x';
    for (int i = 15; i >= 0; i--) {
        int nib = (v >> (i * 4)) & 0xF;
        buf[16 - i] = (char)(nib < 10 ? '0' + nib : 'a' + nib - 10);
    }
    buf[18] = '\n';
    (void) write(fd, buf, 19);
}

static void crash_write_dec(int fd, long long v) {
    char buf[24];
    int len = 0;
    bool neg = false;
    if (v < 0) { neg = true; v = -v; }
    char rev[22];
    int rlen = 0;
    do { rev[rlen++] = (char)('0' + (v % 10)); v /= 10; } while (v > 0 && rlen < 22);
    if (neg && len < 23) buf[len++] = '-';
    while (rlen > 0 && len < 23) buf[len++] = rev[--rlen];
    buf[len++] = '\n';
    (void) write(fd, buf, (size_t) len);
}

struct CrashUnwindState {
    void** pcs;
    int max;
    int count;
};

static _Unwind_Reason_Code crash_unwind_cb(
    struct _Unwind_Context* ctx, void* arg) {
    CrashUnwindState* s = static_cast<CrashUnwindState*>(arg);
    if (s->count >= s->max) return _URC_END_OF_STACK;
    s->pcs[s->count++] = (void*) _Unwind_GetIP(ctx);
    return _URC_NO_REASON;
}

static void crash_handler(int sig, siginfo_t* info, void* /*ctx*/) {
    // Faulting PC tells whether this is OUR crash: ART and other libs
    // must chain through untouched.
    void* pcs[32];
    CrashUnwindState state{pcs, 32, 0};
    _Unwind_Backtrace(crash_unwind_cb, &state);
    int n = state.count;
    bool ours = false;
    // pcs[0..1] are unwind machinery + this handler; the crashing
    // frame is pcs[2] (best effort — symbolization trims as needed).
    for (int f = 2; f < n && !ours; f++) {
        Dl_info dli;
        if (dladdr(pcs[f], &dli) && dli.dli_fname) {
            const char* fn = dli.dli_fname;
            for (size_t k = 0; fn[k] != '\0' && fn[k+1] != '\0' &&
                 fn[k+2] != '\0' && fn[k+3] != '\0' && fn[k+4] != '\0'; k++) {
                if (fn[k] == 'l' && fn[k+1] == 'l' && fn[k+2] == 'a' &&
                    fn[k+3] == 'm' && fn[k+4] == 'a') { ours = true; break; }
            }
        }
    }
    int idx = -1;
    for (int i = 0; i < 5; i++) {
        if (g_crash_signals[i] == sig) { idx = i; break; }
    }
    struct sigaction* old_act = (idx >= 0) ? &g_old_crash_handlers[idx] : nullptr;
    if (ours && g_crash_dir[0] != '\0') {
        char path[1400];
        size_t d = 0;
        while (g_crash_dir[d] != '\0' && d < 1000) { path[d] = g_crash_dir[d]; d++; }
        const char* mid = "/native_crash_";
        size_t m = 0;
        while (mid[m] != '\0') { path[d++] = mid[m++]; }
        // time() is async-signal-safe; digits appended manually.
        long long t = (long long) time(nullptr);
        char rev[22];
        int rlen = 0;
        if (t == 0) rev[rlen++] = '0';
        while (t > 0 && rlen < 22) { rev[rlen++] = (char)('0' + (t % 10)); t /= 10; }
        while (rlen > 0) path[d++] = rev[--rlen];
        path[d++] = '.'; path[d++] = 't'; path[d++] = 'x'; path[d++] = 't';
        path[d] = '\0';
        int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (fd >= 0) {
            crash_write_str(fd, "signal ");
            crash_write_dec(fd, sig);
            crash_write_str(fd, "fault ");
            crash_write_hex(fd, (uintptr_t)(info ? info->si_addr : nullptr));
            crash_write_str(fd, "pcs ");
            crash_write_dec(fd, n);
            for (int i = 0; i < n; i++) crash_write_hex(fd, (uintptr_t)pcs[i]);
            // Module + file offset for the first frames: lets offline
            // symbolization (llvm-symbolizer against the unstripped .so
            // from the same build) name the crashing function exactly.
            crash_write_str(fd, "mods\n");
            int mcount = n < 8 ? n : 8;
            for (int i = 0; i < mcount; i++) {
                Dl_info dli2;
                if (dladdr(pcs[i], &dli2) && dli2.dli_fname && dli2.dli_fbase) {
                    crash_write_str(fd, dli2.dli_fname);
                    crash_write_str(fd, " +");
                    crash_write_hex(fd, (uintptr_t)pcs[i] - (uintptr_t)dli2.dli_fbase);
                }
            }
            close(fd);
        }
    }
    // Chain: previous handler (or default) still owns the death, so the
    // OS records it in ApplicationExitInfo exactly as before.
    if (old_act && (old_act->sa_flags & SA_SIGINFO)) {
        old_act->sa_sigaction(sig, info, nullptr);
    } else if (old_act && old_act->sa_handler != SIG_DFL && old_act->sa_handler != SIG_IGN) {
        old_act->sa_handler(sig);
    } else {
        signal(sig, SIG_DFL);
        raise(sig);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeInstallCrashHandler(
    JNIEnv* env, jobject thiz, jstring crash_dir) {
    const char* dir = env->GetStringUTFChars(crash_dir, nullptr);
    if (dir) {
        size_t n = strlen(dir);
        if (n >= sizeof(g_crash_dir)) n = sizeof(g_crash_dir) - 1;
        memcpy(g_crash_dir, dir, n);
        g_crash_dir[n] = '\0';
        env->ReleaseStringUTFChars(crash_dir, dir);
    }
    struct sigaction act;
    memset(&act, 0, sizeof(act));
    act.sa_sigaction = crash_handler;
    act.sa_flags = SA_SIGINFO | SA_RESTART;
    sigemptyset(&act.sa_mask);
    for (int i = 0; i < 5; i++) {
        sigaction(g_crash_signals[i], &act, &g_old_crash_handlers[i]);
    }
    LOGI("Native crash handler installed (dir=%s)", g_crash_dir);
}

static ModelSlot* activeSlot() {
    const int i = g_active_slot.load(std::memory_order_acquire);
    if (i < 0 || i >= MAX_SLOTS) return nullptr;
    return &g_slots[i];
}

static void freeSlotContents(ModelSlot& s) {
    if (s.sampler) {
        llama_sampler_free(s.sampler);
        s.sampler = nullptr;
    }
    if (s.ctx) {
        llama_free(s.ctx);
        s.ctx = nullptr;
    }
    if (s.model) {
        llama_model_free(s.model);
        s.model = nullptr;
    }
    s.vocab = nullptr;
    s.n_past = 0;
}

static void androidLlamaLog(ggml_log_level level, const char* text, void*) {
    if (!text) return;

    const int priority = level >= GGML_LOG_LEVEL_ERROR
        ? ANDROID_LOG_ERROR
        : level == GGML_LOG_LEVEL_WARN
            ? ANDROID_LOG_WARN
            : level == GGML_LOG_LEVEL_DEBUG
                ? ANDROID_LOG_DEBUG
                : ANDROID_LOG_INFO;
    __android_log_write(priority, LOG_TAG, text);

    std::lock_guard<std::mutex> lock(g_load_log_mutex);
    if (!g_capture_load_error) return;
    if (level == GGML_LOG_LEVEL_ERROR) {
        g_load_error.assign(text);
    } else if (level == GGML_LOG_LEVEL_CONT && !g_load_error.empty()) {
        g_load_error.append(text);
    }
    if (g_load_error.size() > 4096) {
        g_load_error.erase(0, g_load_error.size() - 4096);
    }
}

static std::string consumeLoadError() {
    std::lock_guard<std::mutex> lock(g_load_log_mutex);
    g_capture_load_error = false;
    while (!g_load_error.empty() &&
           (g_load_error.back() == '\n' || g_load_error.back() == '\r')) {
        g_load_error.pop_back();
    }
    return g_load_error;
}

static void throwLoadError(JNIEnv* env, const std::string& message) {
    LOGE("%s", message.c_str());
    jclass exception = env->FindClass("java/lang/RuntimeException");
    env->ThrowNew(exception, message.c_str());
}

// Helper function to validate UTF-8 strings
static bool isValidUTF8(const char* str, size_t len) {
    if (!str) return false;
    
    const unsigned char* bytes = reinterpret_cast<const unsigned char*>(str);
    size_t i = 0;
    
    while (i < len) {
        unsigned char c = bytes[i];
        
        // ASCII character (0xxxxxxx)
        if ((c & 0x80) == 0) {
            i++;
            continue;
        }
        
        // Multi-byte sequence start (110xxxxx, 1110xxxx, or 11110xxx)
        int num_bytes = 0;
        if ((c & 0xE0) == 0xC0) {
            num_bytes = 2; // 110xxxxx
        } else if ((c & 0xF0) == 0xE0) {
            num_bytes = 3; // 1110xxxx
        } else if ((c & 0xF8) == 0xF0) {
            num_bytes = 4; // 11110xxx
        } else {
            // Invalid first byte
            return false;
        }
        
        // Check if we have enough bytes left
        if (i + num_bytes > len) {
            return false;
        }
        
        // Check continuation bytes (10xxxxxx)
        for (int j = 1; j < num_bytes; j++) {
            if ((bytes[i + j] & 0xC0) != 0x80) {
                return false;
            }
        }
        
        // Check for overlong encodings and invalid code points
        if (num_bytes == 2) {
            // Overlong encoding of ASCII character
            if ((c & 0x1E) == 0) return false;
        } else if (num_bytes == 3) {
            // Invalid surrogate halves (U+D800-U+DFFF)
            if (c == 0xED && (bytes[i + 1] & 0x20) == 0x20) return false;
            // Overlong encoding
            if (c == 0xE0 && (bytes[i + 1] & 0x20) == 0) return false;
        } else if (num_bytes == 4) {
            // Out of Unicode range (> U+10FFFF)
            if (c > 0xF4) return false;
            // Overlong encoding
            if (c == 0xF0 && (bytes[i + 1] & 0x30) == 0) return false;
            // Invalid code points (> U+10FFFF)
            if (c == 0xF4 && bytes[i + 1] > 0x8F) return false;
        }
        
        i += num_bytes;
    }
    
    return true;
}

// Helper function to sanitize UTF-8 strings
static std::string sanitizeUTF8(const char* str, size_t len) {
    if (!str || len == 0) return "";
    
    // First try to validate as-is
    if (isValidUTF8(str, len)) {
        return std::string(str, len);
    }
    
    // If invalid, create a sanitized version
    std::string result;
    result.reserve(len);
    
    const unsigned char* bytes = reinterpret_cast<const unsigned char*>(str);
    size_t i = 0;
    
    while (i < len) {
        unsigned char c = bytes[i];
        
        // ASCII character (0xxxxxxx)
        if ((c & 0x80) == 0) {
            result += c;
            i++;
            continue;
        }
        
        // Multi-byte sequence start
        int num_bytes = 0;
        if ((c & 0xE0) == 0xC0) {
            num_bytes = 2;
        } else if ((c & 0xF0) == 0xE0) {
            num_bytes = 3;
        } else if ((c & 0xF8) == 0xF0) {
            num_bytes = 4;
        } else {
            // Invalid first byte, replace with replacement character
            result += "\xEF\xBF\xBD"; // 
            i++;
            continue;
        }
        
        // Check if we have enough bytes left
        if (i + num_bytes > len) {
            result += "\xEF\xBF\xBD"; // 
            break;
        }
        
        // Extract the sequence
        std::string seq(reinterpret_cast<const char*>(bytes + i), num_bytes);
        
        // Validate the sequence
        if (isValidUTF8(seq.c_str(), num_bytes)) {
            result += seq;
        } else {
            // Invalid sequence, replace with replacement character
            result += "\xEF\xBF\xBD"; // 
        }
        
        i += num_bytes;
    }
    
    return result;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeDetectGpu(
        JNIEnv* env, jobject /* this */, jlongArray outStats) {

    // Zero out output array as safe default (-1 = unknown)
    jlong defaults[2] = {-1L, -1L};
    env->SetLongArrayRegion(outStats, 0, 2, defaults);

    // Vulkan GPU detection is disabled on Android to avoid driver crashes
    // on older devices (e.g., Adreno 630). llama.cpp inference already runs
    // on CPU (GGML_VULKAN=OFF), so GPU layers are not used anyway.
    LOGI("nativeDetectGpu: skipped — CPU-only mode on Android");
    return nullptr;
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeLoadModel(
    JNIEnv* env, jobject thiz,
    jstring path, jlong n_threads, jlong ctx_size, jlong n_gpu_layers,
    jint slot, jobject progress_callback) {

    if (slot < 0 || slot >= MAX_SLOTS) {
        throwLoadError(env, "Invalid model slot");
        return;
    }
    if (!path) {
        throwLoadError(env, "GGUF model path is missing");
        return;
    }

    const char* model_path = env->GetStringUTFChars(path, nullptr);
    if (!model_path) {
        throwLoadError(env, "Could not read the GGUF model path");
        return;
    }
    LOGI("Loading model into slot %d: %s", slot, model_path);

    std::ifstream model_file(model_path, std::ios::binary | std::ios::ate);
    if (!model_file) {
        env->ReleaseStringUTFChars(path, model_path);
        throwLoadError(env, "GGUF model file is missing or unreadable");
        return;
    }
    const std::streamsize model_size = model_file.tellg();
    if (model_size < 4) {
        env->ReleaseStringUTFChars(path, model_path);
        throwLoadError(env, "GGUF model file is empty or incomplete");
        return;
    }
    model_file.seekg(0, std::ios::beg);
    char magic[4] = {};
    model_file.read(magic, sizeof(magic));
    if (!model_file || std::memcmp(magic, "GGUF", sizeof(magic)) != 0) {
        env->ReleaseStringUTFChars(path, model_path);
        throwLoadError(env, "Invalid GGUF model header");
        return;
    }
    model_file.close();

    // Model parameters
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = n_gpu_layers;

    llama_log_set(androidLlamaLog, nullptr);
    {
        std::lock_guard<std::mutex> lock(g_load_log_mutex);
        g_load_error.clear();
        g_capture_load_error = true;
    }

    // Loading overwrites the whole target slot; other slots stay resident.
    ModelSlot& target = g_slots[slot];
    freeSlotContents(target);

    // Load model
    target.model = llama_model_load_from_file(model_path, model_params);
    env->ReleaseStringUTFChars(path, model_path);

    if (!target.model) {
        const std::string detail = consumeLoadError();
        const std::string message = detail.empty()
            ? "Failed to load GGUF model; check model compatibility and available RAM"
            : "Failed to load GGUF model: " + detail;
        throwLoadError(env, message);
        return;
    }
    consumeLoadError();

    // Context parameters with memory optimizations for low-end devices
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = ctx_size;
    ctx_params.n_threads = n_threads;
    ctx_params.n_threads_batch = (g_batch_threads > 0) ? g_batch_threads : n_threads;

    // Memory optimization: prompt-processing batch comes from
    // nativeSetBatchSize (default 512). Small batches keep the parallel
    // prompt pass inside free RAM on 4-6GB phones (the spike that kills
    // the app mid-answer).
    int batch = g_batch_size;
    if (batch < 32) batch = 32;
    if (batch > 2048) batch = 2048;
    ctx_params.n_batch = (uint32_t) batch;
    ctx_params.n_ubatch = (uint32_t) batch;

    // Create context (using new API)
    target.ctx = llama_init_from_model(target.model, ctx_params);
    if (!target.ctx) {
        llama_model_free(target.model);
        target.model = nullptr;
        jclass exception = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exception, "Failed to create context");
        return;
    }

    // Get vocab for tokenization
    target.vocab = llama_model_get_vocab(target.model);
    LOGI("Vocab initialized: %p", (void*)target.vocab);

    if (!target.vocab) {
        llama_free(target.ctx);
        llama_model_free(target.model);
        target.ctx = nullptr;
        target.model = nullptr;
        jclass exception = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exception, "Failed to get vocab from model");
        return;
    }

    // Reset KV cache position counter for new model
    target.n_past = 0;
    g_active_slot.store(slot, std::memory_order_release);

    // Report progress completion
    if (progress_callback) {
        jclass callbackClass = env->GetObjectClass(progress_callback);
        jmethodID invokeMethod = env->GetMethodID(callbackClass, "invoke", "(Ljava/lang/Object;)Ljava/lang/Object;");
        
        // Create Double object for 1.0
        jclass doubleClass = env->FindClass("java/lang/Double");
        jmethodID doubleConstructor = env->GetMethodID(doubleClass, "<init>", "(D)V");
        jobject doubleObj = env->NewObject(doubleClass, doubleConstructor, 1.0);
        
        env->CallObjectMethod(progress_callback, invokeMethod, doubleObj);
        env->DeleteLocalRef(doubleObj);
        env->DeleteLocalRef(callbackClass);
    }

    LOGI("Model loaded successfully");
}

static jobject g_token_callback = nullptr;

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeGenerate(
    JNIEnv* env, jobject thiz,
    jstring prompt, jlong max_tokens, 
    jdouble temperature, jdouble top_p, jlong top_k, jdouble min_p, jdouble typical_p,
    jdouble repeat_penalty, jdouble frequency_penalty, jdouble presence_penalty, jlong repeat_last_n,
    jlong mirostat, jdouble mirostat_tau, jdouble mirostat_eta,
    jlong seed, jboolean penalize_newline,
    jobject token_callback) {
    
    if (g_token_callback != nullptr) {
        env->DeleteGlobalRef(g_token_callback);
        g_token_callback = nullptr;
    }
    g_token_callback = env->NewGlobalRef(token_callback);

    ModelSlot* S = activeSlot();
    llama_model* g_model = S ? S->model : nullptr;
    llama_context* g_ctx = S ? S->ctx : nullptr;
    const llama_vocab* g_vocab = S ? S->vocab : nullptr;
    if (!g_model || !g_ctx || !g_vocab) {
        jclass exception = env->FindClass("java/lang/IllegalStateException");
        env->ThrowNew(exception, "Model not loaded");
        return;
    }
    int& g_n_past = S->n_past;

    // NOTE: KV intentionally persists across calls here. The Dart layer
    // re-sends the FULL history every turn and resets the session via
    // nativeClearContext() before each generation, so each prompt is
    // prefilled from position 0. Do NOT "optimize" by skipping callers'
    // reset: decoding full history onto stale KV duplicates context and
    // makes small models regurgitate their previous reply.
    const char* prompt_str = env->GetStringUTFChars(prompt, nullptr);
    g_stop_flag = false;
    
    const int prompt_len = strlen(prompt_str);
    LOGI("Tokenizing prompt: '%s' (length: %d)", prompt_str, prompt_len);
    LOGI("Vocab pointer: %p, Model pointer: %p", (void*)g_vocab, (void*)g_model);

    // Sanitize the UTF-8 string before tokenizing
    std::string sanitized_prompt = sanitizeUTF8(prompt_str, prompt_len);
    const char* sanitized_cstr = sanitized_prompt.c_str();
    const int sanitized_len = sanitized_prompt.length();
    
    // Tokenize prompt - when tokens is NULL, llama_tokenize returns NEGATIVE count
    const int n_prompt_tokens = -llama_tokenize(g_vocab, sanitized_cstr, sanitized_len, nullptr, 0, true, true);
    LOGI("Token count: %d", n_prompt_tokens);
    
    if (n_prompt_tokens <= 0) {
        env->ReleaseStringUTFChars(prompt, prompt_str);
        jclass exception = env->FindClass("java/lang/RuntimeException");
        char error_msg[256];
        snprintf(error_msg, sizeof(error_msg), "Failed to tokenize prompt (got %d tokens)", n_prompt_tokens);
        env->ThrowNew(exception, error_msg);
        return;
    }
    std::vector<llama_token> tokens(n_prompt_tokens);
    const int actual_tokens = llama_tokenize(g_vocab, sanitized_cstr, sanitized_len, tokens.data(), tokens.size(), true, true);
    if (actual_tokens < 0) {
        env->ReleaseStringUTFChars(prompt, prompt_str);
        jclass exception = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exception, "Failed to tokenize prompt");
        return;
    }
    tokens.resize(actual_tokens);
    env->ReleaseStringUTFChars(prompt, prompt_str);

    const int n_ctx = llama_n_ctx(g_ctx);

    // Keep every decode position strictly inside the window. A single
    // 25% shift is NOT enough when the prompt alone exceeds 75% of
    // n_ctx (normal on 512-ctx devices after a few turns) — decoding
    // past n_ctx corrupts the heap and kills the process instantly
    // with no Dart log ("crash when context fills" despite free RAM).
    int shifts = 0;
    while (g_n_past + (int)tokens.size() > n_ctx - 1 && g_n_past > 0 && shifts < 32) {
        // Never remove cells that don't exist: when g_n_past is smaller
        // than the shift window (short turn 1 + long turn 2 without a
        // reset, or a partial failure), rm/add with p0 > p1 corrupts the
        // KV cell list and the process dies with SIGSEGV mid-prefill
        // (observed status=11 on turn 2). Clamp to what actually exists;
        // an emptied cache exits the loop via g_n_past == 0 and the
        // prompt-truncation below still bounds oversized prompts.
        int n_discard = std::max(1, n_ctx / 4);
        if (n_discard > g_n_past) n_discard = g_n_past;
        LOGI("Context is full, shifting KV cache by %d tokens", n_discard);

        // Remove the oldest tokens from the sequence
        llama_memory_seq_rm(llama_get_memory(g_ctx), 0, 0, n_discard);

        // Shift the remaining tokens (skipped when the cache was fully
        // emptied above — shifting an empty range is undefined).
        if (n_discard < g_n_past) {
            llama_memory_seq_add(llama_get_memory(g_ctx), 0, n_discard, g_n_past, -n_discard);
        }

        // Update the past tokens count
        g_n_past -= n_discard;
        if (g_n_past < 0) g_n_past = 0;
        shifts++;
    }
    // Pathological case: the prompt alone still doesn't fit (tiny
    // n_ctx). Drop oldest prompt tokens rather than writing OOB —
    // the Dart layer normally budgets history so this is last-resort.
    if ((int)tokens.size() > n_ctx - 1 && n_ctx > 1) {
        const int keep = n_ctx - 1;
        LOGI("Prompt (%d tokens) exceeds context (%d); keeping last %d tokens", (int)tokens.size(), n_ctx, keep);
        tokens.erase(tokens.begin(), tokens.end() - keep);
        g_n_past = 0;
    }

    // Process prompt in batches to handle long inputs. Uses the same
    // RAM-scaled g_batch_size as context creation (set via
    // nativeSetBatchSize): a hardcoded 512-token batch here spikes
    // past free RAM on 4-6GB phones and kills the app the instant a
    // prompt is sent — before any token is produced.
    int max_batch_size = g_batch_size;
    if (max_batch_size < 1) max_batch_size = 1;
    if (n_ctx > 1 && max_batch_size > n_ctx - 1) max_batch_size = n_ctx - 1;
    int tokens_processed = 0;
    
    llama_batch batch = llama_batch_init(max_batch_size, 0, 1);

    LOGI("Context size: %d", llama_n_ctx(g_ctx));

    while (tokens_processed < tokens.size()) {
        batch.n_tokens = 0;
        int batch_size = std::min((int)tokens.size() - tokens_processed, max_batch_size);

        for (int i = 0; i < batch_size; i++) {
            batch.token[batch.n_tokens] = tokens[tokens_processed + i];
            batch.pos[batch.n_tokens] = g_n_past + tokens_processed + i;
            batch.n_seq_id[batch.n_tokens] = 1;
            batch.seq_id[batch.n_tokens][0] = 0;
            batch.logits[batch.n_tokens] = (tokens_processed + i == tokens.size() - 1);
            batch.n_tokens++;
        }

        LOGI("Decoding batch starting at position %d with %d tokens", g_n_past + tokens_processed, batch.n_tokens);

        LOGI("Decoding batch: g_n_past=%d, batch_size=%d", g_n_past + tokens_processed, batch.n_tokens);
        int decode_result = llama_decode(g_ctx, batch);
        if (decode_result != 0) {
            LOGE("❌ DECODE FAILED! Result code: %d", decode_result);
            llama_batch_free(batch);
            jclass exception = env->FindClass("java/lang/RuntimeException");
            env->ThrowNew(exception, "Failed to decode prompt");
            return;
        }
        tokens_processed += batch_size;
    }

    LOGI("✅ Decode successful! Processed %d total tokens", tokens_processed);

    // Update position counter after decoding the whole prompt
    g_n_past += tokens.size();

    // Create sampler chain with all parameters
    if (S->sampler) {
        llama_sampler_free(S->sampler);
    }

    // Use seed or current time
    uint32_t sampler_seed = (seed >= 0) ? static_cast<uint32_t>(seed) : static_cast<uint32_t>(time(nullptr));

    llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    S->sampler = llama_sampler_chain_init(sparams);

    // Add penalties first (applied to logits before sampling)
    if (repeat_penalty != 1.0f || frequency_penalty != 0.0f || presence_penalty != 0.0f) {
        llama_sampler_chain_add(S->sampler, llama_sampler_init_penalties(
            repeat_last_n,              // penalty_last_n
            repeat_penalty,             // penalty_repeat
            frequency_penalty,          // penalty_freq
            presence_penalty            // penalty_present
        ));
    }

    // Temperature sampling
    llama_sampler_chain_add(S->sampler, llama_sampler_init_temp(temperature));

    // Add advanced samplers if enabled
    if (mirostat == 1) {
        llama_sampler_chain_add(S->sampler, llama_sampler_init_mirostat(
            llama_vocab_n_tokens(g_vocab),  // Use the vocab to get n_vocab
            sampler_seed,
            mirostat_tau,
            mirostat_eta,
            100  // m parameter
        ));
    } else if (mirostat == 2) {
        llama_sampler_chain_add(S->sampler, llama_sampler_init_mirostat_v2(
            sampler_seed,
            mirostat_tau,
            mirostat_eta
        ));
    } else {
        // Standard sampling chain (only if mirostat is disabled)
        if (min_p > 0.0f && min_p < 1.0f) {
            llama_sampler_chain_add(S->sampler, llama_sampler_init_min_p(min_p, 1));
        }

        if (typical_p < 1.0f) {
            llama_sampler_chain_add(S->sampler, llama_sampler_init_typical(typical_p, 1));
        }

        if (top_k > 0) {
            llama_sampler_chain_add(S->sampler, llama_sampler_init_top_k(top_k));
        }

        if (top_p < 1.0f) {
            llama_sampler_chain_add(S->sampler, llama_sampler_init_top_p(top_p, 1));
        }
    }

    // Final distribution sampler
    llama_sampler_chain_add(S->sampler, llama_sampler_init_dist(sampler_seed));

    // Get callback method
    jclass callbackClass = env->GetObjectClass(token_callback);
    jmethodID invokeMethod = env->GetMethodID(callbackClass, "invoke", "(Ljava/lang/Object;)Ljava/lang/Object;");

    // Generation loop
    LOGI("Starting generation loop: max_tokens=%lld", max_tokens);
    for (int i = 0; i < max_tokens && !g_stop_flag; i++) {
        // Never let the decode position reach n_ctx: slide the window
        // first. Without this, long generations write KV out of bounds
        // and the process dies instantly (same crash as prefill).
        if (g_n_past + 1 >= n_ctx) {
            const int n_discard = std::max(1, n_ctx / 4);
            LOGI("Context full during generation, shifting KV cache by %d tokens", n_discard);
            llama_memory_seq_rm(llama_get_memory(g_ctx), 0, 0, n_discard);
            llama_memory_seq_add(llama_get_memory(g_ctx), 0, n_discard, g_n_past, -n_discard);
            g_n_past -= n_discard;
            if (g_n_past < 0) g_n_past = 0;
        }
        // Sample next token
        LOGI("Sampling token %d, g_n_past=%d", i + 1, g_n_past);
        llama_token new_token_id = llama_sampler_sample(S->sampler, g_ctx, -1);
        LOGI("Sampled token: %d", new_token_id);

        // Check for end of generation (EOS/EOD tokens)
        if (llama_vocab_is_eog(g_vocab, new_token_id)) {
            LOGI("EOS token detected, ending generation.");
            break;
        }

        // Decode token to string
        char buffer[256];
        int32_t length = llama_token_to_piece(g_vocab, new_token_id, buffer, sizeof(buffer), 0, true);
        std::string piece;
        
        if (length > 0) {
            piece = sanitizeUTF8(buffer, length);
        } else {
            piece = "";
        }
        
        // Call Kotlin callback
        jstring token_str = env->NewStringUTF(piece.c_str());
        env->CallObjectMethod(g_token_callback, invokeMethod, token_str);
        env->DeleteLocalRef(token_str);

        // Prepare next batch
        batch.n_tokens = 0;
        batch.token[batch.n_tokens] = new_token_id;
        batch.pos[batch.n_tokens] = g_n_past;  // Use the tracked position
        batch.n_seq_id[batch.n_tokens] = 1;
        batch.seq_id[batch.n_tokens][0] = 0;
        batch.logits[batch.n_tokens] = true;
        batch.n_tokens++;

        if (llama_decode(g_ctx, batch) != 0) {
            LOGE("Failed to decode after sampling token %d", i + 1);
            break;
        }
        
        // Update position counter after each generated token
        g_n_past++;
    }
    LOGI("Generation loop finished.");

    if (g_token_callback != nullptr) {
        env->DeleteGlobalRef(g_token_callback);
        g_token_callback = nullptr;
    }

    // After generation completion, ensure the KV cache is properly managed
    // In some llama.cpp versions, KV cache management may be needed between generations
    // For chat applications, we want to maintain conversation context
    
    llama_batch_free(batch);
    env->DeleteLocalRef(callbackClass);
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeSetBatchSize(
    JNIEnv* env, jobject thiz, jint n_batch, jint n_batch_threads) {
    if (n_batch < 32) n_batch = 32;
    if (n_batch > 2048) n_batch = 2048;
    g_batch_size = n_batch;
    g_batch_threads = (n_batch_threads > 0) ? n_batch_threads : -1;
    LOGI("Batch size set to %d (batch threads %d)", g_batch_size, g_batch_threads);
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeStop(
    JNIEnv* env, jobject thiz) {
    g_stop_flag = true;
    // When stopping generation, we just set the flag - KV cache management handled by llama.cpp
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeFreeModel(
    JNIEnv* env, jobject thiz) {

    for (int i = 0; i < MAX_SLOTS; i++) {
        freeSlotContents(g_slots[i]);
    }
    g_active_slot.store(-1, std::memory_order_release);

    LOGI("All model slots freed");
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeSelectSlot(
    JNIEnv* env, jobject thiz, jint slot) {
    if (slot < 0 || slot >= MAX_SLOTS) return JNI_FALSE;
    if (!g_slots[slot].model || !g_slots[slot].ctx) return JNI_FALSE;
    g_active_slot.store(slot, std::memory_order_release);
    LOGI("Active slot switched to %d", slot);
    return JNI_TRUE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeIsSlotLoaded(
    JNIEnv* env, jobject thiz, jint slot) {
    if (slot < 0 || slot >= MAX_SLOTS) return JNI_FALSE;
    return (g_slots[slot].model && g_slots[slot].ctx) ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeFreeSlot(
    JNIEnv* env, jobject thiz, jint slot) {
    if (slot < 0 || slot >= MAX_SLOTS) return;
    freeSlotContents(g_slots[slot]);
    if (g_active_slot.load(std::memory_order_acquire) == slot) {
        g_active_slot.store(-1, std::memory_order_release);
    }
    LOGI("Slot %d freed", slot);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeGetTokensUsed(
    JNIEnv* env, jobject thiz) {
    ModelSlot* S = activeSlot();
    return S ? S->n_past : 0;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeGetContextSize(
    JNIEnv* env, jobject thiz) {
    ModelSlot* S = activeSlot();
    return (S && S->ctx) ? llama_n_ctx(S->ctx) : 0;
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeClearContext(
    JNIEnv* env, jobject thiz) {
    ModelSlot* S = activeSlot();
    if (!S || !S->ctx) {
        LOGE("Cannot clear context: context is null");
        return;
    }

    llama_memory_t mem = llama_get_memory(S->ctx);
    if (mem) {
        llama_memory_seq_rm(mem, 0, 0, -1);
        S->n_past = 0;
        LOGI("Context cleared, n_past reset to 0");
    } else {
        LOGE("Failed to get memory object from context");
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeSetSystemPromptLength(
    JNIEnv* env, jobject thiz, jint length) {
    // Currently not used but available for future smart context management
    LOGI("System prompt length set to: %d tokens (currently unused)", length);
}
