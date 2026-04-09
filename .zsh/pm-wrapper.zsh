# ==============================================================================
# pm - Universal Package Manager Wrapper (v3.3)
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
#   pm                -> Install dependencies at project root.
#   pm add [-D] <pkg> -> Add package (properly mapping Dev flags).
#   pm x <cmd>        -> Unified 'exec' (npx / pnpm dlx / yarn dlx / bunx).
#   pm up             -> Interactive update (prefers ncu, falls back to native).
#   pm nuke           -> Wipe node_modules/locks and reinstall (Safe-guarded).
#   pm doctor         -> Diagnostic report of the current environment.
#   pm [script]       -> Executes package.json scripts with auto-run logic.
#
# OPTIONS:
#   -y, --yes         -> Force 'yes' for all prompts (Automatic in CI).
#   -h, --help        -> Display usage and help.
# ==============================================================================

pm() {
  # Standardize environment and protect against user-specific shell options
  emulate -L zsh
  setopt local_options no_unset pipefail

  local PM="" COMMAND="" ROOT_DIR="$PWD" PKG_DIR="$PWD"
  local ARGS=()
  local FORCE_YES=0
  local VERBOSE=0
  local PARSING_FLAGS=1
  local -a ALL_LOCKS_FOUND=()

  # 1. CI & TTY Detection (Set FORCE_YES if non-interactive)
  [[ "${CI:-}" =~ ^(1|true|yes|TRUE|True)$ ]] && FORCE_YES=1
  [[ ! -t 0 ]] && FORCE_YES=1 

  # 2. Global Flag Parsing
  for arg in "$@"; do
    if (( PARSING_FLAGS )); then
      case $arg in
        --) PARSING_FLAGS=0 ;;
        -y|--yes) FORCE_YES=1 ;;
        -v|--verbose) VERBOSE=1 ;;
        -h|--help|help) _pm_help; return 0 ;;
        *) ARGS+=("$arg") ;;
      esac
    else
      ARGS+=("$arg")
    fi
  done

  # 3. Context Discovery (Climbing to Root)
  local current="$PWD"
  local found_pkg=0

  while [[ "$current" != "/" ]]; do
    [[ -f "$current/package.json" && $found_pkg -eq 0 ]] && { PKG_DIR="$current"; found_pkg=1; }
    
    if [[ -z "$PM" ]]; then
      if [[ -f "$current/pnpm-lock.yaml" ]]; then PM="pnpm"
      elif [[ -f "$current/bun.lockb" || -f "$current/bun.lock" ]]; then PM="bun"
      elif [[ -f "$current/yarn.lock" ]]; then PM="yarn"
      elif [[ -f "$current/package-lock.json" ]]; then PM="npm"
      fi
      [[ -n "$PM" ]] && ROOT_DIR="$current"
    fi

    [[ -f "$current/pnpm-lock.yaml" ]] && ALL_LOCKS_FOUND+=("pnpm@$current")
    [[ -f "$current/bun.lockb" || -f "$current/bun.lock" ]] && ALL_LOCKS_FOUND+=("bun@$current")
    [[ -f "$current/yarn.lock" ]] && ALL_LOCKS_FOUND+=("yarn@$current")
    [[ -f "$current/package-lock.json" ]] && ALL_LOCKS_FOUND+=("npm@$current")
    
    [[ -d "$current/.git" && -z "$PM" ]] && { ROOT_DIR="$current"; break; }
    current="${current:h}"
  done

  ROOT_DIR=$ROOT_DIR:A
  local HOME_REAL=$HOME:A

  COMMAND=${ARGS[1]:-install}
  ARGS=("${ARGS[@]:1}") 
  [[ -z "$PM" ]] && PM="npm" 

  # --- Internal Helpers ---

  _pm_log() {
    if (( VERBOSE )) || [[ -t 1 && "$COMMAND" =~ ^(install|nuke|add|rm|remove|uninstall)$ ]]; then
      print -P "%F{blue}Executing:%f %F{cyan}(cd ${(qq)ROOT_DIR} && $1 ${(qq)@:2})%f"
    fi
  }

  _pm_run() { _pm_log "$PM" "$@"; (cd "$ROOT_DIR" && command "$PM" "$@") }
  _pm_cmd() { _pm_log "$@" ; (cd "$ROOT_DIR" && command "$@") }

  _pm_ensure() {
    local bin="$1"; shift
    if ! command -v "$bin" &> /dev/null; then
      if (( FORCE_YES )); then
        [[ ! -t 0 ]] && { print -P -u2 "%F{red}Error:%f Required tool '$bin' missing in non-interactive environment."; return 1; }
        return 0
      fi
      read -q "choice?Install $bin now? (y/n) " || { echo; return 1; }
      echo; "$@" 
    fi
  }

  # 4. Toolchain Bootstrap
  if ! command -v "$PM" &> /dev/null; then
    case $PM in
      npm) print -P -u2 "%F{red}Error:%f npm not found. Install Node.js."; return 1 ;;
      yarn|pnpm) 
        command -v npm &>/dev/null || { print -P -u2 "%F{red}Error:%f npm missing; cannot bootstrap $PM."; return 1; }
        [[ "$PM" == "yarn" ]] && _pm_ensure yarn npm install -g yarn || _pm_ensure pnpm npm install -g pnpm || return 1
        ;;
      bun) _pm_ensure bun bash -lc 'curl -fsSL https://bun.sh/install | bash' || return 1 ;;
    esac
  fi

  # 5. Command Routing
  case $COMMAND in
    i|install) _pm_run install "${ARGS[@]}" ;;
    
    add)
      local is_dev=0 final_args=() parsing_add=1
      for a in "${ARGS[@]}"; do
        if (( parsing_add )); then
          case $a in
            --) parsing_add=0 ;;
            -D|--dev|--save-dev) is_dev=1 ;;
            *) final_args+=("$a") ;;
          esac
        else
          final_args+=("$a")
        fi
      done
      case $PM in
        npm) (( is_dev )) && _pm_run install -D "${final_args[@]}" || _pm_run install "${final_args[@]}" ;;
        bun) (( is_dev )) && _pm_run add -d "${final_args[@]}" || _pm_run add "${final_args[@]}" ;;
        *)   (( is_dev )) && _pm_run add -D "${final_args[@]}" || _pm_run add "${final_args[@]}" ;;
      esac ;;

    rm|remove|uninstall)
      [[ "$PM" == "npm" ]] && _pm_run uninstall "${ARGS[@]}" || _pm_run remove "${ARGS[@]}" ;;

    up|update|upgrade)
      if command -v ncu &>/dev/null; then 
        _pm_cmd ncu -i "${ARGS[@]}"
      else
        case $PM in
          pnpm) _pm_run up -i ;;
          yarn) [[ "$(command yarn --version)" =~ ^1\. ]] && _pm_run upgrade-interactive --latest || _pm_run up -i ;;
          *)    _pm_run update "${ARGS[@]}" ;;
        esac
      fi ;;

    exec|x)
      case $PM in
        npm)  _pm_cmd npx "${ARGS[@]}" ;;
        pnpm) _pm_run dlx "${ARGS[@]}" ;;
        yarn) [[ "$(command yarn --version)" =~ ^1\. ]] && _pm_cmd npx "${ARGS[@]}" || _pm_run dlx "${ARGS[@]}" ;;
        bun)  _pm_cmd bunx "${ARGS[@]}" ;;
      esac ;;

    nuke)
      [[ "$ROOT_DIR" == "/" || "$ROOT_DIR" == "$HOME_REAL" ]] && { print -P -u2 "%F{red}Error:%f Nuke refused on root/home."; return 1; }
      if (( ! FORCE_YES )); then
        local proj=$(basename "$ROOT_DIR")
        print -P "%F{red}☢ DANGER:%f Wipe node_modules & locks in $ROOT_DIR?"
        echo -n "Type '$proj' to confirm: "
        read confirm
        [[ "$confirm" != "$proj" ]] && { print -P "\nAborted."; return 1; }
      fi
      (cd "$ROOT_DIR" && rm -rf -- node_modules package-lock.json yarn.lock pnpm-lock.yaml bun.lockb bun.lock && command "$PM" install) ;;

    doctor)
      print -P "%F{blue}--- PM DOCTOR ---%f"
      echo "Project Root: $ROOT_DIR"
      echo "Manager:      $PM ($( command "$PM" --version 2>/dev/null ))"
      [[ ! -d "$ROOT_DIR/node_modules" ]] && print -P "%F{red}✗ node_modules missing%f" || echo "✓ node_modules present"
      [[ ${#ALL_LOCKS_FOUND[@]} -gt 0 ]] && echo "All Locks:    ${ALL_LOCKS_FOUND[*]}"
      ;;

    *) 
      local HAS_SCRIPT=0
      if [[ -f "$PKG_DIR/package.json" ]]; then
        if command -v jq &>/dev/null; then
          jq -e --arg cmd "$COMMAND" '.scripts[$cmd] != null' "$PKG_DIR/package.json" >/dev/null 2>&1 && HAS_SCRIPT=1
        elif command -v node &>/dev/null; then
          [[ $(node -e 'try { const s = require(process.argv[1]).scripts; console.log(!!(s && process.argv[2] in s)); } catch { console.log(false) }' "$PKG_DIR/package.json" "$COMMAND") == "true" ]] && HAS_SCRIPT=1
        fi
      fi

      if (( HAS_SCRIPT )); then
        [[ "$PM" =~ ^(npm|pnpm)$ ]] && _pm_run run "$COMMAND" "${ARGS[@]}" || _pm_run "$COMMAND" "${ARGS[@]}"
      else
        _pm_run "$COMMAND" "${ARGS[@]}"
      fi ;;
  esac
}

_pm_help() {
  print -P "%F{blue}pm%f - Universal Package Manager Wrapper (v3.3)"
  echo "Usage: pm [options] <command> [args]"
  echo ""
  echo "Options:"
  echo "  -y, --yes      Force 'yes' (Auto-set in CI or non-TTY)"
  echo "  -v, --verbose  Show execution commands"
  echo ""
  echo "Commands:"
  echo "  i, install     Install dependencies at root"
  echo "  add [-D]       Add package (auto-maps flags)"
  echo "  rm, remove     Remove package"
  echo "  up, update     Interactive update (prefers NCU)"
  echo "  x, exec        Execute binary (npx/dlx/bunx)"
  echo "  nuke           Wipe and reinstall (Safe-guarded)"
  echo "  doctor         Check environment health"
  echo "  [script]       Run package.json scripts"
}

_pm_completion() {
  emulate -L zsh
  local -a subcommands scripts
  local ROOT_DIR="$PWD" PKG_DIR="$PWD"
  while [[ "$ROOT_DIR" != "/" ]]; do
    [[ -f "$ROOT_DIR/package.json" ]] && { PKG_DIR="$ROOT_DIR"; break; }
    ROOT_DIR="${ROOT_DIR:h}"
  done
  
  subcommands=(
    'i:Install dependencies' 'install:Install dependencies'
    'add:Add package'
    'rm:Remove package' 'remove:Remove package' 'uninstall:Remove package'
    'up:Update packages' 'update:Update packages' 'upgrade:Update packages'
    'x:Execute binary' 'exec:Execute binary'
    'nuke:Clean reinstall'
    'doctor:Diagnostics'
  )

  if [[ -f "$PKG_DIR/package.json" ]]; then
    if command -v jq &>/dev/null; then
      scripts=($(jq -r '.scripts | keys[]?' "$PKG_DIR/package.json" 2>/dev/null))
    elif command -v node &>/dev/null; then
      scripts=($(node -e 'try { console.log(Object.keys(require(process.argv[1]).scripts||{}).join(" ")) } catch {}' "$PKG_DIR/package.json"))
    else
      scripts=($(sed -n '/"scripts": {/,/}/ s/^[[:space:]]*"\([^"]*\)":.*/\1/p' "$PKG_DIR/package.json" | grep -v "scripts"))
    fi
    scripts=("${scripts[@]//:/\\:}")
  fi
  _alternative 'scripts:scripts: _describe -t scripts "scripts" scripts' 'commands:commands: _describe -t commands "subcommands" subcommands'
}

compdef _pm_completion pm
