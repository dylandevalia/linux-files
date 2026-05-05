# .zshrc

# ===============================================
#   ENVIRONMENT & PATHS
# ===============================================
export PATH="${HOME}/.local/bin:$PATH"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Fast node manager (fnm)
FNM_PATH="${HOME}/.local/share/fnm"
if [ -d "$FNM_PATH" ]; then
   export PATH="$FNM_PATH:$PATH"
  eval "$(fnm env --use-on-cd --shell zsh --version-file-strategy=recursive)"
fi

# node package manager wrapper (pm)
fpath=($HOME/.zsh/functions $fpath)
autoload -Uz pm

# ===============================================
#   ZINIT BOOTSTRAP
# ===============================================
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
[ ! -d "$ZINIT_HOME" ] && mkdir -p "$(dirname "$ZINIT_HOME")"
[ ! -d "$ZINIT_HOME"/.git ] && git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
source "${ZINIT_HOME}/zinit.zsh"

# ===============================================
#   FAST SYNCHRONOUS SNIPPETS & LIBRARY
# ===============================================
# OMZ libraries (loaded synchronously)
zinit snippet OMZL::git.zsh                     # Git aliases and functions
zinit snippet OMZL::directories.zsh             # .. / ... / take (mkdir + cd)
zinit snippet OMZL::theme-and-appearance.zsh    # Terminal title, ls colors

# Eza config - must be set BEFORE loading the plugin
zstyle ':omz:plugins:eza' 'dirs-first' yes
zstyle ':omz:plugins:eza' 'git-status' yes
zstyle ':omz:plugins:eza' 'header' yes
zstyle ':omz:plugins:eza' 'icons' yes

# ===============================================
#   COMPLETIONS SETUP (Zinit Optimized)
# ===============================================
# Skip security check on directories (-C) for blazing WSL speed
ZINIT[COMPINIT_OPTS]="-C"
ZINIT[ZCOMPDUMP_PATH]="${XDG_CACHE_HOME:-$HOME/.cache}/.zcompdump"

# Load completions plugin with clean update hooks
zinit ice blockf atpull'zinit creinstall -q .'
zinit light zsh-users/zsh-completions

# Initialize the completion system once
zicompinit; zicdreplay

# This tells Zsh to include dotfiles ONLY during tab-completion
_comp_options+=(globdots)

# ===============================================
#   ASYNCHRONOUS PLUGINS (Zinit "Turbo Mode")
# ===============================================
# Load plugins asynchronously 0 seconds after prompt is ready
zinit ice wait lucid; zinit light Aloxaf/fzf-tab                                # Fuzzy completion for commands and files
zinit ice wait lucid; zinit light MichaelAquilina/zsh-you-should-use            # Reminds you to use existing aliases
zinit ice wait lucid; zinit light zdharma-continuum/fast-syntax-highlighting    # Fish-like syntax highlighting
zinit ice wait lucid; zinit light zsh-users/zsh-autosuggestions                 # Fish-like autosuggestions

# OMZ plugins (asynchronous)
zinit ice wait lucid; zinit snippet OMZP::direnv    # direnv integration
zinit ice wait lucid; zinit snippet OMZP::eza       # Enhanced ls replacement
zinit ice wait lucid; zinit snippet OMZP::git       # Git status in prompt and extra aliases

# ===============================================
#   SHELL TOOLS INITIALIZATION
# ===============================================
# Oh My Posh
eval "$(oh-my-posh init zsh --config ${HOME}/.config/oh-my-posh/pure.toml)"

# Zoxide (Smart directory navigation)
eval "$(zoxide init zsh)"

# Atuin - synced shell history (loaded last and safely guarded)
if [ -f "$HOME/.atuin/bin/env" ]; then
    . "$HOME/.atuin/bin/env"
    eval "$(atuin init zsh)"
elif command -v atuin &> /dev/null; then
    eval "$(atuin init zsh)"
fi

# ===============================================
#   PREFERENCES & ALIASES
# ===============================================
# History
HISTFILE=${HOME}/.zhistory
HISTSIZE=10000
SAVEHIST=$HISTSIZE
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_VERIFY
setopt SHARE_HISTORY

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*:*:pm:*' group-order scripts subcommands

# fzf-tab interactive previews
# (Requires bat and eza to be installed)
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
zstyle ':fzf-tab:complete:cat:*' fzf-preview 'bat --color=always --style=header,grid $realpath'
zstyle ':fzf-tab:complete:systemctl-*:*' fzf-preview 'systemctl status $word'

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# Custom aliases (loaded from a separate file for cleanliness)
source $HOME/.aliases

# ===============================================
#   KEYBINDS
# ===============================================

# Bind the Spacebar to auto-expand history shortcuts (e.g., !!, !$)
bindkey ' ' magic-space

# Ctrl + Left/Right Arrow keys to jump whole words
bindkey '^[[1;5D' backward-word
bindkey '^[[1;5C' forward-word

# Ctrl + Backspace/Delete to delete a whole word
bindkey '^H' backward-kill-word
bindkey '^[[3;5~' kill-word

# ===============================================
#   STARTUP
# ===============================================

cd $HOME
clear
quote
echo -e "-=-=-=- Welcome back, $(whoami)! -=-=-=-\n" | lolcat -p 1
