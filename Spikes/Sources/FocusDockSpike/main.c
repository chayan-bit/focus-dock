// Stable loader: dlopens ../../../libSpikeKit.dylib (next to the .app) and calls spike_main.
// Keep this file unchanged: its cdhash is what TCC remembers for FocusDockSpike.app.
#include <dlfcn.h>
#include <libgen.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  char exe[PATH_MAX], real[PATH_MAX], lib[PATH_MAX * 2];
  uint32_t size = sizeof(exe);
  if (_NSGetExecutablePath(exe, &size) != 0 || !realpath(exe, real)) return 70;
  // real = <dir>/FocusDockSpike.app/Contents/MacOS/FocusDockSpike
  char *d = dirname(real);
  snprintf(lib, sizeof(lib), "%s/../../../libSpikeKit.dylib", d);
  void *h = dlopen(lib, RTLD_NOW);
  if (!h) { fprintf(stderr, "dlopen failed: %s\n", dlerror()); return 71; }
  int (*entry)(int, char **) = (int (*)(int, char **))dlsym(h, "spike_main");
  if (!entry) { fprintf(stderr, "spike_main missing\n"); return 72; }
  return entry(argc, argv);
}
