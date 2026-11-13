/*
 * fydetab-boot-menu-ui -- tiny framebuffer generation picker for the initrd.
 *
 * The shell script owns everything that is Nix-specific (finding generations,
 * kexec).  This helper only draws a menu and reports which row was chosen.
 * It draws through a DRM dumb buffer (the vendor kernel's fbdev mmap is
 * broken) and reads raw evdev events, so it does not depend on the VT
 * keyboard layer (which mangles escape sequences).
 */
#define _GNU_SOURCE

#include <drm/drm.h>
#include <drm/drm_fourcc.h>
#include <drm/drm_mode.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/kd.h>
#include <math.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

/* drm_mode.h does not carry the kernel-internal connection enum. */
#ifndef DRM_MODE_CONNECTED
#define DRM_MODE_CONNECTED 1
#endif

#define UI_W 2560
#define UI_H 1600
#define MAX_ENTRIES 9

#define MARGIN 176
#define RIGHT (UI_W - MARGIN)
#define BRAND_Y 112
#define ROWS_TOP 400
#define ROW_STEP 132
#define ROW_BASELINE 78

/* FydeTab's wordmark pink and a restrained monochrome palette. */
#define C_PINK 0x00E40046u
#define C_WHITE 0x00FFFFFFu
#define C_BODY 0x00CBD8D8u
#define C_MUTED 0x0096ABADu
#define C_DIM 0x006F8587u

#define FONT_MAGIC 0x464D4246u /* FBMF */
#define BG_MAGIC 0x424D4246u   /* FBMB */

typedef struct {
    int32_t advance_fp;
    int32_t xoff;
    int32_t yoff;
    uint32_t w;
    uint32_t h;
    uint32_t ax;
    uint32_t ay;
} Glyph;

typedef struct {
    uint32_t size;
    uint32_t ascent;
    uint32_t descent;
    uint32_t first;
    uint32_t count;
    uint32_t atlas_w;
    uint32_t atlas_h;
    Glyph glyphs[96];
    const uint8_t *atlas;
} Font;

typedef struct {
    int n;
    char num[MAX_ENTRIES][16];
    char date[MAX_ENTRIES][40];
    int is_default[MAX_ENTRIES];
} Menu;

typedef struct {
    int timeout;
    int rotation;
    const char *tty;
    const char *assets;
    const char *render;
    int selected;
    int default_slot;
    int paused;
    int left;
} Options;

static uint32_t *canvas;
static uint32_t *bg_canvas;

/* ------------------------------------------------------------------ utils */

static uint8_t *read_file(const char *path, size_t *len)
{
    FILE *f = fopen(path, "rb");
    if (!f)
        return NULL;
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return NULL;
    }
    long size = ftell(f);
    if (size <= 0) {
        fclose(f);
        return NULL;
    }
    rewind(f);
    uint8_t *buf = malloc((size_t)size);
    if (!buf) {
        fclose(f);
        return NULL;
    }
    if (fread(buf, 1, (size_t)size, f) != (size_t)size) {
        free(buf);
        fclose(f);
        return NULL;
    }
    fclose(f);
    *len = (size_t)size;
    return buf;
}

static inline uint32_t blend(uint32_t dst, uint32_t src, int a)
{
    if (a <= 0)
        return dst;
    if (a >= 255)
        return src;
    int dr = (int)((dst >> 16) & 0xff), dg = (int)((dst >> 8) & 0xff), db = (int)(dst & 0xff);
    int sr = (int)((src >> 16) & 0xff), sg = (int)((src >> 8) & 0xff), sb = (int)(src & 0xff);
    int r = (sr * a + dr * (255 - a)) / 255;
    int g = (sg * a + dg * (255 - a)) / 255;
    int b = (sb * a + db * (255 - a)) / 255;
    return ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b;
}

static inline uint32_t add_sat(uint32_t dst, int r, int g, int b)
{
    int dr = (int)((dst >> 16) & 0xff) + r;
    int dg = (int)((dst >> 8) & 0xff) + g;
    int db = (int)(dst & 0xff) + b;
    if (dr > 255) dr = 255;
    if (dg > 255) dg = 255;
    if (db > 255) db = 255;
    return ((uint32_t)dr << 16) | ((uint32_t)dg << 8) | (uint32_t)db;
}

/* ---------------------------------------------------------------- assets */

static char *asset_path(const char *assets, const char *name)
{
    static char buf[4096];
    snprintf(buf, sizeof buf, "%s/%s", assets, name);
    return buf;
}

static char *default_assets_dir(void)
{
    static char dir[4096];
    ssize_t n = readlink("/proc/self/exe", dir, sizeof dir - 1);
    if (n <= 0)
        return NULL;
    dir[n] = '\0';
    char *slash = strrchr(dir, '/');
    if (!slash)
        return NULL;
    *slash = '\0';
    slash = strrchr(dir, '/');
    if (!slash)
        return NULL;
    *slash = '\0';
    snprintf(dir + strlen(dir), sizeof dir - strlen(dir), "/share/fydetab-boot-menu-ui");
    return dir;
}

static int font_load(Font *font, const char *path)
{
    size_t len = 0;
    uint8_t *storage = read_file(path, &len);
    if (!storage || len < 40)
        return -1;

    const uint32_t *h = (const uint32_t *)storage;
    if (h[0] != FONT_MAGIC || h[1] != 1)
        return -1;

    font->size = h[2];
    font->ascent = h[3];
    font->descent = h[4];
    font->first = h[6];
    font->count = h[7];
    font->atlas_w = h[8];
    font->atlas_h = h[9];
    if (font->count > 96)
        return -1;

    const uint32_t *p = h + 10;
    for (uint32_t i = 0; i < font->count; i++) {
        font->glyphs[i].advance_fp = (int32_t)p[0];
        font->glyphs[i].xoff = (int32_t)p[1];
        font->glyphs[i].yoff = (int32_t)p[2];
        font->glyphs[i].w = p[3];
        font->glyphs[i].h = p[4];
        font->glyphs[i].ax = p[5];
        font->glyphs[i].ay = p[6];
        p += 7;
    }
    font->atlas = (const uint8_t *)p;
    (void)len;
    return 0;
}

static const uint8_t *bg_pixels;
static int bg_w, bg_h;

static const uint8_t *brand_pixels;
static int brand_w, brand_h;

static int image_load(const char *path, const uint8_t **pixels, int *w, int *h)
{
    size_t len = 0;
    uint8_t *buf = read_file(path, &len);
    if (!buf || len < 16)
        return -1;
    const uint32_t *header = (const uint32_t *)buf;
    if (header[0] != BG_MAGIC || header[1] != 1)
        return -1;
    *w = (int)header[2];
    *h = (int)header[3];
    if (len < 16 + (size_t)(*w) * (size_t)(*h) * 2)
        return -1;
    *pixels = buf + 16;
    return 0;
}

/* ---------------------------------------------------------------- text */

static int glyph_index(const Font *font, unsigned char c)
{
    int i = (int)c - (int)font->first;
    if (i < 0 || i >= (int)font->count)
        i = '?' - (int)font->first;
    return i;
}

static int text_width(const Font *font, const char *s, int spacing)
{
    int w = 0;
    for (const unsigned char *p = (const unsigned char *)s; *p; p++)
        w += (font->glyphs[glyph_index(font, *p)].advance_fp + 8) / 16 + spacing;
    return w;
}

static int draw_text(const Font *font, int x, int baseline, const char *s,
                     uint32_t color, int alpha, int spacing)
{
    int pen = x;
    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        const Glyph *g = &font->glyphs[glyph_index(font, *p)];
        int px = pen + g->xoff;
        int py = baseline + g->yoff;
        for (uint32_t gy = 0; gy < g->h; gy++) {
            int y = py + (int)gy;
            if (y < 0 || y >= UI_H)
                continue;
            const uint8_t *row = font->atlas + (size_t)(g->ay + gy) * font->atlas_w + g->ax;
            for (uint32_t gx = 0; gx < g->w; gx++) {
                int xx = px + (int)gx;
                if (xx < 0 || xx >= UI_W)
                    continue;
                int a = row[gx] * alpha / 255;
                if (!a)
                    continue;
                uint32_t *dst = &canvas[y * UI_W + xx];
                *dst = blend(*dst, color, a);
            }
        }
        pen += (g->advance_fp + 8) / 16 + spacing;
    }
    return pen;
}

/* ------------------------------------------------------------ background */

static inline void bg_sample(float fx, float fy, int *r, int *g, int *b)
{
    if (fx < 0.0f)
        fx = 0.0f;
    if (fy < 0.0f)
        fy = 0.0f;
    if (fx > (float)(bg_w - 1))
        fx = (float)(bg_w - 1);
    if (fy > (float)(bg_h - 1))
        fy = (float)(bg_h - 1);

    int x0 = (int)fx, y0 = (int)fy;
    int x1 = x0 + 1 < bg_w ? x0 + 1 : x0;
    int y1 = y0 + 1 < bg_h ? y0 + 1 : y0;
    float tx = fx - (float)x0, ty = fy - (float)y0;

    const uint8_t *p00 = bg_pixels + ((size_t)y0 * bg_w + x0) * 2;
    const uint8_t *p10 = bg_pixels + ((size_t)y0 * bg_w + x1) * 2;
    const uint8_t *p01 = bg_pixels + ((size_t)y1 * bg_w + x0) * 2;
    const uint8_t *p11 = bg_pixels + ((size_t)y1 * bg_w + x1) * 2;
    uint16_t c00 = (uint16_t)(p00[0] | (p00[1] << 8));
    uint16_t c10 = (uint16_t)(p10[0] | (p10[1] << 8));
    uint16_t c01 = (uint16_t)(p01[0] | (p01[1] << 8));
    uint16_t c11 = (uint16_t)(p11[0] | (p11[1] << 8));

    float w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty);
    float w01 = (1 - tx) * ty, w11 = tx * ty;

    int rr = (int)(((c00 >> 11) & 31) * w00 + ((c10 >> 11) & 31) * w10 +
                   ((c01 >> 11) & 31) * w01 + ((c11 >> 11) & 31) * w11);
    int gg = (int)(((c00 >> 5) & 63) * w00 + ((c10 >> 5) & 63) * w10 +
                   ((c01 >> 5) & 63) * w01 + ((c11 >> 5) & 63) * w11);
    int bb = (int)((c00 & 31) * w00 + (c10 & 31) * w10 +
                   (c01 & 31) * w01 + (c11 & 31) * w11);

    *r = rr * 255 / 31;
    *g = gg * 255 / 63;
    *b = bb * 255 / 31;
}

static void draw_background_rect(int x0, int y0, int w, int h)
{
    for (int y = y0; y < y0 + h; y++) {
        if (y < 0 || y >= UI_H)
            continue;
        float fy = ((float)y + 0.5f) * (float)bg_h / (float)UI_H - 0.5f;
        float vy = ((float)y / (float)UI_H) * 2.0f - 1.0f;
        for (int x = x0; x < x0 + w; x++) {
            if (x < 0 || x >= UI_W)
                continue;
            float fx = ((float)x + 0.5f) * (float)bg_w / (float)UI_W - 0.5f;
            int r, g, b;
            bg_sample(fx, fy, &r, &g, &b);

            float vx = ((float)x / (float)UI_W) * 2.0f - 1.0f;
            float vig = 1.0f - 0.55f * (0.55f * vx * vx + 0.55f * vy * vy);
            float dim = (0.50f - 0.14f * ((float)y / (float)UI_H)) * vig;

            int rr = (int)((float)r * 0.62f * dim + 1.0f);
            int gg = (int)((float)g * 0.84f * dim + 2.0f);
            int bb = (int)((float)b * 1.00f * dim + 3.0f);
            if (rr > 255) rr = 255;
            if (gg > 255) gg = 255;
            if (bb > 255) bb = 255;
            canvas[y * UI_W + x] = ((uint32_t)rr << 16) | ((uint32_t)gg << 8) | (uint32_t)bb;
        }
    }
}

static void draw_brand(void)
{
    if (!brand_pixels)
        return;
    for (int y = 0; y < brand_h; y++) {
        int dy = BRAND_Y + y;
        if (dy < 0 || dy >= UI_H)
            continue;
        for (int x = 0; x < brand_w; x++) {
            int dx = MARGIN + x;
            if (dx < 0 || dx >= UI_W)
                continue;
            const uint8_t *p = brand_pixels + ((size_t)y * brand_w + x) * 2;
            uint16_t c = (uint16_t)(p[0] | (p[1] << 8));
            int r = ((c >> 11) & 31) * 255 / 31;
            int g = ((c >> 5) & 63) * 255 / 63;
            int b = (c & 31) * 255 / 31;
            if (!r && !g && !b)
                continue;
            uint32_t *dst = &canvas[dy * UI_W + dx];
            *dst = add_sat(*dst, r, g, b);
        }
    }
}

/* --------------------------------------------------------------- layout */

static Menu menu;
static Options opt;
static const Font *font_small;
static const Font *font_mid;
static const Font *font_big;

static void draw_rows(void)
{
    for (int i = 0; i < menu.n; i++) {
        int y = ROWS_TOP + i * ROW_STEP;
        int baseline = y + ROW_BASELINE;
        int sel = (i == opt.selected);

        if (sel)
            draw_text(font_big, MARGIN, baseline, ">", C_PINK, 255, 0);

        draw_text(font_big, MARGIN + 64, baseline, menu.num[i],
                  sel ? C_WHITE : C_BODY, 255, 0);
        draw_text(font_mid, MARGIN + 420, baseline, menu.date[i],
                  sel ? C_BODY : C_MUTED, 255, 0);

        if (menu.is_default[i]) {
            const char *label = "(current)";
            int tw = text_width(font_small, label, 0);
            draw_text(font_small, RIGHT - tw, baseline, label,
                      sel ? C_PINK : 0x00B8456Du, 255, 0);
        }
    }
}

static void draw_footer(void)
{
    int baseline = UI_H - 96;

    struct { const char *text; uint32_t color; } parts[] = {
        { "Up / Down", C_MUTED },
        { "  select      ", C_DIM },
        { "1-9", C_MUTED },
        { "  jump      ", C_DIM },
        { "Enter", C_MUTED },
        { "  boot      ", C_DIM },
        { "T", C_MUTED },
        { "  default", C_DIM },
    };
    int x = MARGIN;
    for (size_t i = 0; i < sizeof parts / sizeof parts[0]; i++)
        x = draw_text(font_small, x, baseline, parts[i].text, parts[i].color, 255, 0);

    const char *status;
    char buffer[64];
    uint32_t color;
    if (opt.paused) {
        status = "Paused";
        color = C_PINK;
    } else {
        snprintf(buffer, sizeof buffer, "Booting in %ds", opt.left);
        status = buffer;
        color = C_MUTED;
    }
    int tw = text_width(font_small, status, 0);
    draw_text(font_small, RIGHT - tw, baseline, status, color, 255, 0);
}

/* --------------------------------------------------------------- screen */

typedef struct {
    int fd;
    uint32_t *mem;
    size_t len;
    int w, h, stride;
    int rotation;
    uint32_t handle;
    uint32_t fb_id;
    int master;
} Screen;

static Screen screen;

static void screen_close(Screen *s)
{
    if (s->mem) {
        munmap(s->mem, s->len);
        s->mem = NULL;
    }
    if (s->fd >= 0) {
        if (s->fb_id) {
            uint32_t id = s->fb_id;
            ioctl(s->fd, DRM_IOCTL_MODE_RMFB, &id);
        }
        if (s->handle) {
            struct drm_mode_destroy_dumb destroy = { .handle = s->handle };
            ioctl(s->fd, DRM_IOCTL_MODE_DESTROY_DUMB, &destroy);
        }
        if (s->master)
            ioctl(s->fd, DRM_IOCTL_DROP_MASTER, 0);
        close(s->fd);
    }
    s->fd = -1;
}

/*
 * The vendor kernel's fbdev mmap is broken (rockchip_gem_mmap_buf maps the
 * object twice, so the second vm_insert_page fails with -EBUSY).  Go through
 * DRM directly instead: a dumb buffer is mappable, and we take over the CRTC
 * for as long as the menu is on screen.
 */
static int screen_open_node(Screen *s, const char *node, int rotation)
{
    memset(s, 0, sizeof *s);
    s->fd = open(node, O_RDWR | O_CLOEXEC);
    if (s->fd < 0) {
        perror(node);
        return -1;
    }

    int master_ok = 0;
    for (int attempt = 0; attempt < 20; attempt++) {
        if (ioctl(s->fd, DRM_IOCTL_SET_MASTER, 0) == 0) {
            master_ok = 1;
            break;
        }
        /* Plymouth may still be winding down and holding the master lock. */
        usleep(100000);
    }
    if (!master_ok) {
        perror("fydetab-menu: DRM_IOCTL_SET_MASTER");
        screen_close(s);
        return -1;
    }
    s->master = 1;

    struct drm_mode_card_res res;
    memset(&res, 0, sizeof res);
    if (ioctl(s->fd, DRM_IOCTL_MODE_GETRESOURCES, &res) < 0) {
        perror("fydetab-menu: MODE_GETRESOURCES");
        screen_close(s);
        return -1;
    }

    uint32_t *connectors = calloc(res.count_connectors, sizeof *connectors);
    uint32_t *crtcs = calloc(res.count_crtcs, sizeof *crtcs);
    uint32_t *encoders = calloc(res.count_encoders, sizeof *encoders);
    if (!connectors || !crtcs || !encoders) {
        fprintf(stderr, "fydetab-menu: out of memory reading DRM resources\n");
        free(connectors);
        free(crtcs);
        free(encoders);
        screen_close(s);
        return -1;
    }

    res.connector_id_ptr = (uint64_t)(uintptr_t)connectors;
    res.crtc_id_ptr = (uint64_t)(uintptr_t)crtcs;
    res.encoder_id_ptr = (uint64_t)(uintptr_t)encoders;
    if (ioctl(s->fd, DRM_IOCTL_MODE_GETRESOURCES, &res) < 0) {
        perror("fydetab-menu: MODE_GETRESOURCES (ids)");
        free(connectors);
        free(crtcs);
        free(encoders);
        screen_close(s);
        return -1;
    }

    uint32_t connector_id = 0, crtc_id = 0;
    struct drm_mode_modeinfo mode;
    memset(&mode, 0, sizeof mode);

    for (uint32_t i = 0; i < res.count_connectors && !connector_id; i++) {
        struct drm_mode_get_connector conn;
        memset(&conn, 0, sizeof conn);
        conn.connector_id = connectors[i];
        if (ioctl(s->fd, DRM_IOCTL_MODE_GETCONNECTOR, &conn) < 0)
            continue;
        if (conn.connection != DRM_MODE_CONNECTED)
            continue;

        uint32_t crtc = 0;
        if (conn.encoder_id) {
            struct drm_mode_get_encoder enc;
            memset(&enc, 0, sizeof enc);
            enc.encoder_id = conn.encoder_id;
            if (ioctl(s->fd, DRM_IOCTL_MODE_GETENCODER, &enc) == 0)
                crtc = enc.crtc_id;
        }
        if (!crtc && res.count_crtcs)
            crtc = crtcs[0];

        /* Reuse the mode the console was already using; do not mode-set. */
        struct drm_mode_crtc current;
        memset(&current, 0, sizeof current);
        current.crtc_id = crtc;
        if (!crtc || ioctl(s->fd, DRM_IOCTL_MODE_GETCRTC, &current) < 0)
            continue;
        if (!current.mode_valid)
            continue;

        connector_id = conn.connector_id;
        crtc_id = crtc;
        mode = current.mode;
    }

    free(connectors);
    free(crtcs);
    free(encoders);

    if (!connector_id) {
        fprintf(stderr, "fydetab-menu: no connected display with an active mode\n");
        screen_close(s);
        return -1;
    }

    s->w = (int)mode.hdisplay;
    s->h = (int)mode.vdisplay;
    s->rotation = rotation;

    if (s->w == UI_W && s->h == UI_H)
        s->rotation = 0;
    else if (!(s->w == UI_H && s->h == UI_W && (rotation == 90 || rotation == 270))) {
        fprintf(stderr, "fydetab-menu: unexpected display mode %dx%d\n", s->w, s->h);
        screen_close(s);
        return -1;
    }

    struct drm_mode_create_dumb dumb;
    memset(&dumb, 0, sizeof dumb);
    dumb.width = (uint32_t)s->w;
    dumb.height = (uint32_t)s->h;
    dumb.bpp = 32;
    if (ioctl(s->fd, DRM_IOCTL_MODE_CREATE_DUMB, &dumb) < 0) {
        perror("fydetab-menu: MODE_CREATE_DUMB");
        screen_close(s);
        return -1;
    }
    s->handle = dumb.handle;
    s->stride = (int)(dumb.pitch / 4);
    s->len = dumb.size;

    struct drm_mode_map_dumb map;
    memset(&map, 0, sizeof map);
    map.handle = dumb.handle;
    if (ioctl(s->fd, DRM_IOCTL_MODE_MAP_DUMB, &map) < 0) {
        perror("fydetab-menu: MODE_MAP_DUMB");
        screen_close(s);
        return -1;
    }

    s->mem = mmap(NULL, s->len, PROT_READ | PROT_WRITE, MAP_SHARED, s->fd,
                  (off_t)map.offset);
    if (s->mem == MAP_FAILED) {
        perror("fydetab-menu: mmap dumb buffer");
        s->mem = NULL;
        screen_close(s);
        return -1;
    }

    struct drm_mode_fb_cmd2 fb;
    memset(&fb, 0, sizeof fb);
    fb.width = (uint32_t)s->w;
    fb.height = (uint32_t)s->h;
    fb.pixel_format = DRM_FORMAT_XRGB8888;
    fb.handles[0] = dumb.handle;
    fb.pitches[0] = dumb.pitch;
    if (ioctl(s->fd, DRM_IOCTL_MODE_ADDFB2, &fb) < 0) {
        /* Some vendor kernels only implement the legacy entry point. */
        struct drm_mode_fb_cmd legacy;
        memset(&legacy, 0, sizeof legacy);
        legacy.width = dumb.width;
        legacy.height = dumb.height;
        legacy.pitch = dumb.pitch;
        legacy.bpp = 32;
        legacy.depth = 24;
        legacy.handle = dumb.handle;
        if (ioctl(s->fd, DRM_IOCTL_MODE_ADDFB, &legacy) < 0) {
            perror("fydetab-menu: MODE_ADDFB2 / MODE_ADDFB");
            screen_close(s);
            return -1;
        }
        fb.fb_id = legacy.fb_id;
    }
    s->fb_id = fb.fb_id;

    struct drm_mode_crtc set;
    memset(&set, 0, sizeof set);
    set.crtc_id = crtc_id;
    set.fb_id = fb.fb_id;
    set.set_connectors_ptr = (uint64_t)(uintptr_t)&connector_id;
    set.count_connectors = 1;
    set.mode = mode;
    set.mode_valid = 1;
    if (ioctl(s->fd, DRM_IOCTL_MODE_SETCRTC, &set) < 0) {
        perror("fydetab-menu: MODE_SETCRTC");
        screen_close(s);
        return -1;
    }

    fprintf(stderr, "fydetab-menu: %dx%d dumb buffer, connector %u, crtc %u\n",
            s->w, s->h, connector_id, crtc_id);
    return 0;
}

static int screen_open(Screen *s, int rotation)
{
    static const char *nodes[] = { "/dev/dri/card0", "/dev/dri/card1" };
    for (size_t i = 0; i < sizeof nodes / sizeof nodes[0]; i++) {
        if (screen_open_node(s, nodes[i], rotation) == 0)
            return 0;
    }
    fprintf(stderr, "fydetab-menu: no usable DRM device\n");
    return -1;
}

static void push_rect(int x0, int y0, int w, int h)
{
    if (x0 < 0)
        x0 = 0;
    if (y0 < 0)
        y0 = 0;
    if (x0 + w > UI_W)
        w = UI_W - x0;
    if (y0 + h > UI_H)
        h = UI_H - y0;
    if (w <= 0 || h <= 0)
        return;

    for (int y = y0; y < y0 + h; y++) {
        for (int x = x0; x < x0 + w; x++) {
            int fx, fy;
            if (screen.rotation == 0) {
                fx = x;
                fy = y;
            } else if (screen.rotation == 90) {
                fx = y;
                fy = screen.h - 1 - x;
            } else {
                fx = screen.w - 1 - y;
                fy = x;
            }
            screen.mem[(size_t)fy * screen.stride + fx] = canvas[y * UI_W + x];
        }
    }
}

/* -------------------------------------------------------------- compose */

static void compose_static(void)
{
    draw_background_rect(0, 0, UI_W, UI_H);
    draw_brand();
    memcpy(bg_canvas, canvas, (size_t)UI_W * UI_H * sizeof(uint32_t));
}

static void compose_rows(void)
{
    int x0 = MARGIN - 8;
    int y0 = ROWS_TOP - 24;
    int w = RIGHT - MARGIN + 16;
    int h = menu.n * ROW_STEP + 48;

    for (int y = y0; y < y0 + h; y++) {
        if (y < 0 || y >= UI_H)
            continue;
        memcpy(&canvas[y * UI_W + x0], &bg_canvas[y * UI_W + x0],
               (size_t)w * sizeof(uint32_t));
    }
    draw_rows();
    push_rect(x0, y0, w, h);
}

static void compose_footer(void)
{
    int y0 = UI_H - 160;
    int h = 160;
    for (int y = y0; y < UI_H; y++)
        memcpy(&canvas[y * UI_W], &bg_canvas[y * UI_W],
               (size_t)UI_W * sizeof(uint32_t));
    draw_footer();
    push_rect(0, y0, UI_W, h);
}

/* ----------------------------------------------------------------- input */

static int open_inputs(int *fds, int max)
{
    int n = 0;
    for (int i = 0; i < 32 && n < max; i++) {
        char path[64];
        snprintf(path, sizeof path, "/dev/input/event%d", i);
        int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0)
            continue;

        uint8_t evbit[(EV_MAX / 8) + 1] = { 0 };
        if (ioctl(fd, EVIOCGBIT(0, sizeof evbit), evbit) < 0 ||
            !(evbit[EV_KEY / 8] & (1u << (EV_KEY % 8)))) {
            close(fd);
            continue;
        }

        uint8_t keybit[(KEY_MAX / 8) + 1] = { 0 };
        if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof keybit), keybit) < 0) {
            close(fd);
            continue;
        }
#define HAS_KEY(k) (keybit[(k) / 8] & (1u << ((k) % 8)))
        if (!(HAS_KEY(KEY_UP) || HAS_KEY(KEY_DOWN) || HAS_KEY(KEY_ENTER) ||
              HAS_KEY(KEY_VOLUMEUP) || HAS_KEY(KEY_VOLUMEDOWN))) {
            close(fd);
            continue;
        }
#undef HAS_KEY

        fds[n++] = fd;
    }
    return n;
}

/* ---------------------------------------------------------------- render */

static int write_ppm(const char *path)
{
    FILE *f = fopen(path, "wb");
    if (!f)
        return -1;
    fprintf(f, "P6\n%d %d\n255\n", UI_W, UI_H);
    for (int i = 0; i < UI_W * UI_H; i++) {
        uint8_t rgb[3] = {
            (uint8_t)((canvas[i] >> 16) & 0xff),
            (uint8_t)((canvas[i] >> 8) & 0xff),
            (uint8_t)(canvas[i] & 0xff),
        };
        fwrite(rgb, 1, 3, f);
    }
    fclose(f);
    return 0;
}

/* ------------------------------------------------------------------ main */

static void read_entries(void)
{
    char line[256];
    while (menu.n < MAX_ENTRIES && fgets(line, sizeof line, stdin)) {
        char *bar1 = strchr(line, '|');
        if (!bar1)
            continue;
        char *bar2 = strchr(bar1 + 1, '|');
        if (!bar2)
            continue;
        *bar1 = '\0';
        *bar2 = '\0';

        char *num = line;
        char *date = bar1 + 1;
        char *flag = bar2 + 1;
        size_t len = strlen(date);
        while (len && (date[len - 1] == '\n' || date[len - 1] == '\r'))
            date[--len] = '\0';

        snprintf(menu.num[menu.n], sizeof menu.num[0], "%.15s", num);
        snprintf(menu.date[menu.n], sizeof menu.date[0], "%.39s", date);
        menu.is_default[menu.n] = (*flag == '1');
        menu.n++;
    }
}

static int parse_option(const char *name, int argc, char **argv, int *i)
{
    if (*i + 1 >= argc) {
        fprintf(stderr, "fydetab-menu: %s needs a value\n", name);
        exit(2);
    }
    return atoi(argv[++(*i)]);
}

int main(int argc, char **argv)
{
    opt.timeout = 5;
    opt.rotation = 270;
    opt.tty = "/dev/tty2";
    opt.selected = 0;
    opt.default_slot = -1;
    opt.paused = 0;
    opt.left = -1;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--timeout"))
            opt.timeout = parse_option("--timeout", argc, argv, &i);
        else if (!strcmp(argv[i], "--rotation"))
            opt.rotation = parse_option("--rotation", argc, argv, &i);
        else if (!strcmp(argv[i], "--selected"))
            opt.selected = parse_option("--selected", argc, argv, &i);
        else if (!strcmp(argv[i], "--default"))
            opt.default_slot = parse_option("--default", argc, argv, &i);
        else if (!strcmp(argv[i], "--left"))
            opt.left = parse_option("--left", argc, argv, &i);
        else if (!strcmp(argv[i], "--paused"))
            opt.paused = 1;
        else if (!strcmp(argv[i], "--tty") && i + 1 < argc)
            opt.tty = argv[++i];
        else if (!strcmp(argv[i], "--assets") && i + 1 < argc)
            opt.assets = argv[++i];
        else if (!strcmp(argv[i], "--render") && i + 1 < argc)
            opt.render = argv[++i];
        else {
            fprintf(stderr, "fydetab-menu: unknown option %s\n", argv[i]);
            return 2;
        }
    }

    if (!opt.assets)
        opt.assets = default_assets_dir();
    if (!opt.assets) {
        fprintf(stderr, "fydetab-menu: cannot locate assets\n");
        return 1;
    }

    static Font small, mid, big;
    if (font_load(&small, asset_path(opt.assets, "font-mono-40.bin")) < 0 ||
        font_load(&mid, asset_path(opt.assets, "font-mono-46.bin")) < 0 ||
        font_load(&big, asset_path(opt.assets, "font-mono-56.bin")) < 0) {
        fprintf(stderr, "fydetab-menu: cannot load fonts from %s\n", opt.assets);
        return 1;
    }
    font_small = &small;
    font_mid = &mid;
    font_big = &big;

    if (image_load(asset_path(opt.assets, "background.bin"), &bg_pixels, &bg_w, &bg_h) < 0) {
        fprintf(stderr, "fydetab-menu: cannot load background\n");
        return 1;
    }
    if (image_load(asset_path(opt.assets, "brand.bin"), &brand_pixels, &brand_w, &brand_h) < 0)
        brand_pixels = NULL;

    read_entries();
    if (menu.n == 0) {
        fprintf(stderr, "fydetab-menu: empty menu\n");
        return 1;
    }
    if (opt.selected < 0 || opt.selected >= menu.n)
        opt.selected = 0;
    if (opt.left < 0)
        opt.left = opt.timeout;

    canvas = calloc((size_t)UI_W * UI_H, sizeof(uint32_t));
    bg_canvas = calloc((size_t)UI_W * UI_H, sizeof(uint32_t));
    if (!canvas || !bg_canvas)
        return 1;

    compose_static();
    memcpy(canvas, bg_canvas, (size_t)UI_W * UI_H * sizeof(uint32_t));

    if (opt.render) {
        draw_rows();
        draw_footer();
        return write_ppm(opt.render) == 0 ? 0 : 1;
    }

    int tty = open(opt.tty, O_RDWR | O_CLOEXEC);
    if (tty < 0) {
        perror("fydetab-menu: open tty");
        tty = open("/dev/tty1", O_RDWR | O_CLOEXEC);
    }
    if (tty < 0) {
        perror("fydetab-menu: open /dev/tty1");
        return 1;
    }
    ioctl(tty, KDSETMODE, KD_GRAPHICS);

    if (screen_open(&screen, opt.rotation) < 0) {
        ioctl(tty, KDSETMODE, KD_TEXT);
        return 1;
    }

    int fds[16];
    int nfds = 0;
    for (int attempt = 0; attempt < 20 && nfds == 0; attempt++) {
        nfds = open_inputs(fds, 16);
        if (!nfds)
            usleep(100000);
    }
    if (!nfds) {
        fprintf(stderr, "fydetab-menu: no usable input device, booting default\n");
        ioctl(tty, KDSETMODE, KD_TEXT);
        return -1;
    }

    fprintf(stderr, "fydetab-menu: %d entries, display %dx%d stride %d rot %d, %d input devices\n",
            menu.n, screen.w, screen.h, screen.stride, screen.rotation, nfds);

    draw_rows();
    draw_footer();
    push_rect(0, 0, UI_W, UI_H);

    int chosen = -1;
    for (;;) {
        struct pollfd pfds[16];
        for (int i = 0; i < nfds; i++) {
            pfds[i].fd = fds[i];
            pfds[i].events = POLLIN;
            pfds[i].revents = 0;
        }

        int ready = poll(pfds, (nfds_t)nfds, 1000);
        if (ready < 0) {
            if (errno == EINTR)
                continue;
            break;
        }

        if (ready == 0) {
            if (!opt.paused) {
                if (opt.left > 0)
                    opt.left--;
                if (opt.left <= 0)
                    break;
                compose_footer();
            }
            continue;
        }

        int rows_dirty = 0, footer_dirty = 0;
        int done = 0;
        for (int i = 0; i < nfds && !done; i++) {
            if (!(pfds[i].revents & POLLIN))
                continue;
            struct input_event ev;
            while (read(fds[i], &ev, sizeof ev) == (ssize_t)sizeof ev) {
                if (ev.type != EV_KEY || ev.value != 1)
                    continue;

                if (!opt.paused) {
                    opt.paused = 1;
                    footer_dirty = 1;
                }

                switch (ev.code) {
                case KEY_UP:
                case KEY_K:
                case KEY_VOLUMEUP:
                case KEY_PAGEUP:
                    opt.selected = (opt.selected + menu.n - 1) % menu.n;
                    rows_dirty = 1;
                    break;
                case KEY_DOWN:
                case KEY_J:
                case KEY_VOLUMEDOWN:
                case KEY_PAGEDOWN:
                    opt.selected = (opt.selected + 1) % menu.n;
                    rows_dirty = 1;
                    break;
                case KEY_ENTER:
                case KEY_KPENTER:
                    chosen = (opt.selected == opt.default_slot) ? -1 : opt.selected;
                    done = 1;
                    break;
                case KEY_1: case KEY_2: case KEY_3:
                case KEY_4: case KEY_5: case KEY_6:
                case KEY_7: case KEY_8: case KEY_9: {
                    int idx = (int)(ev.code - KEY_1);
                    if (idx < menu.n) {
                        opt.selected = idx;
                        rows_dirty = 1;
                    }
                    break;
                }
                case KEY_KP1: case KEY_KP2: case KEY_KP3:
                case KEY_KP4: case KEY_KP5: case KEY_KP6:
                case KEY_KP7: case KEY_KP8: case KEY_KP9: {
                    int idx = (int)(ev.code - KEY_KP1);
                    if (idx < menu.n) {
                        opt.selected = idx;
                        rows_dirty = 1;
                    }
                    break;
                }
                case KEY_T:
                case KEY_Q:
                case KEY_ESC:
                    chosen = -1;
                    done = 1;
                    break;
                default:
                    break;
                }
                if (done)
                    break;
            }
        }
        if (done)
            break;
        if (rows_dirty)
            compose_rows();
        if (footer_dirty)
            compose_footer();
    }

    ioctl(tty, KDSETMODE, KD_TEXT);
    close(tty);
    for (int i = 0; i < nfds; i++)
        close(fds[i]);
    screen_close(&screen);

    printf("%d\n", chosen);
    return 0;
}
