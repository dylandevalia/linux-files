# linux dot files

Stores my config files, aliases, and misc dot files

## Setup 

Setup taken from here: https://www.atlassian.com/git/tutorials/dotfiles

1. Create `~/.cfg` directory and add it to `.gitignore`

```sh
mkdir $HOME/.cfg
echo ".cfg" >> .gitignore
```

1. Add config alias temporarily to `.bashrc` or `.zsh`

```sh
alias config='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'
```

3. Clone repo

```sh
git clone --bare https://github.com/dylandevalia/linux-files.git $HOME/.cfg
```

4. Checkout the content

```sh
config checkout
```

If the checkout fails due to overwriting untracked files, you can run this command to backup and move those files and then retry the checkout

```sh
mkdir -p .config-backup && \
config checkout 2>&1 | egrep "\s+\." | awk {'print $1'} | \
xargs -I{} mv {} .config-backup/{}
```

5. Hide untracked files from this local repo

```sh
config config --local status.showUntrackedFiles no
```

## Usage

```sh
config status                            # Check git status
config add .zshrc                        # Add files
config commit -m "feat: updated .zshrc"  # Commit files
config push                              # Push changes
```
