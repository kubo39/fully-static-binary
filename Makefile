.PHONY: build-ldc-runtime
build-ldc-runtime:
	CC=musl-gcc \
		ldc-build-runtime \
		--reset \
		--ninja \
		--dFlags="-mtriple=x86_64-unknown-linux-musl -Oz -flto=full --release --relocation-model=static --checkaction=halt" \
		--targetSystem 'Linux;musl;UNIX' \
		--linkerFlags '--static -L-Wl,--strip-all' \
		BUILD_SHARED_LIBS=OFF \
		BUILD_LTO_LIBS=ON

.PHONY: build
build:
	ldc2 \
		--mtriple=x86_64-unknown-linux-musl \
		--gcc=musl-gcc \
		-Oz \
		--release \
		--flto=full \
		--defaultlib=phobos2-ldc-lto,druntime-ldc-lto \
		--relocation-model=static \
		--checkaction=halt \
		--conf=$(PWD)/ldc-build-runtime.tmp/etc/ldc2.conf \
		-L-Wl,--strip-all \
		--static \
		-of=hello \
		main.d

.PHONY: run
run: build
	./hello

.PHONY: clean
clean:
	rm hello hello.o
