import std.stdio;

/**
libgcc_eh.aがglibc 2.35で追加された_dl_find_object関数に
リンクしようとした場合に、musl libcではこの関数を実装してい
ないためとりあえずstubする。
 */
extern(C) int _dl_find_object(void* pc, void* result)
{
    return -1;
}

void main()
{
    writeln("Hello, World!");
}
