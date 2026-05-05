# .zshrc

# zinit
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
[ ! -d $ZINIT_HOME ] && mkdir -p "$(dirname $ZINIT_HOME)"
[ ! -d $ZINIT_HOME/.git ] && git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
source "${ZINIT_HOME}/zinit.zsh"

# OMZ libraries
zinit snippet OMZL::git.zsh			# Git aliases and functions
zinit snippet OMZL::directories.zsh		# .. / ... / take (mkdir + cd)
zinit snippet OMZL::theme-and-appearance.zsh  	# Terminal title, ls colors
zinit snippet OMZL::async_prompt.zsh 		# Non-blocking git status in prompt

# eza config - must be set BEFORE loading the plugin
zstyle ':omz:plugins:eza' 'dirs-first' yes
zstyle ':omz:plugins:eza' 'git-status' yes
zstyle ':omz:plugins:eza' 'header' yes
zstyle ':omz:plugins:eza' 'icons' yes

# OMZ plugins
zinit snippet OMZP::git    # 150+ git aliases (gst, gco, gp, etc.)
#zinit snippet OMZP::brew   # Homebrew completions
zinit snippet OMZP::direnv # Auto-load .envrc files
zinit snippet OMZP::eza    # ls replacement with icons/git status

# Plugins
zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light Aloxaf/fzf-tab
zinit light MichaelAquilina/zsh-you-should-use

# Load completions efficiently (after prompt is ready)
autoload -Uz compinit
compinit

# Instantiate tools
## Fast node manager (fnm)
FNM_PATH="/home/dylan/.local/share/fnm"
if [ -d "$FNM_PATH" ]; then
	export PATH="$FNM_PATH:$PATH"
	eval "$(fnm env --use-on-cd --shell zsh --version-file-strategy=recursive)"
fi

## Starship
eval "$(starship init zsh)"

## zoxide
ZOXIDE_PATH="/home/dylan/.local/bin"
if [ -d "$ZOXIDE_PATH" ]; then
	export PATH="$ZOXIDE_PATH:$PATH"
	eval "$(zoxide init zsh)"
fi

# History
HISTFILE=${HOME}/.zhistory
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_VERIFY
setopt SHARE_HISTORY

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-z3A-Z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# Atuin - synced shell history (load last)
. "$HOME/.atuin/bin/env"
eval "$(atuin init zsh)"

