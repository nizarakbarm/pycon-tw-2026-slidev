#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

int main(int argc, char **argv) {
  long n = 0;
  if (argc > 1) {
    char *s = argv[1];
    while (*s)
      n = n * 10 + (*s++ - '0');
  }
  for (long i = 0; i < n; i++) {
    pid_t p = fork();
    if (p == 0) {
      execl("/bin/true", "true", (char *)NULL);
      _exit(127);
    }
    waitpid(p, NULL, 0);
  }
  return 0;
}
