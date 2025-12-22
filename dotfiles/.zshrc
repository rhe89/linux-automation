# Linux (Ubuntu) zsh config

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="agnoster"
plugins=(git)

if [ -r "$ZSH/oh-my-zsh.sh" ]; then
  source "$ZSH/oh-my-zsh.sh"
fi

alias list-outdated='apt list --upgradable 2>/dev/null'
alias upgrade-outdated='sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get autoremove -y'

# zsh-syntax-highlighting (apt)
if [ -r "/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
  source "/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

# Add a newline before each prompt
export PS1="$PS1
"

if [ -f "$HOME/projects/aliases.zshrc" ]; then
  source "$HOME/projects/aliases.zshrc"
fi
