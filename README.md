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

`ldc-build-runtime`を使って標準ライブラリをビルドする。
ldc-build-runtimeは公式installerでLDCを入れると一緒に入ってくる。

[参考: ldc-build-runtimeを使ったruntimeライブラリのビルド方法](https://wiki.dlang.org/Building_LDC_runtime_libraries)

```bash
ldc-build-runtime \
  --reset \
  --ninja \
  --dFlags="-mtriple=x86_64-unknown-linux-musl -Oz -flto=full --release --boundscheck=off --platformlib= --Xcc=-specs=./my-musl-gcc.specs" \
  --targetSystem 'Linux;musl;UNIX' \
  --linkerFlags '--static' \
  BUILD_SHARED_LIBS=OFF \
  BUILD_LTO_LIBS=ON
```

- dFlags: LDCのコンパイルフラグ
  - -mtriple=x86_64-unknown-linux-musl: 静的リンクするためmuslターゲットに
  - -Oz: 最適化+コードサイズ削減
  - -flto=full: Fat LTOを指定してリンク時最適化で不要なセクションを消せるように
  - --release: assert/contracts/invariantを消してboundscheckをsafe関数のみ残す
  - --boundscheck=off: boundscheckを完全に消す
  - --platformlib= : コンパイラがデフォルトでlibrt/libdl/libpthread/libmへリンクするよう指定しているのを防ぐ
  - -Xcc=specs=./my-musl-gcc.specs: カスタムのspecsファイルでリンクするライブラリを指定
- linkerFlags: リンカに伝えるフラグ
  - --static: 静的リンクすることを伝える(-lrtとかしないように)
- BUILD_LTO_LIBS=ON: 実行バイナリでのLTO用にLLVM bitcodeを含んだライブラリを生成

## 2. staticな標準ライブラリとリンクして実行バイナリを作る

コンパイルオプションの説明は上とだいたい同じになるので違うやつだけ。

- --defaultlib=phobos2-ldc-lto,druntime-ldc-lto: LTOのためにbitcodeを含んだライブラリにリンク
- --conf=(...): ldc2.confはどのライブラリにリンクするべきかを指定するための情報が入っているため明示的に指定
- -L-Wl,--strip-all: シンボル情報を削除

```console
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
$ ls -lh hello | awk '{print $5}'
751K
```

```console
$ size -A hello
hello  :
section               size      addr
.init                    3   4198400
.text               482718   4198416
.fini                    3   4681134
.rodata             159212   4681728
.eh_frame            62124   4840944
.gcc_except_table     2804   4903068
.tdata                   4   4910544
.tbss                  452   4910560
.init_array             56   4910560
.fini_array              8   4910616
.data.rel.ro           464   4910624
.got                     8   4911088
.got.plt                24   4911104
.data                53096   4911136
__minfo               1232   4964232
.bss                  6360   4965504
.comment               101         0
Total               768669
```

## FAQ

### Q1: なんで.gotとかあるの？

- A: `libunwind_eh.a`の`uw_init_context_1`関数で使われてる。

```console
$ objdump -s -j .got hello

hello:     file format elf64-x86-64

Contents of section .got:
 4aeff0 00000000 00000000                    ........
$ nm -n hello | awk '$1 ~ /45d6/ {print}'
000000000045d640 t uw_init_context_1
$ nm /usr/lib/gcc/x86_64-linux-gnu/11/libgcc_eh.a 2>/dev/null | grep uw_init_context
0000000000001f10 t uw_init_context_1
0000000000000028 t uw_init_context_1.cold
```

### Q2: -relocation-model=staticでno-pieにしてないのは？

- A: .got経由のコードサイズ減るかなと期待したけど効果がなかった。--staticにしているのとLTOが効いているのかもしれない。あとはGOTPCRELXをリンカがPC相対に最適化したのでコードサイズ上で違いが出なかったとか。

### Q3: --fthread-modelでinitial-exec(ランタイムライブラリ)やlocal-exec(実行バイナリ)にしてないのは？

- A: デフォルトだと`__tls_get_addr`経由になりそうだけど効果がなかった。おそらくリンカが最適化してくれている。

### Q4: なんで他の言語(C,Zig,NimあるいはRust)と比較してこんなに大きいの？

- A: いくつかの理由が考えられる
  - druntimeの実装は例外(unwinding)と密接に結びついているので切り離せない
  - std.stdioはstd.logger経由でstd.concurrencyやstd.socketに依存しているのでコードサイズを小さくできない
  - テンプレートが異なる型でインスタンス化されるため、テンプレートを多用している標準ライブラリのコードは大きくなりがち(`nm <バイナリ> | ddemangle | grep -c '!('`などで確認できる)
  - Dは型ごとにTypeInfoを生成し、上のテンプレートのインスタンス化とあわせて地味に大きなサイズになる(`nm <バイナリ> | grep -c 'TypeInfo'`などで確認できる)。最適化で消えている可能性もあるが。。
