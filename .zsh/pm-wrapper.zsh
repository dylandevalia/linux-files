# ==============================================================================
# pm - Universal Package Manager Wrapper
# ------------------------------------------------------------------------------
# A deterministic, context-aware utility to unify npm, pnpm, yarn, and bun.
#
# CORE PHILOSOPHY:
#   - Root-First: Commands like 'install' and 'nuke' always target the 
#     detected project root, regardless of your current subdirectory.
#   - Deterministic: Maps inconsistent manager flags (e.g., bun's -d vs 
#     npm's -D) to a single, predictable API.
#   - CI/CD Ready: Respects CI=1 and --yes flags to bypass interactivity.
#   - Safety-Centric: 'nuke' requires explicit folder-name confirmation 
#     and refuses to run on system-critical directories.
#   - Hardened: Uses zsh emulation and safe argument expansion to prevent bugs.
#
# USAGE:
#   pm                      -> Install dependencies at project root.
#   pm ci [--frozen]        -> Install with a locked/immutable lockfile.
#   pm add [-D|-P|-O] <pkg> -> Add package (dev, prod, or optional).
#   pm x <cmd>              -> Unified 'exec' (npx / pnpm dlx / yarn dlx / bunx).
#   pm up                   -> Interactive update (prefers ncu, falls back to native).
#   pm nuke                 -> Wipe node_modules/locks and reinstall (safeguarded).
#   pm doctor               -> Diagnostic report of the current environment.
#   pm [script]             -> Execute a package.json script with auto-run logic.
#
# OPTIONS:
#   -y, --yes         -> Force 'yes' for all prompts (automatic in CI / non-TTY).
#   --no-prompt       -> Fail immediately if interaction would be required.
#   -v, --verbose     -> Print each command before executing.
#   -V, --version     -> Print wrapper version and exit.
#   -h, --help        -> Display usage and help.
# ==============================================================================

typeset -gr PM_WRAPPER_VERSION="3.9"

pm() {
  emulate -L zsh
  setopt local_options no_unset pipefail

  local PM="" COMMAND="" ROOT_DIR="" PKG_DIR=""
  local ARGS=()
  local ASSUME_YES=0 NO_PROMPT=0 VERBOSE=0 IS_INTERACTIVE=0
  local PARSING_FLAGS=1 SELECTION_REASON="default (npm)"
  local -a ALL_LOCKS_FOUND=()
  local PM_VERSION_CACHE=""

  # 1. Environment Detection
  [[ -t 0 ]] && IS_INTERACTIVE=1
  [[ "${CI:-}" =~ ^(1|true|yes|TRUE|True)$ ]] && NO_PROMPT=1

  # 2. Global Flag Parsing
  for arg in "$@"; do
    if (( PARSING_FLAGS )); then
      case $arg in
        --) PARSING_FLAGS=0 ;;
        -y|--yes) ASSUME_YES=1 ;;
        --no-prompt) NO_PROMPT=1 ;;
        -v|--verbose) VERBOSE=1 ;;
        -V|--version) print "pm wrapper v$PM_WRAPPER_VERSION"; return 0 ;;
        -h|--help|help) _pm_help; return 0 ;;
        *) ARGS+=("$arg") ;;
      esac
    else
      ARGS+=("$arg")
    fi
  done

  # 3. Context Discovery
  # _pm_discover
  # Walk up from $PWD searching for lockfiles (to identify the package manager
  # and project root) and the nearest package.json (to set PKG_DIR). Collects
  # all lockfiles encountered for multi-lockfile conflict detection.
  # Falls back to npm if no lockfile is found.
  _pm_discover() {
    local current="$PWD"
    local found_pkg=0
    while [[ "$current" != "/" ]]; do
      # Ensure package.json is readable before claiming it
      [[ -r "$current/package.json" && $found_pkg -eq 0 ]] && { PKG_DIR="$current"; found_pkg=1; }
      
      if [[ -z "$PM" ]]; then
        if [[ -f "$current/pnpm-lock.yaml" ]]; then PM="pnpm"; SELECTION_REASON="lockfile (pnpm-lock.yaml) at $current"
        elif [[ -f "$current/bun.lockb" || -f "$current/bun.lock" ]]; then PM="bun"; SELECTION_REASON="lockfile (bun.lock) at $current"
        elif [[ -f "$current/yarn.lock" ]]; then PM="yarn"; SELECTION_REASON="lockfile (yarn.lock) at $current"
        elif [[ -f "$current/package-lock.json" ]]; then PM="npm"; SELECTION_REASON="lockfile (package-lock.json) at $current"
        fi
        [[ -n "$PM" ]] && ROOT_DIR="$current"
      fi

      [[ -f "$current/pnpm-lock.yaml" ]] && ALL_LOCKS_FOUND+=("pnpm@$current")
      [[ -f "$current/bun.lockb" || -f "$current/bun.lock" ]] && ALL_LOCKS_FOUND+=("bun@$current")
      [[ -f "$current/yarn.lock" ]] && ALL_LOCKS_FOUND+=("yarn@$current")
      [[ -f "$current/package-lock.json" ]] && ALL_LOCKS_FOUND+=("npm@$current")

      if [[ -d "$current/.git" && -z "$PM" ]]; then
        ROOT_DIR="$current"; SELECTION_REASON="boundary (.git) at $current"; break
      fi
      current="${current:h}"
    done
    [[ -z "$ROOT_DIR" ]] && ROOT_DIR="$PWD"
    [[ -z "$PKG_DIR" ]] && PKG_DIR="$ROOT_DIR"
    [[ -z "$PM" ]] && PM="npm"
    ROOT_DIR="$(cd "$ROOT_DIR" && pwd -P)"
  }
  _pm_discover

  # Extract the subcommand (first non-flag arg) and shift it off ARGS
  COMMAND=${ARGS[1]:-install}
  ARGS=("${ARGS[@]:1}")

  # --- Helpers ---

  # _pm_log [cmd] [args...]
  # Print a color-coded execution preview to stdout. Fires when --verbose is set
  # or when the current command is a mutating operation (install, add, nuke, etc.).
  _pm_log() {
    if (( VERBOSE )) || [[ -t 1 && "$COMMAND" =~ ^(install|ci|nuke|add|rm|remove|uninstall)$ ]]; then
      print -P "%F{blue}Executing:%f %F{cyan}(cd ${(qq)ROOT_DIR} && $1 ${(qq)@:2})%f"
    fi
  }

  # _pm_get_version
  # Return the active package manager's version string. Result is cached in
  # PM_VERSION_CACHE to avoid repeated subprocess calls per invocation.
  _pm_get_version() {
    [[ -z "$PM_VERSION_CACHE" ]] && PM_VERSION_CACHE=$(command "$PM" --version 2>/dev/null || print "unknown")
    print "$PM_VERSION_CACHE"
  }

  # _pm_ensure <binary> [install-cmd...]
  # Verify <binary> exists on PATH. If missing, attempt installation via the
  # provided command, respecting --yes, --no-prompt, and CI/non-interactive modes.
  # If no install command is given, prints an error and returns 1 (no prompting).
  _pm_ensure() {
    local bin="$1"; shift
    command -v "$bin" &>/dev/null && return 0
    # No install command provided — report the missing binary and bail
    if (( $# == 0 )); then
      print -P -u2 "%F{red}Error:%f '$bin' is not installed. Please install it manually."
      return 1
    fi
    if (( ASSUME_YES )); then
      _pm_log "bootstrap" "$@"
      "$@" || return 1
    elif (( NO_PROMPT )) || (( ! IS_INTERACTIVE )); then
      print -P -u2 "%F{red}Error:%f '$bin' missing. Manual install required (or use --yes)."
      return 1
    else
      read -q "choice?Install $bin now? (y/n) " || { print; return 1; }
      print; "$@"
    fi
  }

  # Runs $PM with given args, always from ROOT_DIR
  _pm_run() {
    # Verify the detected PM is installed; offer to auto-install pnpm and yarn via npm.
    # npm ships with Node.js and bun has a custom curl installer — both require manual setup.
    case $PM in
      pnpm) _pm_ensure pnpm npm install -g pnpm || return 1 ;;
      yarn) _pm_ensure yarn npm install -g yarn || return 1 ;;
      *) _pm_ensure "$PM" || return 1 ;;
    esac
    _pm_log "$PM" "$@"
    (cd "$ROOT_DIR" && command "$PM" "$@")
  }

  # Runs an arbitrary external command (e.g., ncu, npx, bunx) from ROOT_DIR
  _pm_cmd() {
    (( $# == 0 )) && { print -P -u2 "%F{red}Error:%f _pm_cmd called with no arguments"; return 2; }
    _pm_log "$1" "${@:2}"
    (cd "$ROOT_DIR" && command "$@")
  }

  # 4. Routing Logic
  case $COMMAND in
    i|install|ci)
      # 'ci' subcommand and --frozen flag both trigger a locked/immutable install
      local frozen=0
      [[ "$COMMAND" == "ci" ]] && frozen=1
      for a in "${ARGS[@]}"; do [[ "$a" == "--frozen" ]] && frozen=1; done

      if (( frozen )); then
        case $PM in
          npm) _pm_run ci "${ARGS[@]//--frozen/}" ;;
          pnpm|bun) _pm_run install --frozen-lockfile "${ARGS[@]//--frozen/}" ;;
          yarn)
            if [[ "$(_pm_get_version)" =~ ^1\. ]]; then _pm_run install --frozen-lockfile "${ARGS[@]//--frozen/}"
            else _pm_run install --immutable "${ARGS[@]//--frozen/}"; fi ;;
        esac
      else
        _pm_run install "${ARGS[@]}"
      fi ;;

    add)
      # Normalize flag variants (-D/--dev/--save-dev → "dev", etc.) before dispatching
      local flag="" final_args=()
      for a in "${ARGS[@]}"; do
        case $a in
          -D|--dev|--save-dev) flag="dev" ;;
          -P|--prod) flag="prod" ;;
          -O|--optional) flag="opt" ;;
          *) final_args+=("$a") ;;
        esac
      done
      case $PM in
        # npm uses 'install' (not 'add'); -D/-E/--save-optional are native flags
        npm)
          if [[ "$flag" == "dev" ]]; then _pm_run install -D "${final_args[@]}"
          elif [[ "$flag" == "opt" ]]; then _pm_run install --save-optional "${final_args[@]}"
          else _pm_run install "${final_args[@]}"; fi ;;
        # bun uses lowercase -d instead of -D for dev dependencies
        bun)
          if [[ "$flag" == "dev" ]]; then _pm_run add -d "${final_args[@]}"
          else _pm_run add "${final_args[@]}"; fi ;;
        pnpm|yarn)
          local p_flag="-D"
          [[ "$flag" == "opt" ]] && p_flag="--save-optional"
          [[ "$flag" == "prod" || -z "$flag" ]] && p_flag=""
          if [[ -n "$p_flag" ]]; then _pm_run add "$p_flag" "${final_args[@]}"
          else _pm_run add "${final_args[@]}"; fi ;;
      esac ;;

    up|update|upgrade)
      # Prefer ncu (npm-check-updates) for interactive upgrades when available
      if ! command -v ncu &>/dev/null; then
        _pm_ensure "ncu" npm install -g npm-check-updates || {
          case $PM in
            pnpm) _pm_run up -i ;;
            yarn) [[ "$(_pm_get_version)" =~ ^1\. ]] && _pm_run upgrade-interactive --latest || _pm_run up -i ;;
            *) _pm_run update "${ARGS[@]}" ;;
          esac
          return 0
        }
      fi
      _pm_cmd ncu -i "${ARGS[@]}" ;;

    exec|x)
      (( ${#ARGS} == 0 )) && { _pm_help; return 1; }
      # Binary installed locally — invoke via the manager's exec subcommand
      if [[ -f "$ROOT_DIR/node_modules/.bin/${ARGS[1]}" ]]; then
        case $PM in
          npm|yarn|pnpm) _pm_run exec "${ARGS[@]}" ;;
          bun) _pm_run "${ARGS[@]}" ;;
        esac
      else
        # Binary not installed — fetch and run on-demand
        # npm has no dlx; always uses npx. yarn v1 also lacks dlx.
        case $PM in
          npm)
            # npx ships with npm 5.2+; verify it's available before calling
            _pm_ensure npx || return 1
            _pm_cmd npx "${ARGS[@]}" ;;
          yarn)
            if [[ "$(_pm_get_version)" =~ ^1\. ]]; then
              _pm_ensure npx || return 1
              _pm_cmd npx "${ARGS[@]}"
            else
              _pm_run dlx "${ARGS[@]}"
            fi ;;
          pnpm) _pm_run dlx "${ARGS[@]}" ;;
          bun)
            # bunx ships with bun; verify it's on PATH before calling
            _pm_ensure bunx || return 1
            _pm_cmd bunx "${ARGS[@]}" ;;
        esac
      fi ;;

    nuke)
      # Safety: refuse to operate on system-critical or insufficiently deep paths
      local home_real depth
      home_real="$(cd "$HOME" && pwd -P)"
      depth=$(print "$ROOT_DIR" | tr -cd '/' | wc -c)
      [[ "$ROOT_DIR" == "/" || "$ROOT_DIR" == "$home_real" || $depth -lt 3 ]] && { print -P -u2 "%F{red}Error:%f Root too shallow: $ROOT_DIR"; return 1; }
      [[ ! -f "$ROOT_DIR/package.json" ]] && { print -P -u2 "%F{red}Error:%f No package.json found."; return 1; }

      print -P "%F{red}☢  NUKE:%f Removing modules and locks in $ROOT_DIR"
      if (( ! ASSUME_YES )); then
        print -n "Type project name '$(basename "$ROOT_DIR")' to confirm: "
        read -r confirm
        [[ "$confirm" != "$(basename "$ROOT_DIR")" ]] && { print "Aborted."; return 1; }
      fi
      if (cd "$ROOT_DIR" && rm -rf node_modules package-lock.json yarn.lock pnpm-lock.yaml bun.lockb bun.lock); then
        _pm_run install
      else
        print -P -u2 "%F{red}Error:%f Failed to delete files. Check permissions."
        return 1
      fi ;;

    doctor)
      print -P "%F{blue}--- PM DOCTOR (v$PM_WRAPPER_VERSION) ---%f"
      print "Environment:  Node $(node -v 2>/dev/null || print 'missing'), PM: $PM ($(_pm_get_version))"
      print "Context:      Root: $ROOT_DIR"
      print "              Reason: $SELECTION_REASON"
      [[ ${#ALL_LOCKS_FOUND[@]} -gt 1 ]] && print -P "%F{yellow}⚠ WARNING:%f Multiple lockfiles: ${ALL_LOCKS_FOUND[*]}"
      ;;

    *)
      # Check if COMMAND is a package.json script; otherwise pass it through to $PM
      local has_script="false"
      if [[ -f "$PKG_DIR/package.json" ]]; then
        # High-performance grep check before Node process overhead
        if grep -q "\"$COMMAND\":" "$PKG_DIR/package.json" 2>/dev/null; then
          has_script="$(node -e 'try { const s = require(process.argv[1]).scripts; console.log(!!(s && (process.argv[2] in s))); } catch { console.log(false); }' "$PKG_DIR/package.json" "$COMMAND")"
        fi
      fi
      if [[ "$has_script" == "true" ]]; then
        # npm and pnpm require an explicit 'run' prefix; yarn and bun do not
        if [[ "$PM" =~ ^(npm|pnpm)$ ]]; then _pm_run run "$COMMAND" "${ARGS[@]}"
        else _pm_run "$COMMAND" "${ARGS[@]}"; fi
      else
        _pm_run "$COMMAND" "${ARGS[@]}"
      fi ;;
  esac
}

# _pm_help
# Print usage information to stdout.
_pm_help() {
  print -P "%F{blue}pm%f - Universal Package Manager Wrapper (v$PM_WRAPPER_VERSION)"
  print "Usage: pm [options] <command> [args]\n"
  print "Options:"
  print "  -y, --yes            Force yes for all prompts (auto-set in CI / non-TTY)"
  print "  --no-prompt          Fail immediately if interaction would be required"
  print "  -v, --verbose        Print each command before executing"
  print "  -V, --version        Print wrapper version and exit"
  print "  --                   Stop parsing global flags\n"
  print "Commands:"
  print "  i, install           Install all dependencies at project root"
  print "  ci, install --frozen Install with locked/immutable lockfile"
  print "  add [-D|-P|-O]       Add a package  (-D dev, -P prod, -O optional)"
  print "  rm, remove           Remove a package"
  print "  up, update, upgrade  Interactive update (prefers ncu)"
  print "  x, exec              Execute a binary (npx / pnpm dlx / yarn dlx / bunx)"
  print "  nuke                 Wipe node_modules + lockfiles and reinstall"
  print "  doctor               Show environment diagnostics and PM selection reason"
}

# _pm_completion
# Zsh tab-completion handler for pm. Offers both package.json script names
# and built-in subcommands as completion candidates.
_pm_completion() {
  emulate -L zsh
  local -a subcommands scripts
  local PKG_DIR="$PWD" found_pkg=0 current="$PWD"
  while [[ "$current" != "/" ]]; do
    [[ -f "$current/package.json" && $found_pkg -eq 0 ]] && { PKG_DIR="$current"; found_pkg=1; break; }
    current="${current:h}"
  done
  subcommands=(
    'i:Install' 'install:Install'
    'ci:Install (frozen)'
    'add:Add'
    'rm:Remove' 'remove:Remove'
    'up:Update' 'update:Update' 'upgrade:Update'
    'x:Execute' 'exec:Execute'
    'nuke:Clean'
    'doctor:Doctor'
  )

  if [[ -f "$PKG_DIR/package.json" ]]; then
    if command -v jq &>/dev/null; then
      scripts=(${(f)"$(jq -r '.scripts | keys[]?' "$PKG_DIR/package.json" 2>/dev/null)"})
    elif command -v node &>/dev/null; then
      scripts=(${(z)"$(node -e 'try { console.log(Object.keys(require(process.argv[1]).scripts||{}).join(" ")) } catch {}' "$PKG_DIR/package.json")"})
    fi
    scripts=("${scripts[@]//:/\\:}")
  fi
  _alternative 'scripts:scripts: _describe -t scripts "scripts" scripts' 'commands:commands: _describe -t commands "subcommands" subcommands'
}

compdef _pm_completion pm
