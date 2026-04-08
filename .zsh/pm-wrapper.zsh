#!/usr/bin/env zsh

#######################################
# pm - Universal Package Manager Wrapper
#######################################

pm() {
  local PM=""
  local COMMAND=""
  local ROOT_DIR="$PWD"
  local FALLBACK_PM=""
  local FALLBACK_ROOT=""

  # Colors (using zsh associative array for cleaner access)
  typeset -A colors=(
    [cyan]=$'\e[0;36m' [green]=$'\e[0;32m' [yellow]=$'\e[1;33m'
    [blue]=$'\e[1;34m' [red]=$'\e[0;31m' [reset]=$'\e[0m'
  )

  # 1. Improved Root Discovery (Recursive Upward)
  while [[ "$ROOT_DIR" != "/" ]]; do
    if [[ -f "$ROOT_DIR/pnpm-lock.yaml" ]]; then PM="pnpm"; break
    elif [[ -f "$ROOT_DIR/bun.lockb" || -f "$ROOT_DIR/bun.lock" ]]; then PM="bun"; break
    elif [[ -f "$ROOT_DIR/yarn.lock" ]]; then PM="yarn"; break
    elif [[ -f "$ROOT_DIR/package-lock.json" ]]; then PM="npm"; break
    elif [[ -f "$ROOT_DIR/package.json" ]]; then
      FALLBACK_PM="npm"
      FALLBACK_ROOT="$ROOT_DIR"
    fi
    ROOT_DIR="${ROOT_DIR:h}" # Faster Zsh-native 'dirname'
  done

  # Fallback logic
  if [[ -z "$PM" ]]; then
    if [[ -n "$FALLBACK_ROOT" ]]; then
      PM="$FALLBACK_PM"; ROOT_DIR="$FALLBACK_ROOT"
    else
      echo -e "${colors[yellow]}⚠ No project root found.${colors[reset]}"
      echo "1) npm  2) yarn  3) pnpm  4) bun  5) quit"
      read -k 1 "choice?Select: "
      echo ""
      case $choice in
        1) PM="npm" ;; 2) PM="yarn" ;; 3) PM="pnpm" ;; 4) PM="bun" ;; *) return 0 ;;
      esac
      ROOT_DIR="$PWD"
    fi
  fi

  # 2. Command Mapping (Consistency across managers)
  if [[ $# -eq 0 ]]; then
    COMMAND="install"
  else
    COMMAND=$1
    shift
  fi

  # 3. Monorepo-Aware Safety Check
  # Checks if node_modules exists in current OR root directory
  if [[ ! -d "node_modules" && ! -d "$ROOT_DIR/node_modules" && ! "$COMMAND" =~ ^(i|install|nuke|add)$ ]]; then
    echo -e "${colors[yellow]}⚠ node_modules missing.${colors[reset]}"
    read -q "re?Run '$PM install' now? (y/n) "
    echo ""
    [[ $re == "y" ]] && $PM install || return 1
  fi

  # 4. Context Header
  echo -e "${colors[blue]}⚡ ${PM}${colors[reset]} @ ${colors[cyan]}${ROOT_DIR}${colors[reset]}"

  # 5. Optimized Execution Logic
  case $COMMAND in
    i|install) $PM install "$@" ;;
    add)
      [[ "$PM" == "npm" ]] && npm install "$@" || $PM add "$@" ;;
    rm|remove|uninstall)
      [[ "$PM" == "npm" ]] && npm uninstall "$@" || $PM remove "$@" ;;
    up|upgrade|update)
      case $PM in
        npm)  npm update "$@" ;;
        yarn) yarn upgrade-interactive "$@" ;;
        pnpm) pnpm update --interactive "$@" ;;
        bun)  bun update "$@" ;;
      esac ;;
    nuke)
      echo -e "${colors[red]}☢ Nuking dependencies...${colors[reset]}"
      # Only delete local node_modules and the specific root lockfile
      rm -rf node_modules
      [[ -d "$ROOT_DIR/node_modules" ]] && rm -rf "$ROOT_DIR/node_modules"
      $PM install ;;
    *)
      # Check if it's a script in package.json
      if [[ -f "$ROOT_DIR/package.json" ]] && grep -q "\"$COMMAND\":" "$ROOT_DIR/package.json"; then
        # pnpm/bun/yarn don't strictly need 'run', but npm/pnpm benefit from it for clarity
        if [[ "$PM" == "npm" || "$PM" == "pnpm" ]]; then
          $PM run $COMMAND "$@"
        else
          $PM $COMMAND "$@"
        fi
      else
        $PM $COMMAND "$@"
      fi ;;
  esac
}

#######################################
# Root-Aware Zsh Autocompletion
#######################################

_pm_completion() {
  local -a subcommands scripts
  local ROOT_DIR="$PWD"
  
  while [[ "$ROOT_DIR" != "/" ]]; do
    [[ -f "$ROOT_DIR/package.json" ]] && break
    ROOT_DIR="${ROOT_DIR:h}"
  done

  subcommands=(
    'i:Install dependencies'
    'add:Add package'
    'rm:Remove package'
    'up:Update packages'
    'nuke:Clean & Reinstall'
  )

  if [[ -f "$ROOT_DIR/package.json" ]]; then
    # Portable sed to extract keys from "scripts": { ... }
    scripts=($(sed -n '/"scripts": {/,/}/p' "$ROOT_DIR/package.json" | sed -E 's/^[[:space:]]*"([^"]+)":.*/\1/' | grep -v "scripts"))
  fi

  _alternative \
    'scripts:package.json scripts: _describe -t scripts "scripts" scripts' \
    'commands:pm commands: _describe -t commands "subcommands" subcommands'
}

compdef _pm_completion pm
