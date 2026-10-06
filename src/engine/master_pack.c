#include "master_pack.h"

void montage_master_pack (const guint16 *rgba, int width, int height, int layout, guint8 *out, const gsize *offsets, const gint *strides) {
    const double kr = 0.2126, kb = 0.0722, kg = 1 - kr - kb;
    int chroma444 = layout != 0;
    int alpha = layout == 2;
    for (int y = 0; y < height; y++) {
        guint16 *py = (guint16 *) (out + offsets[0] + (gsize) y * strides[0]);
        guint16 *pu = (guint16 *) (out + offsets[1] + (gsize) y * strides[1]);
        guint16 *pv = (guint16 *) (out + offsets[2] + (gsize) y * strides[2]);
        guint16 *pa = alpha ? (guint16 *) (out + offsets[3] + (gsize) y * strides[3]) : NULL;
        for (int x = 0; x < width; x++) {
            const guint16 *s = rgba + ((gsize) y * width + x) * 4;
            double r = s[0] / 65535.0, g = s[1] / 65535.0, b = s[2] / 65535.0;
            double yy = kr * r + kg * g + kb * b;
            double cb = (b - yy) / (2 * (1 - kb));
            double cr = (r - yy) / (2 * (1 - kr));
            py[x] = GUINT16_TO_LE ((guint16) CLAMP (64 + 876 * yy + 0.5, 0, 1023));
            if (chroma444) {
                pu[x] = GUINT16_TO_LE ((guint16) CLAMP (512 + 896 * cb + 0.5, 0, 1023));
                pv[x] = GUINT16_TO_LE ((guint16) CLAMP (512 + 896 * cr + 0.5, 0, 1023));
            } else if ((x & 1) == 0) {
                const guint16 *s2 = x + 1 < width ? s + 4 : s;
                double r2 = s2[0] / 65535.0, g2 = s2[1] / 65535.0, b2 = s2[2] / 65535.0;
                double y2 = kr * r2 + kg * g2 + kb * b2;
                double cb2 = (b2 - y2) / (2 * (1 - kb)), cr2 = (r2 - y2) / (2 * (1 - kr));
                pu[x / 2] = GUINT16_TO_LE ((guint16) CLAMP (512 + 896 * (cb + cb2) / 2 + 0.5, 0, 1023));
                pv[x / 2] = GUINT16_TO_LE ((guint16) CLAMP (512 + 896 * (cr + cr2) / 2 + 0.5, 0, 1023));
            }
            if (pa) pa[x] = GUINT16_TO_LE ((guint16) (s[3] >> 6));
        }
    }
}
