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
	# Standardize environment for the duration of this function
	emulate -L zsh
	setopt local_options no_unset pipe_fail

	local PM="" COMMAND="" ROOT_DIR="$PWD" PKG_DIR="$PWD"
	local ARGS=()
	local FORCE_YES=false
	local PARSING_FLAGS=true

	# CI awareness: automatically bypass prompts in CI environments
	[[ "$CI" == "1" ]] && FORCE_YES=true

	# 1. Global Flag Parsing (Strictly before the command or '--')
	for arg in "$@"; do
		if [[ "$PARSING_FLAGS" == true ]]; then
			case $arg in
			--) PARSING_FLAGS=false ;;
			-y | --yes | --no-prompt) FORCE_YES=true ;;
			-h | --help | help)
				_pm_help
				return 0
				;;
			*) ARGS+=("$arg") ;;
			esac
		else
			ARGS+=("$arg")
		fi
	done

	# 2. Root & Manager Detection logic
	# Finds the nearest package.json for scripts, and the nearest lockfile for PM choice.
	local current="$PWD"
	local found_pkg=false
	local locks_found=()

	while [[ "$current" != "/" ]]; do
		# Track the nearest package.json for script context
		[[ -f "$current/package.json" && "$found_pkg" == false ]] && {
			PKG_DIR="$current"
			found_pkg=true
		}

		# Identify lockfiles at this directory level
		local current_locks=()
		[[ -f "$current/pnpm-lock.yaml" ]] && current_locks+=("pnpm")
		[[ -f "$current/bun.lockb" || -f "$current/bun.lock" ]] && current_locks+=("bun")
		[[ -f "$current/yarn.lock" ]] && current_locks+=("yarn")
		[[ -f "$current/package-lock.json" ]] && current_locks+=("npm")

		if [[ ${#current_locks[@]} -gt 0 ]]; then
			locks_found=("${current_locks[@]}")
			PM="${locks_found[1]}" # Deterministic pick based on check order
			ROOT_DIR="$current"
			break
		elif [[ -d "$current/.git" ]]; then
			ROOT_DIR="$current" # Stop climbing at git root
			break
		fi
		current="${current:h}"
	done

	# Extract Command and slice remaining ARGS safely using Zsh array syntax
	COMMAND=${ARGS[1]:-install}
	ARGS=("${ARGS[@]:1}")

	# Default to npm if no lockfile is present
	[[ -z "$PM" ]] && PM="npm"

	# 3. Environment Sanity Checks
	if [[ ! -f "$ROOT_DIR/package.json" && ! -f "$PKG_DIR/package.json" ]]; then
		if [[ ! "$COMMAND" =~ ^(init|create|doctor)$ ]]; then
			print -P -u2 "%F{yellow}⚠ No package.json found. Functioning in generic mode.%f"
		fi
	fi

	# Warn if multiple lockfiles are polluting the same directory
	if [[ ${#locks_found[@]} -gt 1 && "$FORCE_YES" == false ]]; then
		print -P -u2 "%F{yellow}⚠ Conflict: Multiple lockfiles found: ${locks_found[*]}.%f"
		print -P -u2 "%F{yellow}Defaulting to ${PM}.%f"
	fi

	# --- Internal Helpers ---

	# Helper: Execute using the detected Package Manager (always at root)
	_pm_run() {
		print -P "%F{blue}Executing:%f %F{cyan}(cd \"$ROOT_DIR\" && $PM \"$@\")%f"
		(cd "$ROOT_DIR" && command "$PM" "$@")
	}

	# Helper: Execute a raw command without PM prefix (always at root)
	_pm_cmd() {
		print -P "%F{blue}Executing:%f %F{cyan}(cd \"$ROOT_DIR\" && \"$@\")%f"
		(cd "$ROOT_DIR" && command "$@")
	}

	# Helper: Verify tool existence and offer installation safely (no eval)
	_pm_ensure() {
		local bin="$1"
		shift
		if ! command -v "$bin" &>/dev/null; then
			if [[ "$FORCE_YES" == true ]]; then
				print -P -u2 "%F{red}Error: Required tool '$bin' missing.%f"
				return 1
			fi
			read -q "choice?Install $bin now? (y/n) " || {
				echo
				return 1
			}
			echo
			"$@" # Directly execute the installation array
		fi
		return 0
	}

	# 4. Toolchain Validation
	case $PM in
	npm) _pm_ensure npm print -P -u2 "Please install Node.js manually." || return 1 ;;
	yarn) _pm_ensure yarn npm install -g yarn || return 1 ;;
	pnpm) _pm_ensure pnpm npm install -g pnpm || return 1 ;;
	bun) _pm_ensure bun bash -lc 'curl -fsSL https://bun.sh/install | bash' || return 1 ;;
	esac

	# 5. Command Routing
	case $COMMAND in
	# Basic Management
	i | install) _pm_run install "${ARGS[@]}" ;;

	add)
		local is_dev=false final_args=()
		for a in "${ARGS[@]}"; do [[ "$a" =~ ^(-D|--dev)$ ]] && is_dev=true || final_args+=("$a"); done

		# Map dev flags: bun uses '-d', everyone else uses '-D'
		case $PM in
		npm) [[ "$is_dev" == true ]] && _pm_run install -D "${final_args[@]}" || _pm_run install "${final_args[@]}" ;;
		bun) [[ "$is_dev" == true ]] && _pm_run add -d "${final_args[@]}" || _pm_run add "${final_args[@]}" ;;
		*) [[ "$is_dev" == true ]] && _pm_run add -D "${final_args[@]}" || _pm_run add "${final_args[@]}" ;;
		esac
		;;

	rm | remove | uninstall)
		[[ "$PM" == "npm" ]] && _pm_run uninstall "${ARGS[@]}" || _pm_run remove "${ARGS[@]}"
		;;

	# Updates: Prefer npm-check-updates (ncu) for all managers
	up | update | upgrade)
		if command -v ncu &>/dev/null; then
			_pm_cmd ncu -i "${ARGS[@]}"
		else
			case $PM in
			pnpm) _pm_run up -i ;;
			yarn) _pm_run upgrade-interactive --latest ;;
			*) _pm_run update "${ARGS[@]}" ;;
			esac
		fi
		;;

	# Exec: Dispatch correctly to npx/dlx/bunx
	exec | x)
		case $PM in
		npm) _pm_cmd npx "${ARGS[@]}" ;;
		pnpm) _pm_run dlx "${ARGS[@]}" ;;
		yarn) _pm_run dlx "${ARGS[@]}" ;;
		bun) _pm_cmd bunx "${ARGS[@]}" ;;
		esac
		;;

	# Nuke: Destructive cleanup with project-name confirmation
	nuke)
		[[ "$ROOT_DIR" == "/" || "$ROOT_DIR" == "$HOME" ]] && {
			print -P -u2 "%F{red}Error: Cannot nuke system root or home.%f"
			return 1
		}
		if [[ "$FORCE_YES" == false ]]; then
			local project_name=$(basename "$ROOT_DIR")
			print -P "%F{red}☢ DANGER:%f Wipe node_modules & lockfiles in $ROOT_DIR?"
			echo -n "Type '$project_name' to confirm: "
			read confirm
			[[ "$confirm" != "$project_name" ]] && {
				print -P "\n%F{yellow}Aborted.%f"
				return 1
			}
		fi
		# Defensive rm with '--' to prevent filename-as-flag interpretation
		(cd "$ROOT_DIR" && rm -rf -- node_modules package-lock.json yarn.lock pnpm-lock.yaml bun.lockb bun.lock && command "$PM" install)
		;;

	doctor)
		print -P "%F{blue}--- PM DOCTOR ---%f"
		echo "Working Dir:  $PWD"
		echo "Project Root: $ROOT_DIR"
		echo "Manager:      $PM ($(command "$PM" --version 2>/dev/null || echo 'Not Found'))"
		[[ ${#locks_found[@]} -gt 0 ]] && echo "Detected:     ${locks_found[*]}"
		[[ ! -d "$ROOT_DIR/node_modules" ]] && print -P "%F{red}✗ node_modules missing%f" || echo "✓ node_modules present"
		command -v ncu &>/dev/null && echo "✓ ncu installed" || echo "opt: ncu missing"
		;;

	*)
		# Dynamic Script Detection
		local SCRIPT_EXISTS=false
		if [[ -f "$PKG_DIR/package.json" ]]; then
			if command -v jq &>/dev/null; then
				[[ $(jq -e ".scripts[\"$COMMAND\"]" "$PKG_DIR/package.json" 2>/dev/null) != "null" ]] && SCRIPT_EXISTS=true
			elif command -v node &>/dev/null; then
				SCRIPT_EXISTS=$(node -e "try { const s = require('$PKG_DIR/package.json').scripts; console.log(s && '$COMMAND' in s) } catch { console.log(false) }")
			else
				# Fallback: strictly grep within the scripts block via sed
				sed -n '/"scripts": {/,/}/p' "$PKG_DIR/package.json" | grep -q "\"$COMMAND\":" && SCRIPT_EXISTS=true
			fi
		fi

		if [[ "$SCRIPT_EXISTS" == "true" ]]; then
			# Handle prefix differences (npm/pnpm require 'run')
			[[ "$PM" == "npm" || "$PM" == "pnpm" ]] && _pm_run run "$COMMAND" "${ARGS[@]}" || _pm_run "$COMMAND" "${ARGS[@]}"
		else
			_pm_run "$COMMAND" "${ARGS[@]}"
		fi
		;;
	esac
}

_pm_help() {
	print -P "%F{blue}pm%f - The Unified Package Manager Wrapper (v3.0)"
	echo "Usage: pm [options] <command> [args]"
	echo ""
	echo "Options:"
	echo "  -y, --yes     Bypass all confirmation prompts (Force Yes)"
	echo "  --            Stop parsing pm flags (pass remaining to manager)"
	echo ""
	echo "Commands:"
	echo "  i, install    Install all dependencies at project root"
	echo "  add [-D]      Add package (standardized dev flag mapping)"
	echo "  rm, remove    Remove package"
	echo "  up, update    Interactive version update (prefers ncu)"
	echo "  x, exec       Run binaries (npx/dlx/bunx equivalent)"
	echo "  nuke          Delete node_modules/locks and reinstall"
	echo "  doctor        Diagnostics for current JS environment"
	echo "  [script]      Run any script defined in package.json"
}

#######################################
# Zsh Autocompletion
#######################################

_pm_completion() {
	emulate -L zsh
	local -a subcommands scripts
	local ROOT_DIR="$PWD" PKG_DIR="$PWD"

	# Context discovery for completion
	while [[ "$ROOT_DIR" != "/" ]]; do
		[[ -f "$ROOT_DIR/package.json" ]] && {
			PKG_DIR="$ROOT_DIR"
			break
		}
		ROOT_DIR="${ROOT_DIR:h}"
	done

	subcommands=('i:Install' 'add:Add' 'rm:Remove' 'up:Update' 'nuke:Clean' 'x:Exec' 'doctor:Doctor' 'help:Help')

	# Parse scripts from package.json using hierarchy: jq > node > sed
	if [[ -f "$PKG_DIR/package.json" ]]; then
		if command -v jq &>/dev/null; then
			scripts=($(jq -r '.scripts | keys[]?' "$PKG_DIR/package.json" 2>/dev/null))
		elif command -v node &>/dev/null; then
			scripts=($(node -e "try { console.log(Object.keys(require('$PKG_DIR/package.json').scripts||{}).join(' ')) } catch {}" 2>/dev/null))
		else
			scripts=($(sed -n '/"scripts": {/,/}/ s/^[[:space:]]*"\([^"]*\)":.*/\1/p' "$PKG_DIR/package.json" | grep -v "scripts"))
		fi
		scripts=("${scripts[@]//:/\\:}") # Escape colons for Zsh _describe
	fi

	_alternative \
		'scripts:scripts: _describe -t scripts "scripts" scripts' \
		'commands:commands: _describe -t commands "subcommands" subcommands'
}

compdef _pm_completion pm
