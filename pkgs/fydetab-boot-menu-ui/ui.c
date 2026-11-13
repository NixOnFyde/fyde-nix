/*
 * fydetab-boot-menu-ui -- tiny framebuffer generation picker for the initrd.
 *
 * The shell script owns everything that is Nix-specific (finding generations,
 * kexec).  This helper only draws a menu and reports which row was chosen.
 * It draws through a DRM dumb buffer (the vendor kernel's fbdev mmap is
 * broken) and reads raw evdev events, falling back to the console VT when no
 * key device shows up.
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
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
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
#define MAX_GENS 16
#define MAX_SPECS 8
#define MAX_ROWS (MAX_GENS * (MAX_SPECS + 1))

#define MARGIN 160
#define RIGHT (UI_W - MARGIN)
#define BRAND_Y 84
#define LIST_TOP 300
#define ROW_STEP 74
#define ROW_BASELINE 53
#define FOOTER_TOP (UI_H - 132)
#define VISIBLE_ROWS ((FOOTER_TOP - LIST_TOP - ROW_BASELINE) / ROW_STEP + 1)
#define X_MARKER MARGIN
#define X_FOLD (MARGIN + 40)
#define X_TREE (MARGIN + 116)
#define X_TEXT (MARGIN + 136)
#define X_CHILD (MARGIN + 168)
#define X_DATE (MARGIN + 560)

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
    char num[16];
    char date[32];
    int is_default;
    int nspec;
    char spec[MAX_SPECS][40];
} Gen;

typedef struct {
    int n;
    Gen gens[MAX_GENS];
} Menu;

/* A visible line: a generation itself (spec = -1) or one of its
 * specialisations.  Selection is kept as an item so folding does not move
 * the highlight to a different entry. */
typedef struct {
    int gen;
    int spec;
} Row;

typedef struct {
    int timeout;
    int rotation;
    const char *tty;
    const char *assets;
    const char *render;
    int expand_all;
    int paused;
    int left;
    int cursor;
    int top;
    int sel_gen;
    int sel_spec;
    int input_test;
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

static int expanded[MAX_GENS];
static Row rows[MAX_ROWS];
static int nrows;

static void fill_rect(int x, int y, int w, int h, uint32_t color)
{
    if (x < 0) { w += x; x = 0; }
    if (y < 0) { h += y; y = 0; }
    if (x + w > UI_W) w = UI_W - x;
    if (y + h > UI_H) h = UI_H - y;
    if (w <= 0 || h <= 0)
        return;
    for (int yy = y; yy < y + h; yy++)
        for (int xx = x; xx < x + w; xx++)
            canvas[yy * UI_W + xx] = color;
}

static int build_rows(void)
{
    int n = 0;
    for (int i = 0; i < menu.n; i++) {
        rows[n].gen = i;
        rows[n].spec = -1;
        n++;
        if (!expanded[i])
            continue;
        for (int j = 0; j < menu.gens[i].nspec; j++) {
            rows[n].gen = i;
            rows[n].spec = j;
            n++;
        }
    }
    return n;
}

static int cursor_for(int gen, int spec)
{
    for (int i = 0; i < nrows; i++)
        if (rows[i].gen == gen && rows[i].spec == spec)
            return i;
    return 0;
}

static void select_item(int gen, int spec)
{
    opt.sel_gen = gen;
    opt.sel_spec = spec;
    opt.cursor = cursor_for(gen, spec);
}

static void act_on_cursor(void)
{
    if (opt.cursor < 0)
        opt.cursor = 0;
    if (opt.cursor >= nrows)
        opt.cursor = nrows - 1;
    opt.sel_gen = rows[opt.cursor].gen;
    opt.sel_spec = rows[opt.cursor].spec;
}

static void draw_rows(void)
{
    if (opt.cursor < 0)
        opt.cursor = 0;
    if (opt.cursor >= nrows)
        opt.cursor = nrows - 1;
    if (opt.cursor < opt.top)
        opt.top = opt.cursor;
    if (opt.cursor >= opt.top + VISIBLE_ROWS)
        opt.top = opt.cursor - VISIBLE_ROWS + 1;
    if (opt.top > nrows - VISIBLE_ROWS)
        opt.top = nrows - VISIBLE_ROWS;
    if (opt.top < 0)
        opt.top = 0;

    for (int r = opt.top; r < nrows && r < opt.top + VISIBLE_ROWS; r++) {
        int y = LIST_TOP + (r - opt.top) * ROW_STEP;
        int baseline = y + ROW_BASELINE;
        int cy = y + ROW_BASELINE - 14;
        const Gen *g = &menu.gens[rows[r].gen];
        int sel = (r == opt.cursor);

        if (sel)
            draw_text(font_big, X_MARKER, baseline, ">", C_PINK, 255, 0);

        if (rows[r].spec < 0) {
            if (g->nspec)
                draw_text(font_small, X_FOLD, baseline,
                          expanded[rows[r].gen] ? "[-]" : "[+]",
                          sel ? C_BODY : C_DIM, 255, 0);
            draw_text(font_big, X_TEXT, baseline, g->num,
                      sel ? C_WHITE : C_BODY, 255, 0);
            draw_text(font_small, X_DATE, baseline, g->date,
                      sel ? C_BODY : C_MUTED, 255, 0);
            if (g->is_default) {
                const char *label = "(current)";
                int tw = text_width(font_small, label, 0);
                draw_text(font_small, RIGHT - tw, baseline, label,
                          sel ? C_PINK : 0x00B8456Du, 255, 0);
            }
        } else {
            int first = (r == 0) || rows[r - 1].spec < 0;
            int last = (r + 1 >= nrows) || rows[r + 1].spec < 0;
            int vy0 = first ? cy - ROW_STEP / 2 : y;
            int vy1 = last ? cy : y + ROW_STEP;
            fill_rect(X_TREE, vy0, 2, vy1 - vy0, C_DIM);
            fill_rect(X_TREE, cy - 1, X_CHILD - X_TREE - 24, 2, C_DIM);
            draw_text(font_mid, X_CHILD, baseline, g->spec[rows[r].spec],
                      sel ? C_WHITE : C_BODY, 255, 0);
        }
    }
}

static void draw_footer(void)
{
    int baseline = UI_H - 54;

    struct { const char *text; uint32_t color; } parts[] = {
        { "Up / Down", C_MUTED },
        { "  select      ", C_DIM },
        { "Left / Right", C_MUTED },
        { "  fold      ", C_DIM },
        { "Enter", C_MUTED },
        { "  boot      ", C_DIM },
        { "1-9", C_MUTED },
        { "  jump      ", C_DIM },
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
        const Gen *g = &menu.gens[opt.sel_gen];
        if (opt.sel_spec >= 0)
            snprintf(buffer, sizeof buffer, "Enter boots %s/%s", g->num,
                     g->spec[opt.sel_spec]);
        else
            snprintf(buffer, sizeof buffer, "Enter boots %s", g->num);
        status = buffer;
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
    int y0 = LIST_TOP - 16;

    for (int y = y0; y < FOOTER_TOP; y++)
        memcpy(&canvas[y * UI_W], &bg_canvas[y * UI_W],
               (size_t)UI_W * sizeof(uint32_t));
    draw_rows();
    push_rect(0, y0, UI_W, FOOTER_TOP - y0);
}

static void compose_footer(void)
{
    for (int y = FOOTER_TOP; y < UI_H; y++)
        memcpy(&canvas[y * UI_W], &bg_canvas[y * UI_W],
               (size_t)UI_W * sizeof(uint32_t));
    draw_footer();
    push_rect(0, FOOTER_TOP, UI_W, UI_H - FOOTER_TOP);
}

/* ----------------------------------------------------------------- input */

#define MAX_INPUTS 16

struct idev {
    int fd;
    int event;
    int pointer;
    int minx, maxx, miny, maxy;
    int x, y;
    int down;
    int startx, starty;
};

static struct idev idevs[MAX_INPUTS];
static int nidev;
static int taken[32];

/* (Re)scan the event nodes.  The USB keyboard and the touchscreen can appear
 * after the menu starts, so this runs again on every one-second tick. */
static void input_scan(void)
{
    for (int i = 0; i < 32; i++) {
        if (taken[i] || nidev >= MAX_INPUTS)
            continue;

        char path[64];
        snprintf(path, sizeof path, "/dev/input/event%d", i);
        int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0)
            continue;

        uint8_t evbit[(EV_MAX / 8) + 1] = { 0 };
        uint8_t keybit[(KEY_MAX / 8) + 1] = { 0 };
        if (ioctl(fd, EVIOCGBIT(0, sizeof evbit), evbit) < 0 ||
            ioctl(fd, EVIOCGBIT(EV_KEY, sizeof keybit), keybit) < 0) {
            close(fd);
            continue;
        }

#define HAS_EV(t) (evbit[(t) / 8] & (1u << ((t) % 8)))
#define HAS_KEY(k) (keybit[(k) / 8] & (1u << ((k) % 8)))
        int keys = HAS_KEY(KEY_UP) || HAS_KEY(KEY_DOWN) ||
                   HAS_KEY(KEY_ENTER) || HAS_KEY(KEY_VOLUMEUP) ||
                   HAS_KEY(KEY_VOLUMEDOWN);
        int pointer = 0;
        struct input_absinfo ax = { 0 }, ay = { 0 };
        if (HAS_EV(EV_ABS) && HAS_KEY(BTN_TOUCH) &&
            ioctl(fd, EVIOCGABS(ABS_X), &ax) == 0 &&
            ioctl(fd, EVIOCGABS(ABS_Y), &ay) == 0 &&
            ax.maximum > ax.minimum && ay.maximum > ay.minimum)
            pointer = 1;
#undef HAS_EV
#undef HAS_KEY

        if (!keys && !pointer) {
            close(fd);
            continue;
        }

        char name[80] = "";
        ioctl(fd, EVIOCGNAME(sizeof name - 1), name);

        struct idev *d = &idevs[nidev++];
        memset(d, 0, sizeof *d);
        d->fd = fd;
        d->event = i;
        d->pointer = pointer;
        d->minx = ax.minimum;
        d->maxx = ax.maximum;
        d->miny = ay.minimum;
        d->maxy = ay.maximum;
        d->x = (ax.minimum + ax.maximum) / 2;
        d->y = (ay.minimum + ay.maximum) / 2;
        taken[i] = 1;
        fprintf(stderr, "fydetab-menu: input event%d: %s (%s)\n", i, name,
                pointer ? "touch" : "keys");
    }
}

/* The VT and evdev deliver the same physical keypress, so only one of them
 * may be used for keys.  evdev has the exact keycodes and the kernel's
 * held-key repeats, so it wins whenever a key device exists; the console VT is
 * only a fallback for a boot where no key device showed up. */
static int have_key_device(void)
{
    for (int i = 0; i < nidev; i++)
        if (!idevs[i].pointer)
            return 1;
    return 0;
}

static void input_drop(int idx)
{
    if (idx < 0 || idx >= nidev)
        return;
    fprintf(stderr, "fydetab-menu: input event%d gone, reopening\n",
            idevs[idx].event);
    close(idevs[idx].fd);
    taken[idevs[idx].event] = 0;
    idevs[idx] = idevs[--nidev];
}

/* Map a panel coordinate to a visible row, applying the same rotation the
 * scanout uses.  Returns -1 when the tap is outside the list. */
static int panel_to_row(int px, int py, int *cx_out, int *cy_out)
{
    int sx = px, sy = py;
    int cx, cy;
    if (screen.rotation == 90) {
        cx = 2559 - sy;
        cy = sx;
    } else {
        cx = sy;
        cy = 1599 - sx;
    }
    if (cx_out)
        *cx_out = cx;
    if (cy_out)
        *cy_out = cy;
    if (cx < X_MARKER || cx > RIGHT || cy < LIST_TOP - 8)
        return -1;
    int row = opt.top + (cy - (LIST_TOP - 8)) / ROW_STEP;
    if (row < 0 || row >= nrows || row >= opt.top + VISIBLE_ROWS)
        return -1;
    return row;
}

static void choose_entry(char *out, size_t n, int *g_boot_default)
{
    const Gen *g = &menu.gens[opt.sel_gen];
    if (opt.sel_spec < 0) {
        if (!g->is_default) {
            snprintf(out, n, "%s", g->num);
            *g_boot_default = 0;
        }
    } else {
        snprintf(out, n, "%s/%s", g->num, g->spec[opt.sel_spec]);
        *g_boot_default = 0;
    }
}

static char g_chosen[64];
static int g_boot_default = 1;
static int g_list_dirty, g_footer_dirty, g_done;

/* The initrd's evdev nodes have proved unreliable at menu time, but the
 * console always delivers keys, so the VT is polled alongside evdev. */
static int ttyfd = -1;
static int vt_esc; /* 0: none, 1: ESC, 2: inside a CSI/SS3 sequence */
static int vt_num;

static int vt_feed(unsigned char c)
{
    if (vt_esc == 2) {
        if (c >= '0' && c <= '9') {
            vt_num = vt_num * 10 + (c - '0');
            return 0;
        }
        if (c == '~') {
            int n = vt_num;
            vt_esc = vt_num = 0;
            switch (n) {
            case 1:
            case 7:
                return KEY_HOME;
            case 4:
            case 8:
                return KEY_END;
            case 5:
                return KEY_PAGEUP;
            case 6:
                return KEY_PAGEDOWN;
            case 3:
                return KEY_DELETE;
            default:
                return 0;
            }
        }
        vt_esc = vt_num = 0;
        switch (c) {
        case 'A':
            return KEY_UP;
        case 'B':
            return KEY_DOWN;
        case 'C':
            return KEY_RIGHT;
        case 'D':
            return KEY_LEFT;
        case 'H':
            return KEY_HOME;
        case 'F':
            return KEY_END;
        case 'Z':
            return KEY_TAB;
        default:
            return 0;
        }
    }
    if (c == 27) {
        if (vt_esc == 1) {
            vt_esc = 0;
            return KEY_ESC;
        }
        vt_esc = 1;
        return 0;
    }
    if (vt_esc == 1) {
        vt_esc = 0;
        if (c == '[' || c == 'O') {
            vt_esc = 2;
            vt_num = 0;
            return 0;
        }
        return KEY_ESC;
    }
    switch (c) {
    case '\r':
    case '\n':
        return KEY_ENTER;
    case '\t':
        return KEY_TAB;
    case 0x7f:
    case 0x08:
        return KEY_BACKSPACE;
    case ' ':
        return KEY_SPACE;
    case 'j':
        return KEY_J;
    case 'k':
        return KEY_K;
    case 'q':
        return KEY_Q;
    case 't':
        return KEY_T;
    default:
        if (c >= '1' && c <= '9')
            return KEY_1 + (c - '1');
        return 0;
    }
}

/* Apply one key press (evdev code or a synthetic code from the VT). */
static void handle_key(unsigned code)
{
    if (!opt.paused) {
        opt.paused = 1;
        g_footer_dirty = 1;
    }

    switch (code) {
        case KEY_UP:
        case KEY_K:
        case KEY_VOLUMEUP:
            if (opt.cursor > 0)
                opt.cursor--;
            act_on_cursor();
            g_list_dirty = 1;
            break;
        case KEY_DOWN:
        case KEY_J:
        case KEY_VOLUMEDOWN:
            if (opt.cursor < nrows - 1)
                opt.cursor++;
            act_on_cursor();
            g_list_dirty = 1;
            break;
        case KEY_PAGEUP: {
            opt.cursor -= VISIBLE_ROWS;
            if (opt.cursor < 0)
                opt.cursor = 0;
            act_on_cursor();
            g_list_dirty = 1;
            break;
        }
        case KEY_PAGEDOWN: {
            opt.cursor += VISIBLE_ROWS;
            if (opt.cursor > nrows - 1)
                opt.cursor = nrows - 1;
            act_on_cursor();
            g_list_dirty = 1;
            break;
        }
        case KEY_HOME:
            opt.cursor = 0;
            act_on_cursor();
            g_list_dirty = 1;
            break;
        case KEY_END:
            opt.cursor = nrows - 1;
            act_on_cursor();
            g_list_dirty = 1;
            break;
        case KEY_LEFT: {
            int gi = rows[opt.cursor].gen;
            if (opt.sel_spec >= 0 || expanded[gi]) {
                expanded[gi] = 0;
                nrows = build_rows();
                select_item(gi, -1);
                act_on_cursor();
                g_list_dirty = 1;
            }
            break;
        }
        case KEY_RIGHT: {
            int gi = rows[opt.cursor].gen;
            if (opt.sel_spec < 0 && menu.gens[gi].nspec) {
                if (!expanded[gi]) {
                    expanded[gi] = 1;
                    nrows = build_rows();
                    select_item(gi, -1);
                } else {
                    select_item(gi, 0);
                }
                act_on_cursor();
                g_list_dirty = 1;
            }
            break;
        }
        case KEY_ENTER:
        case KEY_KPENTER: {
            choose_entry(g_chosen, sizeof g_chosen, &g_boot_default);
            fprintf(stderr, "fydetab-menu: boot %s (%s)\n",
                    g_boot_default ? "default" : g_chosen,
                    menu.gens[opt.sel_gen].num);
            g_done = 1;
            break;
        }
        case KEY_1: case KEY_2: case KEY_3:
        case KEY_4: case KEY_5: case KEY_6:
        case KEY_7: case KEY_8: case KEY_9: {
            int idx = (int)(code - KEY_1);
            if (idx < menu.n) {
                select_item(idx, -1);
                g_list_dirty = 1;
            }
            break;
        }
        case KEY_KP1: case KEY_KP2: case KEY_KP3:
        case KEY_KP4: case KEY_KP5: case KEY_KP6:
        case KEY_KP7: case KEY_KP8: case KEY_KP9: {
            int idx = (int)(code - KEY_KP1);
            if (idx < menu.n) {
                select_item(idx, -1);
                g_list_dirty = 1;
            }
            break;
        }
        case KEY_T:
        case KEY_Q:
        case KEY_ESC:
            g_boot_default = 1;
            g_done = 1;
            break;
        default:
            break;
        }
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
    int cur = -1;

    while (menu.n < MAX_GENS && fgets(line, sizeof line, stdin)) {
        size_t len = strlen(line);
        while (len && (line[len - 1] == '\n' || line[len - 1] == '\r'))
            line[--len] = '\0';

        /* S|name is a specialisation of the generation above it. */
        if (line[0] == 'S' && line[1] == '|') {
            if (cur >= 0 && menu.gens[cur].nspec < MAX_SPECS) {
                Gen *g = &menu.gens[cur];
                snprintf(g->spec[g->nspec], sizeof g->spec[0], "%.39s", line + 2);
                g->nspec++;
            }
            continue;
        }

        char *field = (line[0] == 'G' && line[1] == '|') ? line + 2 : line;
        char *bar1 = strchr(field, '|');
        if (!bar1)
            continue;
        char *bar2 = strchr(bar1 + 1, '|');
        if (!bar2)
            continue;
        *bar1 = '\0';
        *bar2 = '\0';

        cur = menu.n++;
        Gen *g = &menu.gens[cur];
        snprintf(g->num, sizeof g->num, "%.15s", field);
        snprintf(g->date, sizeof g->date, "%.31s", bar1 + 1);
        g->is_default = (bar2[1] == '1');
        g->nspec = 0;
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

/* --input-test: exercise the same input path without touching DRM or the
 * console, so the initrd binary can be tested on a running system. */
static void input_test(int seconds)
{
    for (int attempt = 0; attempt < 20 && nidev == 0; attempt++) {
        input_scan();
        if (!nidev)
            usleep(100000);
    }
    fprintf(stderr, "fydetab-menu: input test: %d devices, %d seconds\n",
            nidev, seconds);

    for (int tick = 0; tick < seconds * 5; tick++) {
        struct pollfd pfds[MAX_INPUTS];
        for (int i = 0; i < nidev; i++) {
            pfds[i].fd = idevs[i].fd;
            pfds[i].events = POLLIN;
            pfds[i].revents = 0;
        }

        int ready = poll(pfds, (nfds_t)nidev, 200);
        if (ready <= 0) {
            input_scan();
            continue;
        }

        for (int i = 0; i < nidev; i++) {
            if (!(pfds[i].revents & POLLIN))
                continue;
            struct input_event ev;
            while (read(idevs[i].fd, &ev, sizeof ev) == (ssize_t)sizeof ev)
                fprintf(stderr,
                        "fydetab-menu: ev%d type %u code %u value %d\n",
                        idevs[i].event, ev.type, ev.code, ev.value);
        }
    }
    fprintf(stderr, "fydetab-menu: input test done\n");
}

int main(int argc, char **argv)
{
    opt.timeout = 5;
    opt.rotation = 270;
    opt.tty = "/dev/tty2";
    opt.cursor = 0;
    opt.top = 0;
    opt.sel_gen = 0;
    opt.sel_spec = -1;
    opt.paused = 0;
    opt.left = -1;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--timeout"))
            opt.timeout = parse_option("--timeout", argc, argv, &i);
        else if (!strcmp(argv[i], "--rotation"))
            opt.rotation = parse_option("--rotation", argc, argv, &i);
        else if (!strcmp(argv[i], "--selected"))
            opt.cursor = parse_option("--selected", argc, argv, &i);
        else if (!strcmp(argv[i], "--expand-all"))
            opt.expand_all = 1;
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
        else if (!strcmp(argv[i], "--input-test"))
            opt.input_test = parse_option("--input-test", argc, argv, &i);
        else {
            fprintf(stderr, "fydetab-menu: unknown option %s\n", argv[i]);
            return 2;
        }
    }

    if (opt.input_test > 0) {
        input_test(opt.input_test);
        return 0;
    }

    if (!opt.assets)
        opt.assets = default_assets_dir();
    if (!opt.assets) {
        fprintf(stderr, "fydetab-menu: cannot locate assets\n");
        return 1;
    }

    static Font small, mid, big;
    if (font_load(&small, asset_path(opt.assets, "font-mono-27.bin")) < 0 ||
        font_load(&mid, asset_path(opt.assets, "font-mono-33.bin")) < 0 ||
        font_load(&big, asset_path(opt.assets, "font-mono-44.bin")) < 0) {
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
    for (int i = 0; i < menu.n; i++)
        expanded[i] = opt.expand_all ? 1 : menu.gens[i].is_default;
    nrows = build_rows();
    if (opt.cursor < 0 || opt.cursor >= nrows)
        opt.cursor = 0;
    act_on_cursor();
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

    /* Reading a VT from a background process group raises SIGTTIN, and the
     * console must be in cbreak mode for single-key reads. */
    signal(SIGTTIN, SIG_IGN);
    signal(SIGTTOU, SIG_IGN);

    int tty = open(opt.tty, O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC);
    if (tty < 0) {
        perror("fydetab-menu: open tty");
        tty = open("/dev/tty1", O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC);
    }
    if (tty < 0) {
        perror("fydetab-menu: open /dev/tty1");
        return 1;
    }

    struct termios tty_saved;
    int tty_raw = 0;
    if (tcgetattr(tty, &tty_saved) == 0) {
        struct termios raw = tty_saved;
        raw.c_lflag &= ~(tcflag_t)(ICANON | ECHO | ISIG);
        raw.c_iflag &= ~(tcflag_t)(IXON | ICRNL);
        raw.c_cc[VMIN] = 0;
        raw.c_cc[VTIME] = 0;
        tty_raw = tcsetattr(tty, TCSANOW, &raw) == 0;
    }
    ttyfd = tty;

    ioctl(tty, KDSETMODE, KD_GRAPHICS);

    if (screen_open(&screen, opt.rotation) < 0) {
        ioctl(tty, KDSETMODE, KD_TEXT);
        return 1;
    }

    for (int attempt = 0; attempt < 20 && nidev == 0; attempt++) {
        input_scan();
        if (!nidev)
            usleep(100000);
    }
    if (!nidev && ttyfd < 0) {
        fprintf(stderr, "fydetab-menu: no usable input device, booting default\n");
        ioctl(tty, KDSETMODE, KD_TEXT);
        return -1;
    }

    fprintf(stderr, "fydetab-menu: %d generations, %d rows, display %dx%d stride %d rot %d, %d input devices\n",
            menu.n, nrows, screen.w, screen.h, screen.stride, screen.rotation, nidev);
    fprintf(stderr, "fydetab-menu: keys from %s\n",
            have_key_device() ? "evdev" : (ttyfd >= 0 ? "the console VT" : "nowhere"));

    draw_rows();
    draw_footer();
    push_rect(0, 0, UI_W, UI_H);

    g_chosen[0] = '\0';
    g_boot_default = 1;

    for (;;) {
        input_scan();

        /* Index 0 is the console VT; it is polled only when there is no evdev
         * key device, otherwise every keypress would be handled twice. */
        struct pollfd pfds[MAX_INPUTS + 1];
        int npoll = 0;
        int tty_index = -1;
        if (ttyfd >= 0 && !have_key_device()) {
            tty_index = npoll;
            pfds[npoll].fd = ttyfd;
            pfds[npoll].events = POLLIN;
            pfds[npoll].revents = 0;
            npoll++;
        }
        for (int i = 0; i < nidev; i++) {
            pfds[npoll].fd = idevs[i].fd;
            pfds[npoll].events = POLLIN;
            pfds[npoll].revents = 0;
            npoll++;
        }

        int ready = poll(pfds, (nfds_t)npoll, 1000);
        if (ready < 0) {
            if (errno == EINTR)
                continue;
            break;
        }

        if (ready == 0) {
            if (!opt.paused) {
                if (opt.left > 0)
                    opt.left--;
                fprintf(stderr, "fydetab-menu: tick %d\n", opt.left);
                if (opt.left <= 0) {
                    fprintf(stderr, "fydetab-menu: countdown finished\n");
                    break;
                }
                compose_footer();
            }
            continue;
        }

        g_list_dirty = g_footer_dirty = 0;
        g_done = 0;
        int drop = -1;
        int base = tty_index >= 0 ? 1 : 0;
        for (int i = 0; i < npoll && !g_done; i++) {
            if (i == tty_index) {
                if (pfds[i].revents & POLLIN) {
                    unsigned char buf[64];
                    ssize_t n = read(ttyfd, buf, sizeof buf);
                    while (n > 0 && !g_done) {
                        for (ssize_t k = 0; k < n && !g_done; k++) {
                            int code = vt_feed(buf[k]);
                            if (!code)
                                continue;
                            fprintf(stderr, "fydetab-menu: vt key %d\n", code);
                            handle_key((unsigned)code);
                        }
                        if (g_done)
                            break;
                        n = read(ttyfd, buf, sizeof buf);
                    }
                    if (n < 0 && errno != EAGAIN && errno != EINTR) {
                        fprintf(stderr, "fydetab-menu: vt read: %s\n",
                                strerror(errno));
                        ttyfd = -1;
                    }
                }
                if (pfds[i].revents & (POLLERR | POLLHUP | POLLNVAL)) {
                    fprintf(stderr, "fydetab-menu: vt gone\n");
                    ttyfd = -1;
                }
                continue;
            }
            int e = i - base;
            if (pfds[i].revents & (POLLERR | POLLHUP | POLLNVAL)) {
                drop = e;
                continue;
            }
            if (!(pfds[i].revents & POLLIN))
                continue;

            struct idev *d = &idevs[e];
            struct input_event ev;
            while (read(d->fd, &ev, sizeof ev) == (ssize_t)sizeof ev) {
                if (ev.type == EV_ABS) {
                    if (ev.code == ABS_X || ev.code == ABS_MT_POSITION_X)
                        d->x = ev.value;
                    else if (ev.code == ABS_Y || ev.code == ABS_MT_POSITION_Y)
                        d->y = ev.value;
                    continue;
                }
                if (ev.type != EV_KEY || ev.value < 0)
                    continue;

                if (d->pointer) {
                    if (ev.code != BTN_TOUCH)
                        continue;
                    if (ev.value >= 1) {
                        d->down = 1;
                        d->startx = d->x;
                        d->starty = d->y;
                        if (!opt.paused) {
                            opt.paused = 1;
                            g_footer_dirty = 1;
                        }
                    } else if (d->down) {
                        int dx, dy, px, py, cx, cy, row;
                        d->down = 0;
                        dx = d->x - d->startx;
                        dy = d->y - d->starty;
                        if (dx * dx + dy * dy > 60 * 60)
                            continue;
                        px = (d->x - d->minx) * 1600 /
                             (d->maxx - d->minx + 1);
                        py = (d->y - d->miny) * 2560 /
                             (d->maxy - d->miny + 1);
                        cx = px;
                        cy = py;
                        row = panel_to_row(px, py, &cx, &cy);
                        fprintf(stderr,
                                "fydetab-menu: tap %d,%d canvas %d,%d row %d\n",
                                px, py, cx, cy, row);
                        if (row < 0)
                            continue;
                        if (row == opt.cursor) {
                            choose_entry(g_chosen, sizeof g_chosen, &g_boot_default);
                            g_done = 1;
                        } else {
                            opt.cursor = row;
                            act_on_cursor();
                            g_list_dirty = 1;
                        }
                    }
                    if (g_done)
                        break;
                    continue;
                }

                /* value 2 is the kernel's held-key repeat. */
                if (ev.value < 1)
                    continue;

                fprintf(stderr, "fydetab-menu: key %u value %d\n",
                        ev.code, ev.value);

                handle_key(ev.code);
                if (g_done)
                    break;
            }
        }
        if (g_done)
            break;
        if (drop >= 0)
            input_drop(drop);
        if (g_list_dirty)
            compose_rows();
        if (g_footer_dirty)
            compose_footer();
    }

    ioctl(tty, KDSETMODE, KD_TEXT);
    if (tty_raw)
        tcsetattr(tty, TCSANOW, &tty_saved);
    close(tty);
    for (int i = 0; i < nidev; i++)
        close(idevs[i].fd);
    screen_close(&screen);

    printf("%s\n", g_boot_default ? "-1" : g_chosen);
    return 0;
}
