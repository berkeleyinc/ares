
build_and_run: build
	gdb ares-bin -ex r -ex bt -ex q

dbg: build
	gdb ares-bin -ex r -ex bt

build:
	dub build --skip-registry=all --compiler=dmd

release:
	dub build --build=release --compiler=ldc && cp ares-bin /tmp/ares-bin.new

deploy: release
	cp ares-bin /tmp/ares-bin.new
	patchelf --set-interpreter /home/yuri/ares/ld-linux-x86-64.so.2 --set-rpath /home/yuri/ares --force-rpath /tmp/ares-bin.new
	# upx /tmp/ares-bin.new
	scp /tmp/ares-bin.new elite.bshellz.net:~/ares
	ssh elite.bshellz.net 'cd ares && ./tmux_restart.sh'
