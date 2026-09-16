/// CubicLM Security — process-isolation helpers (no native code).
///
/// Full PRoot sandboxing is Phase 6 native work. Until then every command
/// and path funnels through these pure checks:
/// - [isPathAllowed]: jail check shared by tools and the terminal.
/// - [isCommandBlocked]: destructive-operation blocklist with a reason.
/// - [redactSecrets]: scrub API keys / tokens before logging or display.
///
/// Pure Dart — fully unit-testable.
library;

/// Argument-aware command risk (finer than the blocklist alone).
enum CommandRisk {
  /// Read-only, side-effect free (may auto-approve).
  safe,

  /// Side effects possible (needs approval).
  review,

  /// Dangerous even with approval UI (always explicit).
  high,

  /// Never runs (blocked with a reason).
  blocked,
}

/// Sandbox policy checks.
class SandboxService {
  /// True when [relativePath] stays inside the workspace jail.
  static bool isPathAllowed(String relativePath) {
    final p = relativePath.trim().replaceAll('\\', '/');
    if (p.isEmpty) return false;
    if (p.startsWith('/')) return false;
    if (p.contains(':')) return false; // drive letters, alternate streams
    if (p.split('/').any((seg) => seg == '..')) return false;
    if (p.length > 512) return false;
    return true;
  }

  /// Reason a command is blocked, or null when allowed.
  ///
  /// Catastrophic operations only (Mobile-Harness parity: `rm -rf` on
  /// filesystem roots, disk writes, fork bombs). Recoverable-but-dangerous
  /// commands (`git reset --hard`, project-relative `rm -rf`) are NOT
  /// blocked — [classifyCommand] escalates them to [CommandRisk.high] so
  /// the approval gate always asks explicitly.
  static String? isCommandBlocked(String command) {
    final lower = command.toLowerCase().trim();
    if (lower.isEmpty) return 'Empty command';
    if (lower.startsWith('rm -rf /') || lower.startsWith('rm -rf /*')) {
      return 'Recursive delete of root filesystem';
    }
    if (lower == 'rm -rf ~' || lower == 'rm -rf ~/') {
      return 'Recursive delete of home directory';
    }
    if (RegExp(r'rm\s+-rf?\s+[a-z]:').hasMatch(lower)) {
      return 'Recursive delete of a drive root';
    }
    // Bare `rm -rf` on shell roots that resolve outside any project:
    // `.`, `./`, `*`, `$HOME`, `%USERPROFILE%`, bare `~`.
    if (RegExp(r'rm\s+(-[a-z]*r[a-z]*\s+)*(-[a-z]*f[a-z]*\s+)?'
            r'(\.(\/)?|\*|~|\$home\b|%userprofile%)(\s|;|&&|\||$)')
        .hasMatch(lower)) {
      return 'Recursive delete of working directory root';
    }
    if (lower.contains('mkfs.') || lower.contains('format c:')) {
      return 'Filesystem formatting';
    }
    if (lower.contains('> /dev/sda') || lower.contains('dd if=')) {
      return 'Direct disk write';
    }
    // Any redirect into a device node (e.g. `> /dev/sda`, `>>/dev/kmem`).
    if (RegExp(r'>\s*/dev/').hasMatch(lower)) {
      return 'Direct device write';
    }
    if (lower.contains(':(){:|:&};:')) return 'Fork bomb';
    if (RegExp(r'chmod\s+-r\s+777\s+/').hasMatch(lower)) {
      return 'Recursive permission opening of root';
    }
    return null;
  }

  /// Classify a shell command for the approval gate.
  ///
  /// Returns a (risk, reason) record: [reason] is set only for [blocked].
  /// Chained commands (`&&`, `;`, pipes, substitutions) escalate to at
  /// least [review] even when the base command is harmless.
  static ({CommandRisk risk, String? reason}) classifyCommand(
      String command) {
    final cmd = command.trim();
    if (cmd.isEmpty) {
      return (risk: CommandRisk.blocked, reason: 'Empty command');
    }
    final blocked = isCommandBlocked(cmd);
    if (blocked != null) {
      return (risk: CommandRisk.blocked, reason: blocked);
    }
    final lower = cmd.toLowerCase();
    // Piped network-to-shell (`curl … | sh`) fetches and runs code —
    // checked before the generic chain rule so it lands on high.
    if ((lower.contains('curl') || lower.contains('wget')) &&
        RegExp(r'\|\s*(sh|bash|zsh|powershell|cmd)\b').hasMatch(lower)) {
      return (risk: CommandRisk.high, reason: null);
    }
    if (RegExp(r'(&&|\|\||[;|]|`|\$\()').hasMatch(cmd)) {
      return (risk: CommandRisk.review, reason: null);
    }
    final first = lower.split(RegExp(r'\s+')).first;
    const safeBinaries = {
      'ls',
      'dir',
      'pwd',
      'whoami',
      'echo',
      'cat',
      'type',
      'hostname',
      'node',
      'python',
    };
    // `node --version` style probes are safe; bare `node`/`python` REPLs
    // would hang waiting on stdin, so only allow them with version flags.
    if (first == 'node' || first == 'python') {
      if (lower.contains('--version') || lower.contains('-v')) {
        return (risk: CommandRisk.safe, reason: null);
      }
      return (risk: CommandRisk.review, reason: null);
    }
    if (safeBinaries.contains(first)) {
      return (risk: CommandRisk.safe, reason: null);
    }
    if (first == 'git') {
      const safeGit = {
        'status',
        'diff',
        'log',
        'show',
        'branch',
        'remote',
        'ls-files',
        'rev-parse',
      };
      final sub = lower
          .split(RegExp(r'\s+'))
          .skip(1)
          .firstWhere((t) => !t.startsWith('-'), orElse: () => '');
      if (safeGit.contains(sub)) {
        return (risk: CommandRisk.safe, reason: null);
      }
      // Destructive history rewrites: Mobile-Harness shows an explicit
      // confirm dialog — here they always need explicit approval.
      if (sub == 'reset' && RegExp(r'\b--hard\b').hasMatch(lower)) {
        return (risk: CommandRisk.high, reason: null);
      }
      if (sub == 'clean' && RegExp(r'(^|\s)-[a-z]*f').hasMatch(lower)) {
        return (risk: CommandRisk.high, reason: null);
      }
      const highGit = {'push', 'reset', 'clean', 'checkout'};
      if (highGit.contains(sub)) {
        return (risk: CommandRisk.high, reason: null);
      }
      return (risk: CommandRisk.review, reason: null);
    }
    if (first == 'npm' || first == 'npx' || first == 'flutter' || first == 'dart') {
      return (risk: CommandRisk.review, reason: null);
    }
    // Deleting anything recursively always needs explicit approval,
    // even when the target looks project-relative.
    if (first == 'rm' && RegExp(r'(^|\s)-[a-z]*r').hasMatch(lower)) {
      return (risk: CommandRisk.high, reason: null);
    }
    // Recursive permission/ownership changes are easy to get wrong.
    if ((first == 'chmod' || first == 'chown') &&
        RegExp(r'(^|\s)-[a-z]*R').hasMatch(cmd)) {
      return (risk: CommandRisk.high, reason: null);
    }
    if (first == 'sudo' || first == 'su' || first == 'doas') {
      return (risk: CommandRisk.high, reason: null);
    }
    if (first == 'curl' || first == 'wget' || first == 'ssh' || first == 'scp') {
      // Network egress / auth: always explicit (mirrors the reference app).
      return (risk: CommandRisk.high, reason: null);
    }
    return (risk: CommandRisk.review, reason: null);
  }

  static final _keyValueRe = RegExp(
    r'(api[_-]?key|secret|token|password)\s*[:=]\s*([^\s;,}"]+)',
    caseSensitive: false,
  );
  static final _bearerRe = RegExp(
    r'bearer\s+[A-Za-z0-9\-._~+/=]+',
    caseSensitive: false,
  );
  static final _queryKeyRe = RegExp(
    r'([?&](key|token|api_key)=)[^&\s]+',
    caseSensitive: false,
  );
  static final _longTokenRe = RegExp(
      r'\b(sk-[A-Za-z0-9\-_]{8,}|AIza[A-Za-z0-9\-_]{8,}|xox[bap]-[A-Za-z0-9\-_]{6,})\b');

  /// Scrub secrets from text before logs / trace display.
  static String redactSecrets(String text) {
    var s = text.replaceAllMapped(
        _keyValueRe, (m) => '${m.group(1)}=***REDACTED***');
    s = s.replaceAll(_bearerRe, 'Bearer ***REDACTED***');
    s = s.replaceAllMapped(
        _queryKeyRe, (m) => '${m.group(1)}***REDACTED***');
    s = s.replaceAll(_longTokenRe, '***REDACTED***');
    return s;
  }
}
