# ==============================================================================
# pm - Universal Package Manager Wrapper (v3.2)
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
  local FORCE_YES=false
  local PARSING_FLAGS=true

  # 1. CI Detection (Recognizes '1' or 'true')
  case "${CI:-}" in
    1|true|TRUE|True|yes|YES) FORCE_YES=true ;;
  esac

  # 2. Parse Global Flags (Stop parsing at --)
  for arg in "$@"; do
    if [[ "$PARSING_FLAGS" == true ]]; then
      case $arg in
        --) PARSING_FLAGS=false ;;
        -y|--yes|--no-prompt) FORCE_YES=true ;;
        -h|--help|help) _pm_help; return 0 ;;
        *) ARGS+=("$arg") ;;
      esac
    else
      ARGS+=("$arg")
    fi
  done

  # 3. Context Discovery (Walking up to project root)
  local current="$PWD"
  local found_pkg=false
  local locks_found=()

  while [[ "$current" != "/" ]]; do
    # Nearest package.json is our target for running scripts
    [[ -f "$current/package.json" && "$found_pkg" == false ]] && { PKG_DIR="$current"; found_pkg=true; }
    
    # Identify lockfiles at this level specifically
    local current_locks=()
    [[ -f "$current/pnpm-lock.yaml" ]] && current_locks+=("pnpm")
    [[ -f "$current/bun.lockb" || -f "$current/bun.lock" ]] && current_locks+=("bun")
    [[ -f "$current/yarn.lock" ]] && current_locks+=("yarn")
    [[ -f "$current/package-lock.json" ]] && current_locks+=("npm")

    if [[ ${#current_locks[@]} -gt 0 ]]; then
      locks_found=("${current_locks[@]}")
      PM="${locks_found[1]}" # Deterministic priority
      ROOT_DIR="$current"
      break
    elif [[ -d "$current/.git" ]]; then
      ROOT_DIR="$current" # Fallback boundary
      break 
    fi
    current="${current:h}"
  done

  # Extract command and slice remaining arguments safely
  COMMAND=${ARGS[1]:-install}
  ARGS=("${ARGS[@]:1}") 
  [[ -z "$PM" ]] && PM="npm" 

  # --- Internal Helpers ---

  # Helper: Execute via Package Manager (using qq for accurate debug logging)
  _pm_run() { 
    print -P "%F{blue}Executing:%f %F{cyan}(cd ${(qq)ROOT_DIR} && $PM ${(qq)@})%f"
    (cd "$ROOT_DIR" && command "$PM" "$@") 
  }

  # Helper: Execute raw command (npx, ncu, etc) without PM prefix
  _pm_cmd() { 
    print -P "%F{blue}Executing:%f %F{cyan}(cd ${(qq)ROOT_DIR} && ${(qq)@})%f"
    (cd "$ROOT_DIR" && command "$@") 
  }

  # Helper: Ensure tool exists without using 'eval'
  _pm_ensure() {
    local bin="$1"; shift
    if ! command -v "$bin" &> /dev/null; then
      if [[ "$FORCE_YES" == true ]]; then 
        print -P -u2 "%F{red}Error: Required tool '$bin' not found.%f"
        return 1
      fi
      read -q "choice?Install $bin now? (y/n) " || { echo; return 1; }
      echo
      "$@" 
    fi
    return 0
  }

  # 4. Toolchain Guard (Bootstrap checks)
  if ! command -v "$PM" &> /dev/null; then
    case $PM in
      npm) print -P -u2 "%F{red}Error:%f npm not found. Please install Node.js first."; return 1 ;;
      yarn|pnpm) 
        if ! command -v npm &>/dev/null; then
          print -P -u2 "%F{red}Error:%f Cannot install $PM because npm bootstrap is missing."
          return 1
        fi

        if [[ "$PM" == "yarn" ]]; then
          _pm_ensure yarn npm install -g yarn || return 1
        else
          _pm_ensure pnpm npm install -g pnpm || return 1
        fi
        ;;
      bun)  _pm_ensure bun bash -lc 'curl -fsSL https://bun.sh/install | bash' || return 1 ;;
    esac
  fi

  # 5. Main Command Logic
  case $COMMAND in
    # --- Installation ---
    i|install) _pm_run install "${ARGS[@]}" ;;
    
    add)
      local is_dev=false final_args=()
      for a in "${ARGS[@]}"; do [[ "$a" =~ ^(-D|--dev)$ ]] && is_dev=true || final_args+=("$a"); done
      case $PM in
        npm) [[ "$is_dev" == true ]] && _pm_run install -D "${final_args[@]}" || _pm_run install "${final_args[@]}" ;;
        bun) [[ "$is_dev" == true ]] && _pm_run add -d "${final_args[@]}" || _pm_run add "${final_args[@]}" ;;
        *)   [[ "$is_dev" == true ]] && _pm_run add -D "${final_args[@]}" || _pm_run add "${final_args[@]}" ;;
      esac ;;

    rm|remove|uninstall)
      [[ "$PM" == "npm" ]] && _pm_run uninstall "${ARGS[@]}" || _pm_run remove "${ARGS[@]}" ;;

    # --- Updates ---
    up|update|upgrade)
      if command -v ncu &>/dev/null; then 
        _pm_cmd ncu -i "${ARGS[@]}"
      else
        case $PM in
          pnpm) _pm_run up -i ;;
          yarn) 
            if [[ "$(command yarn --version)" =~ ^1\. ]]; then
              _pm_run upgrade-interactive --latest
            else
              _pm_run up -i
            fi ;;
          *) _pm_run update "${ARGS[@]}" ;;
        esac
      fi ;;

    # --- Exec (npx/dlx/bunx) ---
    exec|x)
      case $PM in
        npm)  _pm_cmd npx "${ARGS[@]}" ;;
        pnpm) _pm_run dlx "${ARGS[@]}" ;;
        yarn) 
          if [[ "$(command yarn --version)" =~ ^1\. ]]; then
            _pm_cmd npx "${ARGS[@]}"
          else
            _pm_run dlx "${ARGS[@]}"
          fi ;;
        bun)  _pm_cmd bunx "${ARGS[@]}" ;;
      esac ;;

    # --- Housekeeping ---
    nuke)
      [[ "$ROOT_DIR" == "/" || "$ROOT_DIR" == "$HOME" ]] && { print -P -u2 "%F{red}Error: Refusing to nuke system root or home.%f"; return 1; }
      if [[ "$FORCE_YES" == false ]]; then
        local project_name=$(basename "$ROOT_DIR")
        print -P "%F{red}☢ DANGER:%f Wipe node_modules & lockfiles in $ROOT_DIR?"
        echo -n "Type '$project_name' to confirm: "
        read confirm
        [[ "$confirm" != "$project_name" ]] && { print -P "\n%F{yellow}Aborted.%f"; return 1; }
      fi
      (cd "$ROOT_DIR" && rm -rf -- node_modules package-lock.json yarn.lock pnpm-lock.yaml bun.lockb bun.lock && command "$PM" install) ;;

    doctor)
      print -P "%F{blue}--- PM DOCTOR ---%f"
      echo "Working Dir:  $PWD"
      echo "Project Root: $ROOT_DIR"
      echo "Manager:      $PM ($( command "$PM" --version 2>/dev/null || echo 'Not Found' ))"
      [[ ! -d "$ROOT_DIR/node_modules" ]] && print -P "%F{red}✗ node_modules missing%f" || echo "✓ node_modules present"
      [[ ${#locks_found[@]} -gt 0 ]] && echo "Lockfiles:    ${locks_found[*]}"
      ;;

    *) 
      # 6. Script Execution (Hardened with process.argv)
      local SCRIPT_EXISTS=false
      if [[ -f "$PKG_DIR/package.json" ]]; then
        if command -v jq &>/dev/null; then
          if jq -e --arg cmd "$COMMAND" '.scripts[$cmd] != null' "$PKG_DIR/package.json" >/dev/null 2>&1; then
            SCRIPT_EXISTS=true
          fi
        elif command -v node &>/dev/null; then
          SCRIPT_EXISTS=$(node -e 'try { const s = require(process.argv[1]).scripts; console.log(!!(s && process.argv[2] in s)); } catch { console.log(false) }' \
            "$PKG_DIR/package.json" "$COMMAND")
        else
          # Fallback to sed-based scripts-block restriction
          sed -n '/"scripts": {/,/}/p' "$PKG_DIR/package.json" | grep -q "\"$COMMAND\":" && SCRIPT_EXISTS=true
        fi
      fi

      if [[ "$SCRIPT_EXISTS" == "true" ]]; then
        [[ "$PM" == "npm" || "$PM" == "pnpm" ]] && _pm_run run "$COMMAND" "${ARGS[@]}" || _pm_run "$COMMAND" "${ARGS[@]}"
      else
        _pm_run "$COMMAND" "${ARGS[@]}"
      fi ;;
  esac
}

# --- Usage ---
_pm_help() {
  print -P "%F{blue}pm%f - Universal Package Manager Wrapper (v3.2)"
  echo "Usage: pm [options] <command> [args]"
  echo ""
  echo "Commands:"
  echo "  i, install    Install all dependencies"
  echo "  add [-D]      Add package (maps Dev flag correctly)"
  echo "  rm, remove    Remove package"
  echo "  up, update    Interactive upgrade"
  echo "  x, exec       Run binaries (npx/dlx/bunx)"
  echo "  nuke          Deep clean and reinstall"
}

# --- Autocompletion ---
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
