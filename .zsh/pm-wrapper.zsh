# ==============================================================================
# pm - Universal Package Manager Wrapper (v3.7)
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
  emulate -L zsh
  setopt local_options no_unset pipefail

  local VERSION="3.7"
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
        -V|--version) echo "pm wrapper v$VERSION"; return 0 ;;
        -h|--help|help) _pm_help; return 0 ;;
        *) ARGS+=("$arg") ;;
      esac
    else
      ARGS+=("$arg")
    fi
  done

  # 3. Context Discovery (Consolidated Logic)
  _pm_discover() {
    local current="$PWD"
    local found_pkg=0
    while [[ "$current" != "/" ]]; do
      [[ -f "$current/package.json" && $found_pkg -eq 0 ]] && { PKG_DIR="$current"; found_pkg=1; }
      
      # Priority PM Check
      if [[ -z "$PM" ]]; then
        if [[ -f "$current/pnpm-lock.yaml" ]]; then PM="pnpm"; SELECTION_REASON="lockfile (pnpm-lock.yaml) at $current"
        elif [[ -f "$current/bun.lockb" || -f "$current/bun.lock" ]]; then PM="bun"; SELECTION_REASON="lockfile (bun.lock) at $current"
        elif [[ -f "$current/yarn.lock" ]]; then PM="yarn"; SELECTION_REASON="lockfile (yarn.lock) at $current"
        elif [[ -f "$current/package-lock.json" ]]; then PM="npm"; SELECTION_REASON="lockfile (package-lock.json) at $current"
        fi
        [[ -n "$PM" ]] && ROOT_DIR="$current"
      fi

      # Gather all locks for Doctor
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

  COMMAND=${ARGS[1]:-install}
  ARGS=("${ARGS[@]:1}")

  # --- Helpers ---

  _pm_log() {
    if (( VERBOSE )) || [[ -t 1 && "$COMMAND" =~ ^(install|ci|nuke|add|rm|remove|uninstall)$ ]]; then
      print -P "%F{blue}Executing:%f %F{cyan}(cd ${(qq)ROOT_DIR} && $1 ${(qq)@:2})%f"
    fi
  }

  _pm_get_version() {
    [[ -z "$PM_VERSION_CACHE" ]] && PM_VERSION_CACHE=$(command "$PM" --version 2>/dev/null || echo "unknown")
    echo "$PM_VERSION_CACHE"
  }

  _pm_ensure() {
    local bin="$1"; shift
    command -v "$bin" &>/dev/null && return 0
    if (( ASSUME_YES )); then
      _pm_log "bootstrap" "$@"
      "$@" || return 1
    elif (( NO_PROMPT )) || (( ! IS_INTERACTIVE )); then
      print -P -u2 "%F{red}Error:%f '$bin' missing. Manual install required (or use --yes)."
      return 1
    else
      read -q "choice?Install $bin now? (y/n) " || { echo; return 1; }
      echo; "$@"
    fi
  }

  _pm_run() { _pm_log "$PM" "$@"; (cd "$ROOT_DIR" && command "$PM" "$@") }

  # 4. Routing Logic
  case $COMMAND in
    i|install|ci)
      local frozen=0
      [[ "$COMMAND" == "ci" ]] && frozen=1
      for a in "${ARGS[@]}"; do [[ "$a" == "--frozen" ]] && frozen=1; done

      if (( frozen )); then
        case $PM in
          npm) _pm_run ci "${ARGS[@]//--frozen/}" ;;
          pnpm) _pm_run install --frozen-lockfile "${ARGS[@]//--frozen/}" ;;
          bun) _pm_run install --frozen-lockfile "${ARGS[@]//--frozen/}" ;;
          yarn) 
            if [[ "$(_pm_get_version)" =~ ^1\. ]]; then _pm_run install --frozen-lockfile "${ARGS[@]//--frozen/}"
            else _pm_run install --immutable "${ARGS[@]//--frozen/}"; fi ;;
        esac
      else
        _pm_run install "${ARGS[@]}"
      fi ;;

    add)
      local type_flag="" final_args=()
      for a in "${ARGS[@]}"; do
        case $a in
          -D|--dev|--save-dev) type_flag="dev" ;;
          -P|--prod) type_flag="prod" ;;
          -O|--optional) type_flag="opt" ;;
          *) final_args+=("$a") ;;
        esac
      done
      case $PM in
        npm) [[ "$type_flag" == "dev" ]] && _pm_run install -D "${final_args[@]}" || _pm_run install "${final_args[@]}" ;;
        bun) [[ "$type_flag" == "dev" ]] && _pm_run add -d "${final_args[@]}" || _pm_run add "${final_args[@]}" ;;
        pnpm) 
          [[ "$type_flag" == "dev" ]] && _pm_run add -D "${final_args[@]}" 
          [[ "$type_flag" == "opt" ]] && _pm_run add --save-optional "${final_args[@]}"
          [[ "$type_flag" == "prod" ]] && _pm_run add "${final_args[@]}" ;;
        *) [[ "$type_flag" == "dev" ]] && _pm_run add -D "${final_args[@]}" || _pm_run add "${final_args[@]}" ;;
      esac ;;

    up|update|upgrade)
      if command -v ncu &>/dev/null; then _pm_run ncu -i "${ARGS[@]}"
      else
        case $PM in
          pnpm) _pm_run up -i ;;
          yarn) [[ "$(_pm_get_version)" =~ ^1\. ]] && _pm_run upgrade-interactive --latest || _pm_run up -i ;;
          *) _pm_run update "${ARGS[@]}" ;;
        esac
      fi ;;

    exec|x)
      # Optimization: If bin exists in local node_modules, use 'exec' style
      if [[ -f "$ROOT_DIR/node_modules/.bin/${ARGS[1]:-}" ]]; then
        case $PM in
          npm|yarn) _pm_run "$@" ;; # yarn/npm run local bins naturally
          pnpm) _pm_run exec "${ARGS[@]}" ;;
          bun) _pm_run "${ARGS[@]}" ;;
        esac
      else
        case $PM in
          npm|yarn) [[ "$(_pm_get_version)" =~ ^1\. ]] && (cd "$ROOT_DIR" && npx "${ARGS[@]}") || _pm_run dlx "${ARGS[@]}" ;;
          pnpm) _pm_run dlx "${ARGS[@]}" ;;
          bun) (cd "$ROOT_DIR" && bunx "${ARGS[@]}") ;;
        esac
      fi ;;

    nuke)
      local home_real="$(cd "$HOME" && pwd -P)"
      local depth=$(echo "$ROOT_DIR" | tr -cd '/' | wc -c)
      [[ "$ROOT_DIR" == "/" || "$ROOT_DIR" == "$home_real" || $depth -lt 3 ]] && { print -P -u2 "%F{red}Error:%f Root too shallow for nuke: $ROOT_DIR"; return 1; }
      [[ ! -f "$ROOT_DIR/package.json" ]] && { print -P -u2 "%F{red}Error:%f No package.json in $ROOT_DIR."; return 1; }

      print -P "%F{red}☢  NUKE:%f The following will be removed in $ROOT_DIR:"
      echo "   - node_modules/"
      echo "   - lockfiles: package-lock.json, yarn.lock, pnpm-lock.yaml, bun.lockb"
      
      if (( ! ASSUME_YES )); then
        echo -n "Confirm project name '$(basename "$ROOT_DIR")': "
        read confirm
        [[ "$confirm" != "$(basename "$ROOT_DIR")" ]] && return 1
      fi
      (cd "$ROOT_DIR" && rm -rf node_modules package-lock.json yarn.lock pnpm-lock.yaml bun.lockb bun.lock)
      _pm_run install ;;

    doctor)
      print -P "%F{blue}--- PM DOCTOR (v$VERSION) ---%f"
      echo "Environment:  Node $(node -v), PM: $PM ($(_pm_get_version))"
      echo "Context:      Root: $ROOT_DIR"
      echo "              Reason: $SELECTION_REASON"
      [[ ${#ALL_LOCKS_FOUND[@]} -gt 1 ]] && print -P "%F{yellow}⚠ WARNING:%f Multiple lockfiles found: ${ALL_LOCKS_FOUND[*]}"
      ;;

    *)
      # Script routing using Node for speed/availability
      local has_script=$(node -e 'try { const s = require(process.argv[1]).scripts; console.log(!!(s && process.argv[2] in s)); } catch { console.log(false) }' "$PKG_DIR/package.json" "$COMMAND" 2>/dev/null)
      if [[ "$has_script" == "true" ]]; then
        [[ "$PM" =~ ^(npm|pnpm)$ ]] && _pm_run run "$COMMAND" "${ARGS[@]}" || _pm_run "$COMMAND" "${ARGS[@]}"
      else
        _pm_run "$COMMAND" "${ARGS[@]}"
      fi ;;
  esac
}

_pm_help() {
  print -P "%F{blue}pm%f - Universal Package Manager Wrapper (v3.6)"
  echo "Usage: pm [options] <command> [args]"
  echo ""
  echo "Options:"
  echo "  -y, --yes      Force 'yes' (Auto-set in CI or non-TTY)"
  echo "  -v, --verbose  Show execution commands"
  echo "  -V, --version  Show wrapper version"
  echo "  --             Stop parsing global flags"
  echo ""
  echo "Commands:"
  echo "  i, install     Install dependencies at root"
  echo "  add [-D]       Add package (auto-maps -D/--dev)"
  echo "  rm, remove     Remove package"
  echo "  up, update     Interactive update (prefers NCU)"
  echo "  x, exec        Execute binary (npx/dlx/bunx)"
  echo "  nuke           Wipe node_modules/locks and reinstall"
  echo "  doctor         Show diagnostics & selection reason"
}

_pm_completion() {
  emulate -L zsh
  local -a subcommands scripts
  local PKG_DIR="$PWD" found_pkg=0
  local current="$PWD"
  
  while [[ "$current" != "/" ]]; do
    [[ -f "$current/package.json" && $found_pkg -eq 0 ]] && { PKG_DIR="$current"; found_pkg=1; break; }
    current="${current:h}"
  done
  
  subcommands=(
    'i:Install' 'install:Install' 'add:Add' 'rm:Remove' 'remove:Remove'
    'up:Update' 'update:Update' 'x:Execute' 'exec:Execute' 'nuke:Clean' 'doctor:Doctor'
  )

  if [[ -f "$PKG_DIR/package.json" ]]; then
    if command -v jq &>/dev/null; then
      scripts=($(jq -r '.scripts | keys[]?' "$PKG_DIR/package.json" 2>/dev/null))
    elif command -v node &>/dev/null; then
      scripts=($(node -e 'try { console.log(Object.keys(require(process.argv[1]).scripts||{}).join(" ")) } catch {}' "$PKG_DIR/package.json"))
    fi
    scripts=("${scripts[@]//:/\\:}")
  fi
  _alternative 'scripts:scripts: _describe -t scripts "scripts" scripts' 'commands:commands: _describe -t commands "subcommands" subcommands'
}

compdef _pm_completion pm
