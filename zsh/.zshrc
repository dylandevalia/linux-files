# .zshrc

# =============================================
#   ENVIRONMENT & PATHS
# =============================================
export PATH="${HOME}/.local/bin:$PATH"

# Fast node manager (fnm)
FNM_PATH="${HOME}/.local/share/fnm"
if [ -d "$FNM_PATH" ]; then
   export PATH="$FNM_PATH:$PATH"
  eval "$(fnm env --use-on-cd --shell zsh --version-file-strategy=recursive)"
fi

# =============================================
#   ZINIT BOOTSTRAP
# =============================================
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
[ ! -d "$ZINIT_HOME" ] && mkdir -p "$(dirname "$ZINIT_HOME")"
[ ! -d "$ZINIT_HOME"/.git ] && git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
source "${ZINIT_HOME}/zinit.zsh"

# =============================================
#   FAST SYNCHRONOUS SNIPPETS & LIBRARY
# =============================================
# OMZ libraries (loaded synchronously)
zinit snippet OMZL::git.zsh                     # Git aliases and functions
zinit snippet OMZL::directories.zsh             # .. / ... / take (mkdir + cd)
zinit snippet OMZL::theme-and-appearance.zsh    # Terminal title, ls colors

# Eza config - must be set BEFORE loading the plugin
zstyle ':omz:plugins:eza' 'dirs-first' yes
zstyle ':omz:plugins:eza' 'git-status' yes
zstyle ':omz:plugins:eza' 'header' yes
zstyle ':omz:plugins:eza' 'icons' yes

# =============================================
#   COMPLETIONS SETUP (Zinit Optimized)
# =============================================
# Skip security check on directories (-C) for blazing WSL speed
ZINIT[COMPINIT_OPTS]="-C"
ZINIT[ZCOMPDUMP_PATH]="${HOME}/.zcompdump"

# Load completions plugin with clean update hooks
zinit ice blockf atpull'zinit creinstall -q .'
zinit light zsh-users/zsh-completions

# Initialize the completion system once
zicompinit; zicdreplay

# =============================================
#   ASYNCHRONOUS PLUGINS (Zinit "Turbo Mode")
# =============================================
# Load plugins asynchronously 0 seconds after prompt is ready
zinit ice wait lucid; zinit light zsh-users/zsh-autosuggestions         # Fish-like autosuggestions
zinit ice wait lucid; zinit light zsh-users/zsh-syntax-highlighting     # Fish-like syntax highlighting
zinit ice wait lucid; zinit light MichaelAquilina/zsh-you-should-use    # Reminds you to use existing aliases
zinit ice wait lucid; zinit light Aloxaf/fzf-tab                        # Fuzzy completion for commands and files

# OMZ plugins (asynchronous)
zinit ice wait lucid; zinit snippet OMZP::git       # Git status in prompt and extra aliases
zinit ice wait lucid; zinit snippet OMZP::direnv    # direnv integration
zinit ice wait lucid; zinit snippet OMZP::eza       # Enhanced ls replacement

# =============================================
#   SHELL TOOLS INITIALIZATION
# =============================================
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

# =============================================
#   PREFERENCES & ALIASES
# =============================================
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