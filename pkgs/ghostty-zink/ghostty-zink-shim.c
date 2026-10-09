/*
 * ghostty-zink-shim.c — LD_PRELOAD shim so Ghostty uses Zink (GL-on-Vulkan)
 * on Mali G610 where native desktop OpenGL is unfortunately limited to 3.1.
 *
 * Ghostty (a GTK4 app) sets GDK_DISABLE=gles-api,vulkan in its process.
 * Disabling vulkan there appears to make Zink unable to pick a physical
 * device ("ZINK: failed to choose pdev"), so Ghostty then falls back to
 * software (llvmpipe) rendering, which is unusably slow on this tablet.
 *
 * Zink is a GL loader that translates desktop GL onto a Vulkan driver
 * (here Mesa PANVK on the Mali G610). If we remove the vulkan token in
 * GDK_DISABLE and keep MESA_LOADER_DRIVER_OVERRIDE=zink, GTK's GL loader
 * creates a proper hardware desktop GL >= 3.3 context using Zink, which is
 * what Ghostty needs.
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef int (*orig_setenv_t)(const char *, const char *, int);
typedef int (*orig_g_setenv_t)(const char *, const char *, int);

static void *(*real_dlsym)(void *, const char *);

/* Buffer big enough for a rewritten GDK_DISABLE value. */
static char buf[512];

/* Drop a comma-separated token from a list value. */
static const char *drop_token(const char *value, const char *drop) {
  if (!value)
    return value;
  char *out = buf;
  const char *p = value;
  int first = 1;
  size_t dlen = strlen(drop);
  while (*p) {
    const char *start = p;
    while (*p && *p != ',')
      p++;
    size_t len = p - start;
    if (!(len == dlen && memcmp(start, drop, dlen) == 0)) {
      if (!first)
        *out++ = ',';
      memcpy(out, start, len);
      out += len;
      first = 0;
    }
    if (*p == ',')
      p++;
  }
  *out = '\0';
  return buf;
}

static const char *fix_gdk_disable(const char *value) {
  const char *v = value;
  v = drop_token(v, "vulkan");
  v = drop_token(v, "gles-api");
  return v;
}

int setenv(const char *name, const char *value, int overwrite) {
  orig_setenv_t real = (orig_setenv_t)real_dlsym(RTLD_NEXT, "setenv");
  const char *fixed = value;
  if (name && strcmp(name, "GDK_DISABLE") == 0)
    fixed = fix_gdk_disable(value);
  return real(name, fixed, overwrite);
}

/* GTK4 apps often go through g_setenv (glib) rather than just setenv. */
int g_setenv(const char *name, const char *value, int overwrite) {
  orig_g_setenv_t real = (orig_g_setenv_t)real_dlsym(RTLD_NEXT, "g_setenv");
  const char *fixed = value;
  if (name && strcmp(name, "GDK_DISABLE") == 0)
    fixed = fix_gdk_disable(value);
  return real(name, fixed, overwrite);
}

__attribute__((constructor)) static void shim_init(void) {
  real_dlsym =
      (void *(*)(void *, const char *))dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.34");
  if (!real_dlsym)
    real_dlsym = (void *(*)(void *, const char *))dlvsym(RTLD_NEXT, "dlsym",
                                                         "GLIBC_2.17");

  /* Force Zink regardless of what the wrapper sets. */
  setenv("MESA_LOADER_DRIVER_OVERRIDE", "zink", 1);
  /* Ensure we are NOT forcing software rendering. */
  setenv("LIBGL_ALWAYS_SOFTWARE", "0", 1);
}
