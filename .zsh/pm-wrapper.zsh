#!/usr/bin/env zsh

# ==============================================================================
# pm - Universal Package Manager Wrapper (Zsh Optimized)
# ------------------------------------------------------------------------------
# A context-aware wrapper that intelligently detects and executes commands
# across pnpm, bun, yarn, and npm.
#
# FEATURES:
#   - Root Discovery: Recursively walks up directories to find project roots.
#   - Command Mapping: Normalizes 'add', 'rm', and 'up' across all managers.
#   - Safety First: Prompts to install if node_modules are missing.
#   - Script Detection: Runs 'package.json' scripts without needing 'run'.
#   - Nuke Mode: A "panic button" to clean and fresh-install dependencies.
#   - Autocompletion: Deep integration with Zsh to suggest scripts and commands.
#
# USAGE:
#   pm                -> Detects manager and runs default install
#   pm <command>      -> Runs command (eg. pm dev, pm test)
#   pm add <pkg>      -> Adds a dependency using the correct syntax
#   pm up             -> Interactive update (where supported)
#   pm nuke           -> Deletes node_modules/lockfiles and reinstalls
#
# COMPATIBILITY:
#   Optimized for Zsh on macOS and Linux. Requires no external dependencies
#   like 'jq' (uses native 'sed' and 'grep').
# ==============================================================================

# ==============================================================================
# pm - Universal Package Manager Wrapper (Zsh Optimized)
# ------------------------------------------------------------------------------
# A context-aware tool that intelligently bridges the gap between npm, pnpm,
# yarn, and bun. It treats the project root as the source of truth.
#
# CORE LOGIC:
#   1. DETECTION:  Recursively searches upward for lockfiles.
#   2. CONFLICTS:  Warns if multiple lockfiles (eg., yarn vs npm) exist.
#   3. MAPPING:    Normalizes different PM syntaxes into a single API.
#   4. SELF-HEAL:  Prompts to install missing PMs or 'ncu' for updates.
#   5. NAVIGATION: Offers to 'cd' to the project root for root-level tasks.
#
# USAGE:
#   pm                -> Install dependencies (detects manager)
#   pm add <pkg>      -> Adds a package (handles 'npm install' vs 'yarn add')
#   pm add -D <pkg>   -> Adds a dev dependency
#   pm rm <pkg>       -> Removes a package
#   pm up             -> Triggers interactive update (prefers ncu -i)
#   pm nuke           -> Wipe node_modules/lockfiles and start fresh
#   pm [script]       -> Runs any script defined in package.json (eg., pm dev)
#   pm help           -> Shows the internal help guide
#
# TECHNICAL NOTES:
#   - Requires Zsh (uses Zsh-specific path expansion and prompts).
#   - macOS/Linux compatible (uses portable sed/grep).
#   - Integrated autocompletion for scripts and subcommands.
# ==============================================================================

pm() {
	local PM=""
	local COMMAND=""
	local ROOT_DIR="$PWD"
	local FALLBACK_PM=""
	local FALLBACK_ROOT=""

	# Colors
	typeset -A colors=(
		[cyan]=$'\e[0;36m'
		[green]=$'\e[0;32m'
		[yellow]=$'\e[1;33m'
		[blue]=$'\e[1;34m'
		[red]=$'\e[0;31m'
		[reset]=$'\e[0m'
	)

	# Help / Usage Guide
	if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
		echo -e "${colors[blue]}pm${colors[reset]} - Universal Package Manager Wrapper"
		echo -e "Usage: ${colors[cyan]}pm${colors[reset]} <command> [args...]\n"
		echo -e "${colors[yellow]}Subcommands:${colors[reset]}"
		echo -e "  ${colors[green]}i, install${colors[reset]}     Install dependencies"
		echo -e "  ${colors[green]}add, add -D${colors[reset]}    Add/Dev-add a package"
		echo -e "  ${colors[green]}rm, remove${colors[reset]}      Remove a package"
		echo -e "  ${colors[green]}up, update${colors[reset]}      Interactive update via 'ncu'"
		echo -e "  ${colors[green]}nuke${colors[reset]}            Total cleanup & fresh reinstall"
		echo -e "\n${colors[yellow]}QoL Features:${colors[reset]}"
		echo -e "  - Auto-detects project root from subdirectories"
		echo -e "  - Prevents lockfile conflicts (eg. yarn vs npm)"
		echo -e "  - Self-heals missing tools (ncu, bun, pnpm, etc.)"
		return 0
	fi

	# Internal helper to ensure a tool is present
	_ensure_tool() {
		local tool_name=$1
		local install_cmd=$2
		if ! command -v "$tool_name" &>/dev/null; then
			echo -e "${colors[yellow]}⚠ ${tool_name} is required but not installed.${colors[reset]}"
			read -q "choice?Install it now via '${install_cmd}'? (y/n) "
			echo ""
			if [[ $choice == "y" ]]; then
				eval "$install_cmd"
			else
				return 1
			fi
		fi
		return 0
	}

	# 1. Root Discovery
	while [[ "$ROOT_DIR" != "/" ]]; do
		if [[ -f "$ROOT_DIR/pnpm-lock.yaml" ]]; then
			PM="pnpm"
			break
		elif [[ -f "$ROOT_DIR/bun.lockb" || -f "$ROOT_DIR/bun.lock" ]]; then
			PM="bun"
			break
		elif [[ -f "$ROOT_DIR/yarn.lock" ]]; then
			PM="yarn"
			break
		elif [[ -f "$ROOT_DIR/package-lock.json" ]]; then
			PM="npm"
			break
		elif [[ -f "$ROOT_DIR/package.json" ]]; then
			FALLBACK_PM="npm"
			FALLBACK_ROOT="$ROOT_DIR"
		fi
		ROOT_DIR="${ROOT_DIR:h}"
	done

	# Fallback logic
	if [[ -z "$PM" ]]; then
		if [[ -n "$FALLBACK_ROOT" ]]; then
			PM="$FALLBACK_PM"
			ROOT_DIR="$FALLBACK_ROOT"
		else
			echo -e "${colors[yellow]}⚠ No project root found.${colors[reset]}"
			echo "1) npm  2) yarn  3) pnpm  4) bun  5) quit"
			read -k 1 "choice?Select: "
			echo ""
			case $choice in 1) PM="npm" ;; 2) PM="yarn" ;; 3) PM="pnpm" ;; 4) PM="bun" ;; *) return 0 ;; esac
			ROOT_DIR="$PWD"
		fi
	fi

	# 2. Lockfile Conflict Check
	if [[ "$PM" == "npm" && -f "$ROOT_DIR/yarn.lock" ]]; then
		echo -e "${colors[red]}⚠ WARNING: Found yarn.lock but using npm.${colors[reset]}"
		read -q "ans?Switch to yarn instead? (y/n) "
		[[ $ans == "y" ]] && PM="yarn" && echo ""
	fi

	# 3. PM Installation Safety
	local pm_install_cmd=""
	case $PM in
	npm) pm_install_cmd="echo 'Please install Node.js manually.'" ;;
	yarn) pm_install_cmd="npm install -g yarn" ;;
	pnpm) pm_install_cmd="npm install -g pnpm" ;;
	bun) pm_install_cmd="curl -fsSL https://bun.sh/install | bash" ;;
	esac
	_ensure_tool "$PM" "$pm_install_cmd" || return 1

	# 4. Handle Arguments
	if [[ $# -eq 0 ]]; then
		COMMAND="install" else COMMAND=$1
		shift
	fi

	# 5. Root Context Logic
	if [[ "$PWD" != "$ROOT_DIR" && "$COMMAND" =~ ^(i|install|nuke|up|update)$ ]]; then
		echo -e "${colors[yellow]}⚠ You are in a subdirectory.${colors[reset]}"
		read -q "move?Jump to root ($ROOT_DIR) first? (y/n) "
		if [[ $move == "y" ]]; then cd "$ROOT_DIR" && echo ""; fi
	fi

	# 6. Dependency Safety Check
	if [[ ! -d "node_modules" && ! -d "$ROOT_DIR/node_modules" && ! "$COMMAND" =~ ^(i|install|nuke|add)$ ]]; then
		echo -e "${colors[yellow]}⚠ node_modules missing.${colors[reset]}"
		read -q "re?Run '$PM install' now? (y/n) "
		echo ""
		[[ $re == "y" ]] && $PM install || return 1
	fi

	echo -e "${colors[blue]}⚡ ${PM}${colors[reset]} (${colors[cyan]}${ROOT_DIR}${colors[reset]})"

	# 7. Execution Logic
	case $COMMAND in
	i | install | in)
		echo -e "📦 ${colors[green]}Installing...${colors[reset]}"
		$PM install "$@"
		;;
	add)
		echo -e "➕ ${colors[green]}Adding:${colors[reset]} ${colors[cyan]}$@${colors[reset]}"
		[[ "$PM" == "npm" ]] && npm install "$@" || $PM add "$@"
		;;
	rm | remove | uninstall)
		echo -e "➖ ${colors[red]}Removing:${colors[reset]} ${colors[cyan]}$@${colors[reset]}"
		[[ "$PM" == "npm" ]] && npm uninstall "$@" || $PM remove "$@"
		;;
	up | upgrade | update)
		if _ensure_tool "ncu" "npm install -g npm-check-updates"; then
			ncu -i "$@"
		else
			case $PM in yarn) yarn upgrade-interactive "$@" ;; pnpm) pnpm update --interactive "$@" ;; *) $PM update "$@" ;; esac
		fi
		;;
	nuke)
		echo -e "${colors[red]}☢ NUKING root dependencies...${colors[reset]}"
		rm -rf node_modules package-lock.json yarn.lock pnpm-lock.yaml bun.lockb bun.lock
		$PM install
		;;
	*)
		if [[ -f "$ROOT_DIR/package.json" ]] && grep -q "\"$COMMAND\":" "$ROOT_DIR/package.json"; then
			echo -e "🚀 ${colors[green]}Script:${colors[reset]} ${colors[blue]}$COMMAND${colors[reset]}"
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
		ROOT_DIR="${ROOT_DIR:h}"
	done

	subcommands=(
		'i:Install dependencies'
		'add:Add package'
		'rm:Remove package'
		'up:Update packages'
		'nuke:Clean & Reinstall'
		'help:Show usage guide'
	)

	if [[ -f "$ROOT_DIR/package.json" ]]; then
		scripts=($(sed -n '/"scripts": {/,/}/ s/^[[:space:]]*"\([^"]*\)":.*/\1/p' "$ROOT_DIR/package.json" | grep -v "scripts"))
		scripts=("${scripts[@]//:/\\:}")
	fi

	_alternative \
		'scripts:package.json scripts: _describe -t scripts "scripts" scripts' \
		'commands:pm commands: _describe -t commands "subcommands" subcommands'
}

compdef _pm_completion pm
