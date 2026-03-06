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
  
  # Colors
  local CYAN='\033[0;36m'
  local GREEN='\033[0;32m'
  local YELLOW='\033[1;33m'
  local BLUE='\033[1;34m'
  local RED='\033[0;31m'
  local NC='\033[0m'

  # 1. Root Discovery: Look upwards for a lockfile or package.json
  while [[ "$ROOT_DIR" != "/" ]]; do
    if [[ -f "$ROOT_DIR/package-lock.json" ]]; then
      PM="npm"; break
    elif [[ -f "$ROOT_DIR/yarn.lock" ]]; then
      PM="yarn"; break
    elif [[ -f "$ROOT_DIR/pnpm-lock.yaml" ]]; then
      PM="pnpm"; break
    elif [[ -f "$ROOT_DIR/bun.lockb" || -f "$ROOT_DIR/bun.lock" ]]; then
      PM="bun"; break
    elif [[ -f "$ROOT_DIR/package.json" ]]; then
      FALLBACK_PM="npm"
      FALLBACK_ROOT="$ROOT_DIR"
    fi
    ROOT_DIR="$(dirname "$ROOT_DIR")"
  done

  # Fallback logic
  if [[ -z "$PM" ]]; then
    if [[ -n "$FALLBACK_ROOT" ]]; then
      PM="$FALLBACK_PM"
      ROOT_DIR="$FALLBACK_ROOT"
    else
      ROOT_DIR="$PWD"
      echo -e "${YELLOW}⚠ No project root found.${NC}"
      echo "1) npm  2) yarn  3) pnpm  4) bun  5) quit"
      read -k 1 "choice?Select a manager: "
      echo ""
      case $choice in
        1) PM="npm" ;; 2) PM="yarn" ;; 3) PM="pnpm" ;; 4) PM="bun" ;; *) return 0 ;;
      esac
    fi
  fi

  # 2. Env Check
  if ! command -v $PM &> /dev/null; then
    echo -e "${RED}✘ Error: ${PM} is not installed.${NC}"
    return 1
  fi

  # 3. Version & Context Display
  local PM_VER=$($PM --version)
  echo -e "${BLUE}⚡ ${PM}${NC} (${PM_VER}) @ ${CYAN}${ROOT_DIR}${NC}"

  # 4. Handle Default Command
  if [[ $# -eq 0 ]]; then
    COMMAND="i"
  else
    COMMAND=$1
    shift
  fi

  # 5. Dependency Safety Check
  if [[ ! -d "$ROOT_DIR/node_modules" && ! "$COMMAND" =~ ^(i|install|nuke)$ ]]; then
    echo -e "${YELLOW}⚠ node_modules missing at root.${NC}"
    read -q "re?Run '$PM install' now? (y/n) "
    echo ""
    [[ $re == "y" ]] && $PM install || return 1
  fi

  # 6. Execution Logic
  case $COMMAND in
    i|install)
      echo -e "📦 ${GREEN}Installing...${NC}"
      $PM install "$@"
      ;;
    add)
      echo -e "➕ ${GREEN}Adding:${NC} ${CYAN}$@${NC}"
      [[ "$PM" == "npm" ]] && npm install "$@" || $PM add "$@"
      ;;
    rm|remove|uninstall)
      echo -e "➖ ${RED}Removing:${NC} ${CYAN}$@${NC}"
      [[ "$PM" == "npm" ]] && npm uninstall "$@" || $PM remove "$@"
      ;;
    up|upgrade|update)
      echo -e "🆙 ${GREEN}Updating...${NC}"
      case $PM in
        npm)  npm update "$@" ;;
        yarn) yarn upgrade-interactive "$@" ;;
        pnpm) pnpm update --interactive "$@" ;;
        bun)  bun update "$@" ;;
      esac
      ;;
    nuke)
      echo -e "${RED}☢ NUKING root dependencies...${NC}"
      (
        cd "$ROOT_DIR"
        rm -rf node_modules package-lock.json yarn.lock pnpm-lock.yaml bun.lockb bun.lock
        echo -e "${GREEN}✓ Clean slate. Reinstalling...${NC}"
        $PM install
      )
      ;;
    *)
      if [[ -f "$ROOT_DIR/package.json" ]] && grep -q "\"$COMMAND\":" "$ROOT_DIR/package.json"; then
        echo -e "🚀 ${GREEN}Script:${NC} ${BLUE}$COMMAND${NC}"
        [[ "$PM" == "npm" || "$PM" == "pnpm" ]] && $PM run $COMMAND "$@" || $PM $COMMAND "$@"
      else
        $PM $COMMAND "$@"
      fi
      ;;
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
    ROOT_DIR="$(dirname "$ROOT_DIR")"
  done

  subcommands=(
    'i:Install dependencies'
    'add:Add package'
    'rm:Remove package'
    'up:Update packages'
    'nuke:Clean & Reinstall'
  )

  if [[ -f "$ROOT_DIR/package.json" ]]; then
    scripts=($(sed -n '/"scripts": {/,/}/p' "$ROOT_DIR/package.json" | grep -oP '(?<=")\w+(?="(?=\s*:\s*"))'))
  fi

  _alternative \
    'scripts:package.json scripts: _describe -t scripts "scripts" scripts' \
    'commands:pm commands: _describe -t commands "subcommands" subcommands'
}

compdef _pm_completion pm
