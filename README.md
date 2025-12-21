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
- -L-Wl,noseparate-code: .rodataと.textを同じPT_LOADセグメントにまとめる
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
  -L-Wl,-z,noseparate-code \
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
759K
```

```console
$ size -A hello
hello  :
section               size      addr
.init                    3   4198400
.text               495310   4198416
.fini                    3   4693726
.rodata             159596   4694016
.eh_frame            62164   4853616
.gcc_except_table     2804   4915780
.tdata                   4   4922784
.tbss                  452   4922800
.init_array             56   4922800
.fini_array             16   4922856
.data.rel.ro           464   4922880
.got                     8   4923344
.got.plt                24   4923368
.data                53096   4923392
__minfo               1232   4976488
.bss                  6104   4977728
.comment                99         0
Total               781435
```

## FAQ

### Q1: なんで.gotとかあるの？

- A: `libgcc_eh.a`の`uw_init_context_1`関数で使われてる。

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

- A: .got経由のコードサイズ減るかなと期待したけど効果がなかった。そもそも--staticにしているとno pieなバイナリになるのかも。

```console
$ file hello
hello: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, stripped
```

オブジェクトファイルなんかみるとrelocatableになってる。

```console
$ file ldc-build-runtime.tmp/objects/object.o
ldc-build-runtime.tmp/objects/object.o: ELF 64-bit LSB relocatable, x86-64, version 1 (GNU/Linux), not stripped
$ objdump --demangle=dlang -dr ldc-build-runtime.tmp/objects/object.o
(...)
0000000000000000 <object.Object.opCmp(Object)>:
   0:   55                      push   %rbp
   1:   48 89 e5                mov    %rsp,%rbp
   4:   41 56                   push   %r14
   6:   53                      push   %rbx
   7:   49 89 fe                mov    %rdi,%r14
   a:   48 8b 3d 00 00 00 00    mov    0x0(%rip),%rdi        # 11 <object.Object.opCmp(Object)+0x11>
                        d: R_X86_64_REX_GOTPCRELX       ClassInfo for Exception-0x4
  11:   e8 00 00 00 00          call   16 <object.Object.opCmp(Object)+0x16>
                        12: R_X86_64_PLT32      _d_allocclass-0x4
  16:   48 89 c3                mov    %rax,%rbx
  19:   48 8b 05 00 00 00 00    mov    0x0(%rip),%rax        # 20 <object.Object.opCmp(Object)+0x20>
                        1c: R_X86_64_REX_GOTPCRELX      vtable for Exception-0x4
  20:   48 89 03                mov    %rax,(%rbx)
  23:   48 c7 43 08 00 00 00    movq   $0x0,0x8(%rbx)
```

### Q3: --fthread-modelでinitial-exec(ランタイムライブラリ)やlocal-exec(実行バイナリ)にしてないのは？

- A: デフォルトだと`__tls_get_addr`経由になりそうだけど効果がなかった。おそらくリンカが最適化してくれている。

### Q4: なんで他の言語(C,Zig,NimあるいはRust)と比較してこんなに大きいの？

- A: いくつかの理由が考えられる
  - druntimeの実装は例外(unwinding)と密接に結びついているので切り離せない
  - std.stdioはstd.logger経由でstd.concurrencyやstd.socketに依存しているのでコードサイズを小さくできない
  - テンプレートが異なる型でインスタンス化されるため、テンプレートを多用している標準ライブラリのコードは大きくなりがち(`nm <バイナリ> | ddemangle | grep -c '!('`などで確認できる)
  - Dは型ごとにTypeInfoを生成し、上のテンプレートのインスタンス化とあわせて地味に大きなサイズになる(`nm <バイナリ> | grep -c 'TypeInfo'`などで確認できる)
  - モジュールコンストラクタ(`static this()`)があるライブラリは消せないので__minfoだけでなく.text/.rodata/.dataなどにも影響が出る
