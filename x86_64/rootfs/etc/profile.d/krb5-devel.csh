if ( "${path}" !~ */usr/kerberos/bin* ) then
	set path = ( /usr/kerberos/bin $path )
endif
if ( "${path}" !~ */usr/kerberos/sbin* ) then
	if ( `id -u` == 0 ) then
		set path = ( /usr/kerberos/sbin $path )
	endif
endif
