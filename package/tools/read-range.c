/* Read-only ARM EABI/Linux range copier; no libc, 64-bit kernel seek.
 * Usage: read-range INPUT START_SECTOR SECTOR_COUNT (512-byte sectors).
 * Only writes to stdout/stderr; INPUT is always opened O_RDONLY.
 * SPDX-License-Identifier: MIT
 */
typedef unsigned int u32;
static unsigned char buffer[65536];
static int call(int nr, u32 a, u32 b, u32 c, u32 d, u32 e) {
    register u32 r0 __asm__("r0") = a;
    register u32 r1 __asm__("r1") = b;
    register u32 r2 __asm__("r2") = c;
    register u32 r3 __asm__("r3") = d;
    register u32 r4 __asm__("r4") = e;
    register int r7 __asm__("r7") = nr;
    __asm__ volatile("svc 0" : "+r"(r0) : "r"(r1), "r"(r2), "r"(r3), "r"(r4), "r"(r7) : "memory", "cc");
    return (int)r0;
}
__attribute__((noreturn)) static void fail(void) {
    static const char message[] = "read-range: invalid arguments or open/seek/read/write failure\n";
    call(4, 2, (u32)message, sizeof(message)-1, 0, 0);
    call(1, 1, 0, 0, 0, 0);
    __builtin_unreachable();
}
static u32 number(const char *p) {
    u32 n = 0;
    if (!*p) fail();
    for (; *p; ++p) {
        if (*p<'0' || *p>'9' || n>429496729u || (n==429496729u && *p>'5')) fail();
        n=n*10+(u32)(*p-'0');
    }
    return n;
}
__attribute__((noreturn,used)) void main_start(u32 *stack) {
    if (stack[0]!=4) fail();
    char **argv=(char **)(stack+1);
    u32 start=number(argv[2]);
    u32 count=number(argv[3]);
    if (!count || count>2097152u) fail();
    int fd=call(5, (u32)argv[1], 0, 0, 0, 0);
    if (fd<0) fail();
    u32 position[2]={0,0};
    if (call(140, (u32)fd, start>>23, start<<9, (u32)position, 0)<0) fail();
    if (position[0]!=(start<<9) || position[1]!=(start>>23)) fail();
    u32 remaining=count<<9;
    while (remaining) {
        u32 wanted=remaining<sizeof(buffer)?remaining:sizeof(buffer);
        int got=call(3, (u32)fd, (u32)buffer, wanted, 0, 0);
        if (got==-4) continue;
        if (got<=0) fail();
        u32 written=0;
        while (written<(u32)got) {
            int done=call(4, 1, (u32)(buffer+written), (u32)got-written, 0, 0);
            if (done==-4) continue;
            if (done<=0) fail();
            written+=(u32)done;
        }
        remaining-=(u32)got;
    }
    call(6, (u32)fd, 0, 0, 0, 0);
    call(1, 0, 0, 0, 0, 0);
    __builtin_unreachable();
}
__attribute__((naked,noreturn)) void _start(void) {
    __asm__ volatile("mov r0, sp\nb main_start");
}
