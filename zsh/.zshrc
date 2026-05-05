# .zshrc

# Update PATH
export PATH="${HOME}/.local/bin:$PATH"
## Fast node manager (fnm)
FNM_PATH="${HOME}/.local/share/fnm"
if [ -d "$FNM_PATH" ]; then
	export PATH="$FNM_PATH:$PATH"
	eval "$(fnm env --use-on-cd --shell zsh --version-file-strategy=recursive)"
fi

# Load zinit
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
[ ! -d "$ZINIT_HOME" ] && mkdir -p "$(dirname "$ZINIT_HOME")"
[ ! -d "$ZINIT_HOME"/.git ] && git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
source "${ZINIT_HOME}/zinit.zsh"

# OMZ libraries
zinit snippet OMZL::git.zsh			# Git aliases and functions
zinit snippet OMZL::directories.zsh		# .. / ... / take (mkdir + cd)
zinit snippet OMZL::theme-and-appearance.zsh  	# Terminal title, ls colors

# eza config - must be set BEFORE loading the plugin
zstyle ':omz:plugins:eza' 'dirs-first' yes
zstyle ':omz:plugins:eza' 'git-status' yes
zstyle ':omz:plugins:eza' 'header' yes
zstyle ':omz:plugins:eza' 'icons' yes

# Synchronous Plugins (Completions must load before prompt)
zinit ice blockf; zinit light zsh-users/zsh-completions

# Load completions efficiently (after prompt is ready)
autoload -Uz compinit
compinit -d ~/.zcompdump
# Enable Zinit's completion caching helper
zicompinit; zicdreplay

# Plugins
zinit ice wait"0" lucid; zinit light zsh-users/zsh-autosuggestions
zinit ice wait"0" lucid; zinit light zsh-users/zsh-syntax-highlighting
zinit ice wait"0" lucid; zinit light MichaelAquilina/zsh-you-should-use
zinit ice wait"0" lucid; zinit light Aloxaf/fzf-tab

# OMZ plugins
zinit ice wait"0" lucid; zinit snippet OMZP::git    # 150+ git aliases (gst, gco, gp, etc.)
#zinit ice wait"0" lucid; zinit snippet OMZP::brew   # Homebrew completions
zinit ice wait"0" lucid; zinit snippet OMZP::direnv # Auto-load .envrc files
zinit ice wait"0" lucid; zinit snippet OMZP::eza    # ls replacement with icons/git status

# Instantiate tools
# Oh my posh
eval "$(oh-my-posh init zsh --config ${HOME}/.config/oh-my-posh/pure.toml)"

## Starship
#eval "$(starship init zsh)"

## zoxide
eval "$(zoxide init zsh)"

## Atuin - synced shell history (load last)
. "$HOME/.atuin/bin/env"
eval "$(atuin init zsh)"

# History
HISTFILE=${HOME}/.zhistory
HISTSIZE=10000
SAVEHIST=$HISTSIZE
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_VERIFY
setopt SHARE_HISTORY

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-z3A-Z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"