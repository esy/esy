#include <stdio.h>
#include "dep.h"

int main(int argc, char **argv) {
  printf("message from dep: %s\n", dep_hello());
  return 0;
}
