#include <unistd.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    long n = 0;
    if (argc > 1) { char *s = argv[1]; while (*s) n = n*10 + (*s++ - '0'); }
    for (long i = 0; i < n; i++) unlink("/tmp/fgen_test");
    return 0;
}
