# .bashrc

# User specific aliases and functions

export LS_COLORS=

alias ls='ls --color'
alias ll='ls -l'
alias l='ls -lA'
alias mkdir='mkdir -m755'

# Source global definitions
if [ -f /etc/bashrc ]; then
	. /etc/bashrc
fi
