# color-ls initialization
alias ll 'ls -l'
alias l. 'ls -d .*'

set COLORS=/etc/DIR_COLORS
if ($?TERM) then
    if ( -e "/etc/DIR_COLORS.$TERM" ) set COLORS="/etc/DIR_COLORS.$TERM"
endif
if ( -f ~/.dircolors ) set COLORS=~/.dircolors
if ($?TERM) then
    if ( -f ~/.dircolors."$TERM" ) set COLORS=~/.dircolors."$TERM"
endif
if ( -f ~/.dir_colors ) set COLORS=~/.dir_colors
if ($?TERM) then
    if ( -f ~/.dir_colors."$TERM" ) set COLORS=~/.dir_colors."$TERM"
endif

if ( ! -e "$COLORS" ) exit

eval `dircolors -c $COLORS`

if ( "$LS_COLORS" == '' ) then
   exit
endif

set color_none=`sed -n '/^COLOR.*none/Ip' < $COLORS`
if ( "$color_none" == '' ) then
alias ll 'ls -l --color=tty'
alias l. 'ls -d .* --color=tty'
alias ls 'ls --color=tty'
endif
unset color_none
