name = deb-format-ancient-file

all:
	-mkdir -p root/usr/share/doc/$(name)
	install -m0644 copyright changelog root/usr/share/doc/$(name)
	gzip -n -9 -f root/usr/share/doc/$(name)/changelog
	env TZ=GMT touch -t 197001010000 \
	    root/usr/share/doc/$(name)/changelog.gz

	-mkdir -p root/usr/share/cargo/registry/$(name)
	echo '{}' > root/usr/share/cargo/registry/$(name)/.cargo_vcs_info.json
	env TZ=GMT touch -t 197001010000 \
	    root/usr/share/cargo/registry/$(name)/.cargo_vcs_info.json

	chown 0:0 control
	chmod 644 control
	env TZ=GMT touch -d@-1 control

	# Use --no-fix-perm to avoid it messing with the
	# our created "mod-times"
	create-deb -o $(name).deb --no-fix-perm \
            --root root/ control

clean:
	rm -f *.tar.gz *.deb md5sums debian-binary
	rm -rf root
