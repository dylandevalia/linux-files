# My Linux Dotfiles

These are my dotfiles.

---

## The Stack

* **Shell**: `zsh`
* **Plugin manager**: [zinit](https://github.com/zdharma-continuum/zinit)
* **Prompt:** [Starship](https://starship.rs/)
* **Navigation:** [Zoxide](https://github.com/ajeetdsouza/zoxide)
* **Modern Tools:**
    *   `eza`: A modern replacement for `ls`
    *   `bat`: A `cat` clone with syntax highlighting
    *   `fd`: A simple, fast alternative to `find`
    *   `tig`: Text-mode interface for Git

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
