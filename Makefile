.PHONY: build-ldc-runtime
build-ldc-runtime:
	ldc-build-runtime \
		--reset \
		--ninja \
		--dFlags="-mtriple=x86_64-unknown-linux-musl -Oz -flto=full --release --boundscheck=off --platformlib= -L/usr/lib/x86_64-linux-musl" \
		--targetSystem 'Linux;musl;UNIX' \
		--linkerFlags '--static' \
		BUILD_SHARED_LIBS=OFF \
		BUILD_LTO_LIBS=ON \
		C_SYSTEM_LIBS=""

.PHONY: build
build:
	ldc2 \
		--mtriple=x86_64-unknown-linux-musl \
		-Oz \
		--release \
		--boundscheck=off \
		--flto=full \
		--defaultlib=phobos2-ldc-lto,druntime-ldc-lto \
		--platformlib= \
		--conf=$(PWD)/ldc-build-runtime.tmp/etc/ldc2.conf \
		--Xcc=-specs=$(PWD)/my-musl-gcc.specs \
		--static \
		-of=hello \
		main.d

.PHONY: run
run: build
	./hello

.PHONY: clean
clean:
	rm hello hello.o
