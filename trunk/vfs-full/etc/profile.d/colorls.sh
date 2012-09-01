# color-ls initialization

alias ll='ls -l' 2>/dev/null
alias l.='ls -d .*' 2>/dev/null

COLORS=/etc/DIR_COLORS
[ -e "/etc/DIR_COLORS.$TERM" ] && COLORS="/etc/DIR_COLORS.$TERM"
[ -e "$HOME/.dircolors" ] && COLORS="$HOME/.dircolors"
[ -e "$HOME/.dircolors.$TERM" ] && COLORS="$HOME/.dircolors.$TERM"
[ -e "$HOME/.dir_colors" ] && COLORS="$HOME/.dir_colors"
[ -e "$HOME/.dir_colors.$TERM" ] && COLORS="$HOME/.dir_colors.$TERM"
[ -e "$COLORS" ] || return

eval `dircolors --sh "$COLORS"`
[ -z "$LS_COLORS" ] && return

if ! egrep -qi "^COLOR.*none" $COLORS >/dev/null 2>/dev/null ; then
	alias ll='ls -l --color=tty' 2>/dev/null
	alias l.='ls -d .* --color=tty' 2>/dev/null
	alias ls='ls --color=tty' 2>/dev/null
fi
