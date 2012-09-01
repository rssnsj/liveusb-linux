if ! echo ${PATH} | /bin/grep -q /usr/kerberos/bin ; then
	PATH=/usr/kerberos/bin:${PATH}
fi
if ! echo ${PATH} | /bin/grep -q /usr/kerberos/sbin ; then
	if [ `/usr/bin/id -u` = 0 ] ; then
		PATH=/usr/kerberos/sbin:${PATH}
	fi
fi
