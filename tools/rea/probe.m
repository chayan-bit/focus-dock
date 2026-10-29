// Read-only probe: dlsym existence + getter-only calls. No setters, no injection.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <CoreGraphics/CoreGraphics.h>
#import <mach-o/dyld.h>
#import <mach-o/nlist.h>
#import <objc/runtime.h>
#include <string.h>
static void *findLocal(const char *img, const char *sym) {
  for (uint32_t i = 0; i < _dyld_image_count(); i++) {
    if (strcmp(_dyld_get_image_name(i), img)) continue;
    const struct mach_header_64 *h = (void *)_dyld_get_image_header(i); intptr_t slide = _dyld_get_image_vmaddr_slide(i);
    const struct load_command *lc = (void *)(h + 1); struct segment_command_64 *le = 0; struct symtab_command *st = 0;
    for (uint32_t c = 0; c < h->ncmds; c++, lc = (void *)((char *)lc + lc->cmdsize)) {
      if (lc->cmd == LC_SEGMENT_64 && !strcmp(((struct segment_command_64 *)lc)->segname, "__LINKEDIT")) le = (void *)lc;
      if (lc->cmd == LC_SYMTAB) st = (void *)lc; }
    if (!le || !st) return NULL;
    uintptr_t base = le->vmaddr + slide - le->fileoff;
    struct nlist_64 *nl = (void *)(base + st->symoff); const char *strs = (void *)(base + st->stroff);
    for (uint32_t k = 0; k < st->nsyms; k++) if (!strcmp(strs + nl[k].n_un.n_strx, sym)) return (void *)(nl[k].n_value + slide);
    printf("  in-memory symtab nsyms=%u (local not found)\n", st->nsyms); }
  return NULL; }
int main(int argc, char **argv) {
  void *sl = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW);
  for (int i = 1; i < argc; i++) printf("%s %s\n", dlsym(sl, argv[i]) || dlsym(RTLD_DEFAULT, argv[i]) ? "FOUND  " : "MISSING", argv[i]);
  void *loc = findLocal("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation");
  printf("local SLSPerformAsynchronousBridgedWindowManagementOperation via in-memory symtab: %s\n", loc ? "FOUND" : "MISSING");
  printf("class SLSBridgedMoveWindowsToManagedSpaceOperation: %s\n", objc_getClass("SLSBridgedMoveWindowsToManagedSpaceOperation") ? "FOUND" : "MISSING");
  // getters only
  int (*cid)(void) = dlsym(sl, "SLSMainConnectionID"); int c = cid();
  CFArrayRef (*spaces)(int) = dlsym(sl, "SLSCopyManagedDisplaySpaces"); CFArrayRef sp = spaces(c);
  long n = 0; for (CFIndex d = 0; d < CFArrayGetCount(sp); d++) n += CFArrayGetCount(CFDictionaryGetValue(CFArrayGetValueAtIndex(sp, d), CFSTR("Spaces")));
  printf("getter SLSCopyManagedDisplaySpaces: displays=%ld spaces=%ld\n", (long)CFArrayGetCount(sp), n);
  int (*mode)(int) = dlsym(sl, "SLSGetSpaceManagementMode"); printf("getter SLSGetSpaceManagementMode=%d\n", mode(c));
  bool (*mbah)(int, bool *) = dlsym(sl, "CGSGetMenuBarAutohideEnabled"); bool ah = 0; mbah(c, &ah); printf("getter CGSGetMenuBarAutohideEnabled=%d\n", ah);
  bool (*sec)(void) = dlsym(sl, "CGSIsSecureEventInputSet"); printf("getter CGSIsSecureEventInputSet=%d\n", sec());
  bool (*hk)(int) = dlsym(sl, "CGSIsSymbolicHotKeyEnabled"); printf("getter CGSIsSymbolicHotKeyEnabled(1 cmd-tab)=%d\n", hk(1));
  CFArrayRef wl = CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID); printf("public CGWindowListCopyWindowInfo count=%ld\n", (long)CFArrayGetCount(wl));
  return 0; }
