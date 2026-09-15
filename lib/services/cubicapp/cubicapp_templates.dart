/// CubicApp Builder — Android project templates.
///
/// Each template provides a starting point for AI to generate a full Android
/// project. Templates include a base project structure and a system prompt
/// that guides the AI on what to generate.
library;

import 'dart:convert' as json;

/// A single file in a template project.
class CubicAppFile {
  final String path;
  final String content;

  const CubicAppFile({required this.path, required this.content});

  Map<String, String> toMap() => {'path': path, 'content': content};
}

/// A project template with metadata, base files, and AI generation prompt.
class CubicAppTemplate {
  final String id;
  final String name;
  final String description;
  final String icon; // lucide icon name
  final List<CubicAppFile> baseFiles;
  final String systemPrompt;

  const CubicAppTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.baseFiles,
    required this.systemPrompt,
  });
}

// ─── GitHub Actions Workflow ─────────────────────────────────────────────

const _githubActionsWorkflow = r'''name: Build Android APK

on:
  push:
    branches: [ main, master ]
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.32.0'
          channel: 'stable'

      - name: Flutter pub get
        run: flutter pub get

      - name: Build APK (release)
        run: flutter build apk --release --split-per-abi

      - name: Upload APK artifacts
        uses: actions/upload-artifact@v4
        with:
          name: apk-release
          path: build/app/outputs/flutter-apk/*.apk
          if-no-files-found: error
''';

// ─── Helper: Generate build.gradle.kts ──────────────────────────────────

String _buildGradleKts({
  required String appId,
  required String appName,
  int minSdk = 21,
  int compileSdk = 35,
  int targetSdk = 35,
}) =>
    '''
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "$appId"
    compileSdk = $compileSdk

    defaultConfig {
        applicationId = "$appId"
        minSdk = $minSdk
        targetSdk = $targetSdk
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.webkit:webkit:1.8.0")
}
''';

String _settingsGradle(String appName) =>
    '''
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "$appName"
include(":app")
''';

String _gradleProperties() =>
    '''
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
''';

String _proguardRules() =>
    '''
# Default ProGuard rules
-keepattributes *Annotation*
-keep class com.google.android.material.** { *; }
''';

String _gitignore() =>
    '''
*.iml
.gradle
/local.properties
/.idea
.DS_Store
/build
/captures
.externalNativeBuild
.cxx
local.properties
/app/build
/app/release
*.apk
*.aab
*.jks
*.keystore
''';

// ─── Template: WebView Wrapper ──────────────────────────────────────────

const _webViewActivity = r'''package {{PACKAGE}}.MainActivity

import android.annotation.SuppressLint
import android.os.Bundle
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    private lateinit var webView: WebView

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        webView = WebView(this)
        setContentView(webView)

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            loadWithOverviewMode = true
            useWideViewPort = true
            builtInZoomControls = true
            displayZoomControls = false
            mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
        }
        webView.webViewClient = WebViewClient()
        webView.webChromeClient = WebChromeClient()
        webView.loadUrl("{{URL}}")
    }

    override fun onBackPressed() {
        if (webView.canGoBack()) webView.goBack()
        else super.onBackPressed()
    }
}
''';

// ─── Template: Notes App ────────────────────────────────────────────────

const _notesLayoutXml = r'''<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="16dp">

    <TextView
        android:id="@+id/title"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="My Notes"
        android:textSize="24sp"
        android:textStyle="bold"
        android:layout_marginBottom="16dp"/>

    <com.google.android.material.textfield.TextInputLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:hint="New note"
        android:layout_marginBottom="8dp">

        <com.google.android.material.textfield.TextInputEditText
            android:id="@+id/noteInput"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:minLines="2"/>
    </com.google.android.material.textfield.TextInputLayout>

    <Button
        android:id="@+id/addBtn"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="Add Note"
        android:layout_marginBottom="16dp"/>

    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/notesList"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"/>
</LinearLayout>
''';

const _notesMainActivity = r'''package {{PACKAGE}}.MainActivity

import android.os.Bundle
import android.widget.Button
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.textfield.TextInputEditText

class MainActivity : AppCompatActivity() {
    private val notes = mutableListOf<String>()
    private lateinit var adapter: NotesAdapter

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val input = findViewById<TextInputEditText>(R.id.noteInput)
        val addBtn = findViewById<Button>(R.id.addBtn)
        val list = findViewById<RecyclerView>(R.id.notesList)

        adapter = NotesAdapter(notes) { pos ->
            notes.removeAt(pos)
            adapter.notifyItemRemoved(pos)
        }
        list.layoutManager = LinearLayoutManager(this)
        list.adapter = adapter

        addBtn.setOnClickListener {
            val text = input.text?.toString()?.trim() ?: ""
            if (text.isNotEmpty()) {
                notes.add(0, text)
                adapter.notifyItemInserted(0)
                input.text?.clear()
            } else {
                Toast.makeText(this, "Type a note first", Toast.LENGTH_SHORT).show()
            }
        }
    }
}
''';

// ─── Template: Todo App ─────────────────────────────────────────────────

const _todoMainActivity = r'''package {{PACKAGE}}.MainActivity

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView

data class TodoItem(val text: String, var done: Boolean = false)

class MainActivity : AppCompatActivity() {
    private val items = mutableListOf<TodoItem>()
    private lateinit var adapter: TodoAdapter

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val input = findViewById<EditText>(R.id.todoInput)
        val addBtn = findViewById<Button>(R.id.addBtn)
        val list = findViewById<RecyclerView>(R.id.todoList)

        adapter = TodoAdapter(items) { pos ->
            items[pos].done = !items[pos].done
            adapter.notifyItemChanged(pos)
        }
        list.layoutManager = LinearLayoutManager(this)
        list.adapter = adapter

        addBtn.setOnClickListener {
            val text = input.text?.toString()?.trim() ?: ""
            if (text.isNotEmpty()) {
                items.add(TodoItem(text))
                adapter.notifyItemInserted(items.size - 1)
                input.text?.clear()
            }
        }
    }
}

class TodoAdapter(
    private val items: List<TodoItem>,
    private val onToggle: (Int) -> Unit
) : RecyclerView.Adapter<TodoAdapter.VH>() {
    class VH(v: View) : RecyclerView.ViewHolder(v) {
        val check: CheckBox = v.findViewById(R.id.todoCheck)
        val text: TextView = v.findViewById(R.id.todoText)
    }
    override fun onCreateViewHolder(p: ViewGroup, viewType: Int) =
        VH(LayoutInflater.from(p.context).inflate(R.layout.item_todo, p, false))
    override fun getItemCount() = items.size
    override fun onBindViewHolder(h: VH, pos: Int) {
        h.text.text = items[pos].text
        h.check.isChecked = items[pos].done
        h.itemView.setOnClickListener { onToggle(pos) }
    }
}
''';

// ─── Template: Calculator ───────────────────────────────────────────────

const _calcMainActivity = r'''package {{PACKAGE}}.MainActivity

import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    private lateinit var display: TextView
    private var current = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        display = findViewById(R.id.display)

        val buttons = mapOf(
            R.id.btn0 to "0", R.id.btn1 to "1", R.id.btn2 to "2",
            R.id.btn3 to "3", R.id.btn4 to "4", R.id.btn5 to "5",
            R.id.btn6 to "6", R.id.btn7 to "7", R.id.btn8 to "8",
            R.id.btn9 to "9", R.id.btnDot to ".",
            R.id.btnAdd to "+", R.id.btnSub to "-",
            R.id.btnMul to "*", R.id.btnDiv to "/",
            R.id.btnOpen to "(", R.id.btnClose to ")"
        )

        for ((id, value) in buttons) {
            findViewById<Button>(id).setOnClickListener { append(value) }
        }

        findViewById<Button>(R.id.btnClear).setOnClickListener {
            current = ""
            display.text = "0"
        }
        findViewById<Button>(R.id.btnEquals).setOnClickListener { calculate() }
        findViewById<Button>(R.id.btnBack).setOnClickListener {
            if (current.isNotEmpty()) {
                current = current.dropLast(1)
                display.text = current.ifEmpty { "0" }
            }
        }
    }

    private fun append(s: String) {
        current += s
        display.text = current
    }

    private fun calculate() {
        try {
            val result = eval(current)
            display.text = if (result == result.toLong().toDouble())
                result.toLong().toString() else String.format("%.6g", result)
            current = display.text.toString()
        } catch (e: Exception) {
            display.text = "Error"
            current = ""
        }
    }

    private fun eval(expr: String): Double {
        return object : Any() {
            var pos = -1; var ch = 0

            fun nextChar() { ch = if (++pos < expr.length) expr[pos].code else -1 }
            fun eat(c: Int): Boolean {
                while (ch == ' '.code) nextChar()
                if (ch == c) { nextChar(); return true }
                return false
            }
            fun parse(): Double {
                nextChar()
                val x = parseExpression()
                if (pos < expr.length) throw RuntimeException("Unexpected: ${expr[pos]}")
                return x
            }
            fun parseExpression(): Double {
                var x = parseTerm()
                while (true) {
                    if (eat('+'.code)) x += parseTerm()
                    else if (eat('-'.code)) x -= parseTerm()
                    else return x
                }
            }
            fun parseTerm(): Double {
                var x = parseFactor()
                while (true) {
                    if (eat('*'.code)) x *= parseFactor()
                    else if (eat('/'.code)) x /= parseFactor()
                    else return x
                }
            }
            fun parseFactor(): Double {
                if (eat('+'.code)) return parseFactor()
                if (eat('-'.code)) return -parseFactor()
                var x: Double
                val startPos = pos
                if (eat('('.code)) {
                    x = parseExpression()
                    eat(')'.code)
                } else if (ch in '0'.code..'9'.code || ch == '.'.code) {
                    while (ch in '0'.code..'9'.code || ch == '.'.code) nextChar()
                    x = expr.substring(startPos, pos).toDouble()
                } else {
                    throw RuntimeException("Unexpected: ${if (ch != -1) expr[pos] else 'EOF'}")
                }
                return x
            }
        }.parse()
    }
}
''';

// ─── Template: Quiz App ─────────────────────────────────────────────────

const _quizMainActivity = r'''package {{PACKAGE}}.MainActivity

import android.os.Bundle
import android.widget.*
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    private val questions = listOf(
        Triple("What is 2 + 2?", listOf("3", "4", "5", "6"), 1),
        Triple("Capital of Japan?", listOf("Seoul", "Tokyo", "Beijing", "Bangkok"), 1),
        Triple("Which planet is closest to the Sun?", listOf("Venus", "Earth", "Mercury", "Mars"), 2),
        Triple("1 km = ?", listOf("100m", "1000m", "10000m", "10m"), 1),
        Triple("Square root of 9?", listOf("2", "4", "3", "5"), 2)
    )
    private var current = 0
    private var score = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        showQuestion()
    }

    private fun showQuestion() {
        if (current >= questions.size) {
            val tv = TextView(this).apply {
                text = "Score: $score / ${questions.size}"
                textSize = 22f
                setPadding(32, 32, 32, 32)
            }
            setContentView(tv)
            return
        }
        val (q, options, _) = questions[current]
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 32, 32, 32)
        }
        layout.addView(TextView(this).apply {
            text = q; textSize = 20f; setPadding(0, 0, 0, 24)
        })
        for ((_, opt) in options.withIndex()) {
            val btn = Button(this).apply {
                text = opt
                setOnClickListener { checkAnswer(options.indexOf(opt)) }
            }
            layout.addView(btn)
        }
        setContentView(layout)
    }

    private fun checkAnswer(selected: Int) {
        if (selected == questions[current].third) score++
        current++
        showQuestion()
    }
}
''';

// ─── Export all templates ───────────────────────────────────────────────

List<CubicAppTemplate> cubicAppTemplates() => [
      const CubicAppTemplate(
        id: 'webview',
        name: 'WebView Wrapper',
        description:
            'Wraps any URL as a native Android app with back navigation, zoom, and JS support.',
        icon: 'globe',
        baseFiles: [],
        systemPrompt:
            'Generate a WebView-based Android app that loads a user-specified URL. '
            'Include back-button navigation, JavaScript enabled, DOM storage, zoom controls, '
            'and mixed content support. Use Kotlin with Material Design components.',
      ),
      const CubicAppTemplate(
        id: 'blank',
        name: 'Blank Starter',
        description:
            'Minimal empty Android project with Kotlin + Material Design. AI fills in the rest.',
        icon: 'file',
        baseFiles: [],
        systemPrompt:
            'Generate a minimal Android starter project with a single Activity and '
            'Material Design. Use Kotlin, ViewBinding, and Material3 components. '
            'Add a simple centered "Hello World" text as the starting point.',
      ),
      const CubicAppTemplate(
        id: 'notes',
        name: 'Notes App',
        description:
            'Add, view, and delete notes with RecyclerView. Material Design UI.',
        icon: 'stickyNote',
        baseFiles: [],
        systemPrompt:
            'Generate a Notes Android app with: add/view/delete notes, RecyclerView list, '
            'Material Design TextInputLayout, and simple in-memory storage. Use Kotlin.',
      ),
      const CubicAppTemplate(
        id: 'todo',
        name: 'Todo App',
        description:
            'Task list with checkbox toggle. Material Design with RecyclerView.',
        icon: 'checkSquare',
        baseFiles: [],
        systemPrompt:
            'Generate a Todo Android app with: add tasks, toggle completion with checkbox, '
            'RecyclerView list, Material Design UI. Use Kotlin.',
      ),
      const CubicAppTemplate(
        id: 'calculator',
        name: 'Calculator',
        description:
            'Basic arithmetic calculator with buttons grid. Supports +, -, *, /.',
        icon: 'calculator',
        baseFiles: [],
        systemPrompt:
            'Generate a Calculator Android app with: grid of number/operator buttons, '
            'expression display, evaluate with built-in parser, backspace and clear. Use Kotlin.',
      ),
      const CubicAppTemplate(
        id: 'quiz',
        name: 'Quiz App',
        description:
            'Multiple choice quiz with scoring. Perfect for trivia apps.',
        icon: 'brainCircuit',
        baseFiles: [],
        systemPrompt:
            'Generate a Quiz Android app with: multiple choice questions, scoring system, '
            'progress indicator, and results screen. Use Kotlin with Material Design.',
      ),
      const CubicAppTemplate(
        id: 'ai_generate',
        name: 'AI Generate',
        description:
            'No template - describe what you want and AI generates the full project.',
        icon: 'sparkles',
        baseFiles: [],
        systemPrompt:
            'Generate a complete Android project based on the user\'s description. '
            'Use Kotlin with Material Design. Include all necessary files: build.gradle, '
            'manifest, activities, layouts, and resources.',
      ),
    ];

/// Build a complete Android project from a template + AI modifications.
///
/// Returns a map of path -> content for all project files.
Map<String, String> buildCubicAppProject({
  required CubicAppTemplate template,
  required String appId,
  required String appName,
}) {
  final files = <String, String>{};

  // Root project files
  files['build.gradle.kts'] =
      _buildGradleKts(appId: appId, appName: appName);
  files['settings.gradle.kts'] = _settingsGradle(appName);
  files['gradle.properties'] = _gradleProperties();
  files['.gitignore'] = _gitignore();
  files['README.md'] = '# $appName\n\nGenerated by CubicApp Builder.\n';

  // GitHub Actions
  files['.github/workflows/build.yml'] = _githubActionsWorkflow;

  // App module
  files['app/build.gradle.kts'] = _buildGradleKts(
    appId: appId,
    appName: appName,
    minSdk: 21,
    compileSdk: 35,
    targetSdk: 35,
  );
  files['app/proguard-rules.pro'] = _proguardRules();

  // AndroidManifest
  files['app/src/main/AndroidManifest.xml'] =
      '''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <application
        android:allowBackup="true"
        android:label="$appName"
        android:supportsRtl="true"
        android:theme="@style/Theme.Material3.DayNight.NoActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:configChanges="orientation|screenSize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
''';

  // Template-specific files
  final pkg = appId.replaceAll('.', '/');
  switch (template.id) {
    case 'webview':
      files['app/src/main/java/$pkg/MainActivity.kt'] = _webViewActivity
          .replaceAll('{{PACKAGE}}', appId)
          .replaceAll('{{URL}}', 'https://example.com');
    case 'notes':
      files['app/src/main/java/$pkg/MainActivity.kt'] =
          _notesMainActivity.replaceAll('{{PACKAGE}}', appId);
      files['app/src/main/res/layout/activity_main.xml'] = _notesLayoutXml;
    case 'todo':
      files['app/src/main/java/$pkg/MainActivity.kt'] =
          _todoMainActivity.replaceAll('{{PACKAGE}}', appId);
    case 'calculator':
      files['app/src/main/java/$pkg/MainActivity.kt'] =
          _calcMainActivity.replaceAll('{{PACKAGE}}', appId);
    case 'quiz':
      files['app/src/main/java/$pkg/MainActivity.kt'] =
          _quizMainActivity.replaceAll('{{PACKAGE}}', appId);
    case 'blank':
      files['app/src/main/java/$pkg/MainActivity.kt'] = '''package $appId

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}
''';
      files['app/src/main/res/layout/activity_main.xml'] =
          '''<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:gravity="center"
    android:orientation="vertical">
    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Hello World!"
        android:textSize="24sp"/>
</LinearLayout>
''';
    default:
      break;
  }

  return files;
}

/// Parse AI-generated files from structured JSON output.
Map<String, String> parseAiGeneratedFiles(String raw) {
  final files = <String, String>{};
  // Try JSON format: {"files":[{"path":"...","content":"..."}]}
  final jsonMatch = RegExp(r'\{[\s\S]*"files"[\s\S]*\}').firstMatch(raw);
  if (jsonMatch != null) {
    try {
      final decoded = Map<String, dynamic>.from(
          json.jsonDecode(jsonMatch.group(0)!) as Map);
      final list = decoded['files'] as List?;
      if (list != null) {
        for (final f in list) {
          final m = Map<String, dynamic>.from(f as Map);
          final path = (m['path'] ?? '').toString();
          final content = (m['content'] ?? '').toString();
          if (path.isNotEmpty && content.isNotEmpty) {
            files[path] = content;
          }
        }
      }
    } catch (_) {
      // AI output might not be structured, skip
    }
  }
  return files;
}
