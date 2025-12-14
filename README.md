# fully static binary

なるべく小さな静的バイナリを作る。

いちおうレギュレーションとして:

- 標準ライブラリにリンクすること
- 過度にトリッキーな手法(objcopyとかリンカスクリプトとか)を使わないこと

## 0. 準備

musl関連のパッケージを入れておく。

```console
apt install -y musl musl-dev musl-tools
```

## 1. staticな標準ライブラリをビルドする

```bash
ldc-build-runtime \
  --reset \
  --ninja \
  --dFlags="-mtriple=x86_64-unknown-linux-musl -Oz -flto=full --release --relocation-model=static --checkaction=halt" \
  --targetSystem 'Linux;musl;UNIX' \
  --linkerFlags '--static -L-Wl,--strip-all' \
  BUILD_SHARED_LIBS=OFF \
  BUILD_LTO_LIBS=ON
```

## 2. staticな標準ライブラリとリンクして実行バイナリを作る

```console
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
  -of=hello main.d
```

## 3. 静的なバイナリになっているかと動作を確認

```console
$ file hello
hello: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, stripped
$ ldd hello
        not a dynamic executable
$  ./hello
Hello, World!
```

## 4. サイズをみる

```console
 ls -lh hello | awk '{print $5}'
751K
```
