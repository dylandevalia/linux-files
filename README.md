# My Linux Dotfiles

These are my dotfiles.

---

## The Stack

### Core Shell
* **Shell**: `zsh`
* **Plugin manager**: [zinit](https://github.com/zdharma-continuum/zinit) (with turbo mode for blazing fast startup)
* **Prompt**: [Oh My Posh](https://ohmyposh.dev/) (pure theme)

### Navigation & History
* **Smart CD**: [Zoxide](https://github.com/ajeetdsouza/zoxide) - Smarter cd command
* **Shell History**: [Atuin](https://github.com/atuinsh/atuin) - Magical shell history sync

### Enhanced Commands
* **ls**: `eza` - Modern replacement with git integration, icons, and tree view
* **cat**: `bat` - Syntax highlighting and git integration
* **git**: `lazygit` - Text-mode interface for Git
* **docker**: `lazydocker` - Text-mode interface for Docker

### Development Tools
* **Node**: `fnm` - Fast Node Manager with auto-switching
* **Runtimes**: `bun` - Fast all-in-one JavaScript runtime
* **Package Manager**: `pm` - Universal wrapper for npm/pnpm/yarn/bun with smart detection

### Zsh Enhancements
* **Completions**: `fzf-tab` - Fuzzy completion with previews
* **Syntax**: `fast-syntax-highlighting` - Fish-like syntax highlighting  
* **Suggestions**: `zsh-autosuggestions` - Fish-like autosuggestions
* **Alias Reminder**: `zsh-you-should-use` - Reminds you to use defined aliases
* **Environment**: `direnv` - Automatic environment switching

### Custom Features
* **Keybinds**: Ctrl+arrows for word navigation, Ctrl+Backspace/Delete for word deletion
* **Aliases**: Custom quality-of-life aliases in `.aliases`
* **Completions**: Custom completion functions (e.g., `pm` command)

---

## Installation

> [!WARNING]
> This script will symlink configurations to your home directory and change your default shell to zsh. Review `install` before running.

1. Clone this repo
```bash
mkdir -p ~/dotfiles
git clone https://github.com/dylandevalia/linux-files.git ~/dotfiles
```

2. Run the installer
```bash
chmod +x ~/dotfiles/install
~/dotfiles/install
```

3. All done!
