# .bashrc

# User specific aliases and functions

alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

export LS_COLORS=

alias ls='ls --color'
alias ll='ls -l'
alias l='ls -lA'
alias mkdir='mkdir -m755'

# Source global definitions
if [ -f /etc/bashrc ]; then
	. /etc/bashrc
fi
