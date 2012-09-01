# less initialization script (csh)
if ( -x /usr/bin/lesspipe.sh ) then
  setenv LESSOPEN "|/usr/bin/lesspipe.sh %s"
endif
