#define _GNU_SOURCE
#include <unistd.h>
#include <sys/syscall.h>
#include <sys/mman.h>
#include <linux/futex.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>

/* Emits exactly the futex op sequence the GhostLock chain uses
 * (LOCK_PI -> WAIT_REQUEUE_PI -> CMP_REQUEUE_PI), public and private.
 * cmpval/waitval mismatch so every call returns immediately.
 * `hold` argument: stay alive afterwards, so an enforcer can kill us. */

static void call(const char *name, int op, int *uaddr, int val, int *uaddr2, int val3) {
    errno = 0;
    long r = syscall(SYS_futex, uaddr, op, val, NULL, uaddr2, val3);
    printf("%-28s op=%-4d ret=%ld errno=%s\n", name, op, r,
           (r == -1) ? strerror(errno) : "ok");
    fflush(stdout);
}

int main(int argc, char **argv) {
    int *f = mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANONYMOUS, -1, 0);
    int *g = mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANONYMOUS, -1, 0);

    call("LOCK_PI",              FUTEX_LOCK_PI,  f, 0, NULL, 0);
    call("LOCK_PI|PRIVATE",      FUTEX_LOCK_PI|FUTEX_PRIVATE_FLAG, g, 0, NULL, 0);
    call("WAIT_REQUEUE_PI",      FUTEX_WAIT_REQUEUE_PI, g, 1, f, 0);
    call("WAIT_REQUEUE_PI|PRIV", FUTEX_WAIT_REQUEUE_PI|FUTEX_PRIVATE_FLAG, g, 1, f, 0);
    call("CMP_REQUEUE_PI",       FUTEX_CMP_REQUEUE_PI, f, 1, g, 1);
    call("CMP_REQUEUE_PI|PRIV",  FUTEX_CMP_REQUEUE_PI|FUTEX_PRIVATE_FLAG, f, 1, g, 1);
    call("UNLOCK_PI",            FUTEX_UNLOCK_PI, f, 0, NULL, 0);
    call("UNLOCK_PI|PRIVATE",    FUTEX_UNLOCK_PI|FUTEX_PRIVATE_FLAG, g, 0, NULL, 0);

    if (argc > 1 && strcmp(argv[1], "hold") == 0) {
        printf("HOLDING pid=%d\n", getpid());
        fflush(stdout);
        pause();   /* enforcer has a window to act */
    }
    return 0;
}
