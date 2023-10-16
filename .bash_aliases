# ease of use

alias q="exit"
alias c="clear"
mkcd() {
	mkdir "$1"
	cd "$1"
}


# git

alias gls="git status"
alias gbr="git branch"
alias gco="git checkout"
alias grom="git remote update; git reset --hard origin/master"
alias gpb="git push --set-upstream origin $(git rev-parse --symbolic-full-name --abbrev-ref HEAD)"
gcoo() {
	git remote update
	git checkout origin/"$1" --track
}


# work

alias msr="cd ~/enerlytics/maintenance-strategy-review/"
alias pbl="cd ~/enerlytics/pebble/"
alias pmh="cd ~/enerlytics/predictive-maintenance-hub/"
alias sam="cd ~/enerlytics/spherical-alarm-monitor/"
alias arm="cd ~/enerlytics/asset-risk-management/"
alias charts="cd ~/enerlytics/charts-experimental/"
alias thermo="cd ~/enerlytics/thermodynamic-modelling-viewer/"

alias cama="cd ~/coode/Cama-Front-End/FrontEnd/Adam.VueUi/"

# misc

alias code="/mnt/c/Program\ Files/Microsoft\ VS\ Code/bin/code . &"
alias explorer="/mnt/c/Windows/explorer.exe ."

quote () {
  eyes="bdgpstwy"
  rnd=$[ ($RANDOM % 3) ]
  
  case "$rnd" in
    0)
      color="\033[1;33m" # yellow
      file=~/.quotes/simpsonsChalkboards
      ;;
    1)
      color="\033[1;36m" # light cyan
      file=~/.quotes/futuramaCaptions
      ;;
    2)
      color="\033[1;32m" # light green
      file=~/.quotes/minecraftSplashes
      ;;
    *)
      color="\033[1;37m" # white
      file=~/.quotes/error
  esac

  echo -e "${color}"
  shuf -n 1 $file | cowsay -${eyes:$(( $RANDOM % ${#eyes} )):1}
  echo -e "\033[0m"
}
