# ==============================================================================
# pm - Universal Package Manager Wrapper (Industrial Grade)
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
  local PM="" COMMAND="" ROOT_DIR="$PWD" PKG_DIR="$PWD"
  local ARGS=()
  local FORCE_YES=false
  [[ "$CI" == "1" ]] && FORCE_YES=true

  # Colors
  typeset -A c=(
    [cyan]=$'\e[0;36m' [green]=$'\e[0;32m' [yellow]=$'\e[1;33m' 
    [blue]=$'\e[1;34m' [red]=$'\e[0;31m' [reset]=$'\e[0m'
  )

  # 1. Parse Global Flags
  for arg in "$@"; do
    case $arg in
      -y|--yes|--no-prompt) FORCE_YES=true ;;
      -h|--help|help) _pm_help; return 0 ;;
      *) ARGS+=("$arg") ;;
    esac
  done

  # 2. Root & Manager Detection (Monorepo & Git Aware)
  local current="$PWD"
  local found_pkg=false
  while [[ "$current" != "/" ]]; do
    # Nearest package.json is our target for running scripts
    [[ -f "$current/package.json" && "$found_pkg" == false ]] && { PKG_DIR="$current"; found_pkg=true; }
    
    # Lockfiles define the Package Manager and the Project Root
    if [[ -f "$current/pnpm-lock.yaml" ]]; then PM="pnpm"; ROOT_DIR="$current"; break;
    elif [[ -f "$current/bun.lockb" || -f "$current/bun.lock" ]]; then PM="bun"; ROOT_DIR="$current"; break;
    elif [[ -f "$current/yarn.lock" ]]; then PM="yarn"; ROOT_DIR="$current"; break;
    elif [[ -f "$current/package-lock.json" ]]; then PM="npm"; ROOT_DIR="$current"; break;
    elif [[ -d "$current/.git" ]]; then ROOT_DIR="$current"; break; 
    fi
    current="${current:h}"
  done
  [[ -z "$PM" ]] && PM="npm" # Default to npm if no lockfile found

  # Helper: Execute in Root
  _pm_run() { 
    echo -e "${c[blue]}Executing:${c[reset]} ${c[cyan]}(cd $ROOT_DIR && $PM $*) ${c[reset]}"
    (cd "$ROOT_DIR" && eval "$PM $*") 
  }

  # Helper: Tool Ensure (Check if PM or utility is installed)
  _pm_ensure() {
    if ! command -v "$1" &> /dev/null; then
      if [[ "$FORCE_YES" == true ]]; then 
        echo -e "${c[red]}Error: $1 is not installed. Exiting (CI/Non-interactive).${c[reset]}"; return 1
      fi
      read -q "choice?Install $1 via '$2'? (y/n) " && echo "" && eval "$2" || return 1
    fi
    return 0
  }

  # 3. PM Installation Check
  local pm_install_cmd=""
  case $PM in
    npm)  pm_install_cmd="echo 'Please install Node.js manually.'" ;;
    yarn) pm_install_cmd="npm install -g yarn" ;;
    pnpm) pm_install_cmd="npm install -g pnpm" ;;
    bun)  pm_install_cmd="curl -fsSL https://bun.sh/install | bash" ;;
  esac
  _pm_ensure "$PM" "$pm_install_cmd" || return 1

  COMMAND=${ARGS[1]:-install}
  shift ARGS 2>/dev/null 

  # 4. Main Command Logic
  case $COMMAND in
    # --- Installation & Management ---
    i|install) _pm_run install "${ARGS[@]}" ;;
    
    add)
      local is_dev=false
      local final_args=()
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
      if command -v ncu &>/dev/null; then _pm_run ncu -i "${ARGS[@]}"
      else
        case $PM in
          pnpm) _pm_run up -i ;;
          yarn) _pm_run upgrade-interactive --latest ;;
          *)    _pm_run update "${ARGS[@]}" ;;
        esac
      fi ;;

    # --- Utilities ---
    exec|x)
      case $PM in
        npm) _pm_run npx "${ARGS[@]}" ;;
        pnpm) _pm_run dlx "${ARGS[@]}" ;;
        yarn) _pm_run dlx "${ARGS[@]}" ;;
        bun) _pm_run bunx "${ARGS[@]}" ;;
      esac ;;

    nuke)
      [[ "$ROOT_DIR" == "/" || "$ROOT_DIR" == "$HOME" ]] && { echo "Safety: Nuke refused on root/home."; return 1; }
      if [[ "$FORCE_YES" == false ]]; then
        local project_name=$(basename "$ROOT_DIR")
        echo -e "${c[red]}☢ DANGER:${c[reset]} Wipe node_modules & lockfiles in $ROOT_DIR?"
        echo -n "Type '$project_name' to confirm: "
        read confirm
        [[ "$confirm" != "$project_name" ]] && { echo "Aborted."; return 1; }
      fi
      (cd "$ROOT_DIR" && rm -rf node_modules package-lock.json yarn.lock pnpm-lock.yaml bun.lockb bun.lock && $PM install) ;;

    doctor)
      echo -e "${c[blue]}--- PM DOCTOR ---${c[reset]}"
      echo "Working Dir: $PWD"
      echo "Project Root: $ROOT_DIR"
      echo "Manager: $PM ($( $PM --version 2>/dev/null || echo 'Not Found' ))"
      [[ ! -d "$ROOT_DIR/node_modules" ]] && echo -e "${c[red]}✗ node_modules missing${c[reset]}" || echo "✓ node_modules present"
      command -v ncu &>/dev/null && echo "✓ ncu available" || echo "opt: ncu not found"
      ;;

    *) # Run Scripts (with package.json verification)
      local SCRIPT_EXISTS=false
      if command -v node &>/dev/null; then
        SCRIPT_EXISTS=$(node -e "try { const s = require('$PKG_DIR/package.json').scripts; console.log(s && '$COMMAND' in s) } catch { console.log(false) }")
      else
        grep -q "\"$COMMAND\":" "$PKG_DIR/package.json" && SCRIPT_EXISTS=true
      fi

      if [[ "$SCRIPT_EXISTS" == "true" ]]; then
        [[ "$PM" == "npm" || "$PM" == "pnpm" ]] && _pm_run run "$COMMAND" "${ARGS[@]}" || _pm_run "$COMMAND" "${ARGS[@]}"
      else
        _pm_run "$COMMAND" "${ARGS[@]}"
      fi ;;
  esac
}

_pm_help() {
  echo "pm - The Unified Package Manager Wrapper"
  echo "Usage: pm [options] <command> [args]"
  echo ""
  echo "Options:"
  echo "  -y, --yes     Force yes (CI mode)"
  echo ""
  echo "Commands:"
  echo "  i, install    Install dependencies at project root"
  echo "  add [-D]      Add package (standardized flags)"
  echo "  rm, remove    Remove package"
  echo "  up, update    Update packages (interactive via ncu)"
  echo "  x, exec       Run binaries (npx/dlx/bunx)"
  echo "  nuke          Clean slate reinstall (Guarded)"
  echo "  doctor        Environment diagnostics"
  echo "  [script]      Run package.json scripts"
}

#######################################
# Root-Aware Zsh Autocompletion
#######################################

_pm_completion() {
  local -a subcommands scripts
  local ROOT_DIR="$PWD" PKG_DIR="$PWD"
  
  while [[ "$ROOT_DIR" != "/" ]]; do
    [[ -f "$ROOT_DIR/package.json" ]] && { PKG_DIR="$ROOT_DIR"; break; }
    ROOT_DIR="${ROOT_DIR:h}"
  done

  subcommands=('i:Install' 'add:Add' 'rm:Remove' 'up:Update' 'nuke:Clean' 'x:Exec' 'doctor:Doctor' 'help:Help')

  if [[ -f "$PKG_DIR/package.json" ]]; then
    if command -v node &>/dev/null; then
      scripts=($(node -e "try { console.log(Object.keys(require('$PKG_DIR/package.json').scripts||{}).join(' ')) } catch {}" 2>/dev/null))
    else
      scripts=($(sed -n '/"scripts": {/,/}/ s/^[[:space:]]*"\([^"]*\)":.*/\1/p' "$PKG_DIR/package.json" | grep -v "scripts"))
    fi
    scripts=("${scripts[@]//:/\\:}")
  fi

  _alternative \
    'scripts:scripts: _describe -t scripts "scripts" scripts' \
    'commands:commands: _describe -t commands "subcommands" subcommands'
}

compdef _pm_completion pm
