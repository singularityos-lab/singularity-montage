using Singularity.Imaging;

namespace Singularity.Apps.Montage {
    public struct Placement {
        public double x;
        public double y;
        public double scale_x;
        public double scale_y;
        public double rotation;
        public double anchor_x;
        public double anchor_y;
        public double opacity;
        public double crop_l;
        public double crop_r;
        public double crop_t;
        public double crop_b;

        public bool identity () {
            return x == 0 && y == 0 && scale_x == 1 && scale_y == 1 && rotation == 0 && anchor_x == 0 && anchor_y == 0 &&
                crop_l == 0 && crop_r == 0 && crop_t == 0 && crop_b == 0;
        }
    }

    namespace Compose {
        public Placement placement (Clip c, int64 key, double scale) {
            Placement p = Placement ();
            var ps = c.params;
            double s = ps.get_value ("scale", key, 100) / 100;
            p.x = ps.get_value ("x", key, 0) * scale;
            p.y = ps.get_value ("y", key, 0) * scale;
            p.scale_x = s * ps.get_value ("scale-x", key, 100) / 100;
            p.scale_y = s * ps.get_value ("scale-y", key, 100) / 100;
            p.rotation = ps.get_value ("rotation", key, 0) * Math.PI / 180;
            p.anchor_x = ps.get_value ("anchor-x", key, 0) * scale;
            p.anchor_y = ps.get_value ("anchor-y", key, 0) * scale;
            p.opacity = (ps.get_value ("opacity", key, 100) / 100).clamp (0, 1);
            p.crop_l = ps.get_value ("crop-left", key, 0) / 100;
            p.crop_r = ps.get_value ("crop-right", key, 0) / 100;
            p.crop_t = ps.get_value ("crop-top", key, 0) / 100;
            p.crop_b = ps.get_value ("crop-bottom", key, 0) / 100;
            return p;
        }

        public void place (FloatImage canvas, FloatImage layer, Placement p, BlendMode mode) {
            int cw = canvas.width, ch = canvas.height;
            int lw = layer.width, lh = layer.height;
            double cx = cw / 2.0 + p.x, cy = ch / 2.0 + p.y;
            double sx = p.scale_x, sy = p.scale_y;
            if (sx.abs () < 1e-6 || sy.abs () < 1e-6 || p.opacity <= 0) return;
            double cos_r = Math.cos (p.rotation), sin_r = Math.sin (p.rotation);
            double x0 = lw * p.crop_l, x1 = lw * (1 - p.crop_r), y0 = lh * p.crop_t, y1 = lh * (1 - p.crop_b);
            if (x1 <= x0 || y1 <= y0) return;
            bool axis = p.rotation == 0 && sx == 1 && sy == 1 && p.anchor_x == 0 && p.anchor_y == 0;
            double min_x = double.MAX, min_y = double.MAX, max_x = -double.MAX, max_y = -double.MAX;
            double[] corners = { x0, y0, x1, y0, x0, y1, x1, y1 };
            for (int k = 0; k < 4; k++) {
                double qx = corners[k * 2] - lw / 2.0 - p.anchor_x, qy = corners[k * 2 + 1] - lh / 2.0 - p.anchor_y;
                double px = cx + cos_r * qx * sx - sin_r * qy * sy;
                double py = cy + sin_r * qx * sx + cos_r * qy * sy;
                min_x = double.min (min_x, px); max_x = double.max (max_x, px);
                min_y = double.min (min_y, py); max_y = double.max (max_y, py);
            }
            int bx0 = int.max (0, (int) Math.floor (min_x)), bx1 = int.min (cw, (int) Math.ceil (max_x) + 1);
            int by0 = int.max (0, (int) Math.floor (min_y)), by1 = int.min (ch, (int) Math.ceil (max_y) + 1);
            if (bx0 >= bx1 || by0 >= by1) return;
            float opacity = (float) p.opacity;
            bool normal = mode == BlendMode.NORMAL;
            int ox = (int) Math.round (cx - lw / 2.0), oy = (int) Math.round (cy - lh / 2.0);
            bool integral = axis && (cx - lw / 2.0 - ox).abs () < 1e-6 && (cy - lh / 2.0 - oy).abs () < 1e-6;
            Parallel.range (by1 - by0, (r0, r1) => {
                for (int py = by0 + r0; py < by0 + r1; py++) {
                    for (int px = bx0; px < bx1; px++) {
                        float r, g, b, a;
                        double lx, ly;
                        if (integral) {
                            int ix = px - ox, iy = py - oy;
                            if (ix < x0 || iy < y0 || ix >= x1 || iy >= y1 || ix >= lw || iy >= lh || ix < 0 || iy < 0) continue;
                            size_t li = ((size_t) iy * lw + ix) * 4;
                            r = layer.data[li]; g = layer.data[li + 1]; b = layer.data[li + 2]; a = layer.data[li + 3];
                        } else {
                            double dx = px + 0.5 - cx, dy = py + 0.5 - cy;
                            double qx = (cos_r * dx + sin_r * dy) / sx;
                            double qy = (-sin_r * dx + cos_r * dy) / sy;
                            lx = qx + p.anchor_x + lw / 2.0;
                            ly = qy + p.anchor_y + lh / 2.0;
                            if (lx < x0 - 0.5 || ly < y0 - 0.5 || lx > x1 + 0.5 || ly > y1 + 0.5) continue;
                            layer.sample (lx, ly, out r, out g, out b, out a);
                            double edge = double.min (double.min (lx - x0 + 0.5, x1 + 0.5 - lx), double.min (ly - y0 + 0.5, y1 + 0.5 - ly));
                            if (edge < 1) a *= (float) edge.clamp (0, 1);
                        }
                        a *= opacity;
                        if (a <= 0) continue;
                        size_t ci = ((size_t) py * cw + px) * 4;
                        float ba = canvas.data[ci + 3];
                        float br = canvas.data[ci], bg = canvas.data[ci + 1], bb = canvas.data[ci + 2];
                        if (!normal) {
                            float mr, mg, mb;
                            Blend.mix (mode, Tone.encode (br.clamp (0, 1)), Tone.encode (bg.clamp (0, 1)), Tone.encode (bb.clamp (0, 1)),
                                Tone.encode (r.clamp (0, 1)), Tone.encode (g.clamp (0, 1)), Tone.encode (b.clamp (0, 1)), out mr, out mg, out mb);
                            mr = Tone.decode (mr); mg = Tone.decode (mg); mb = Tone.decode (mb);
                            r = r + (mr - r) * ba;
                            g = g + (mg - g) * ba;
                            b = b + (mb - b) * ba;
                        }
                        float oa = a + ba * (1 - a);
                        if (oa <= 1e-6f) continue;
                        canvas.data[ci] = (r * a + br * ba * (1 - a)) / oa;
                        canvas.data[ci + 1] = (g * a + bg * ba * (1 - a)) / oa;
                        canvas.data[ci + 2] = (b * a + bb * ba * (1 - a)) / oa;
                        canvas.data[ci + 3] = oa;
                    }
                }
            }, 4);
        }

        public void over (FloatImage canvas, FloatImage layer, float opacity) {
            Placement p = Placement ();
            p.scale_x = p.scale_y = 1;
            p.opacity = opacity;
            place (canvas, layer, p, BlendMode.NORMAL);
        }

        public void mix_with (FloatImage target, FloatImage other, float amount) {
            int n = (int) target.pixel_count ();
            Parallel.range (n, (a, b) => {
                for (int p = a; p < b; p++) {
                    size_t i = (size_t) p * 4;
                    for (int c = 0; c < 4; c++) target.data[i + c] += (other.data[i + c] - target.data[i + c]) * amount;
                }
            }, 4096);
        }

        float smooth (float e0, float e1, float x) {
            if (e1 <= e0) return x < e0 ? 0 : 1;
            float t = ((x - e0) / (e1 - e0)).clamp (0, 1);
            return t * t * (3 - 2 * t);
        }

        void premul_sample (FloatImage img, double x, double y, out float r, out float g, out float b, out float a) {
            if (x < 0 || y < 0 || x >= img.width || y >= img.height) {
                r = g = b = a = 0;
                return;
            }
            size_t i = img.offset ((int) x, (int) y);
            a = img.data[i + 3];
            r = img.data[i] * a; g = img.data[i + 1] * a; b = img.data[i + 2] * a;
        }

        public FloatImage transition (FloatImage? from, FloatImage? to, Transition t, float progress) {
            int w = from != null ? from.width : to.width, h = from != null ? from.height : to.height;
            var a = from ?? new FloatImage (w, h);
            var b = to ?? new FloatImage (w, h);
            var result = new FloatImage (w, h);
            float p = progress.clamp (0, 1);
            float soft = (float) t.softness.clamp (0.0, 0.5);
            float cr, cg, cb, ca;
            VideoFx.parse_color (t.color, out cr, out cg, out cb, out ca);
            cr = Tone.decode (cr); cg = Tone.decode (cg); cb = Tone.decode (cb);
            string dir = t.direction;
            string kind = t.kind;
            Parallel.range (h, (y0, y1) => {
                for (int y = y0; y < y1; y++) {
                    for (int x = 0; x < w; x++) {
                        float ar, ag, ab, aa, brr, bgg, bbb, ba;
                        float wa = 1 - p, wb = p;
                        double ax = x, ay = y, bx = x, by = y;
                        float u = (x + 0.5f) / w, v = (y + 0.5f) / h;
                        switch (kind) {
                            case "wipe": {
                                float pos = dir == "right" ? 1 - u : (dir == "up" ? v : (dir == "down" ? 1 - v : u));
                                wb = 1 - smooth (p * (1 + soft) - soft, p * (1 + soft), pos);
                                wa = 1 - wb;
                                break;
                            }
                            case "push": {
                                wa = wb = 1;
                                if (dir == "left") { ax = x + p * w; bx = x - (1 - p) * w; }
                                else if (dir == "right") { ax = x - p * w; bx = x + (1 - p) * w; }
                                else if (dir == "up") { ay = y + p * h; by = y - (1 - p) * h; }
                                else { ay = y - p * h; by = y + (1 - p) * h; }
                                break;
                            }
                            case "slide": {
                                wa = 1; wb = 1;
                                if (dir == "left") bx = x - (1 - p) * w;
                                else if (dir == "right") bx = x + (1 - p) * w;
                                else if (dir == "up") by = y - (1 - p) * h;
                                else by = y + (1 - p) * h;
                                break;
                            }
                            case "iris": {
                                float dx = u - 0.5f, dy = (v - 0.5f) * h / w;
                                float dist = Math.sqrtf (dx * dx + dy * dy) / 0.7072f;
                                wb = 1 - smooth (p * (1 + soft) - soft, p * (1 + soft), dist);
                                wa = 1 - wb;
                                break;
                            }
                            case "clock": {
                                float ang = (Math.atan2f (u - 0.5f, -(v - 0.5f)) / (2 * (float) Math.PI) + 1) % 1.0f;
                                wb = 1 - smooth (p * (1 + soft) - soft, p * (1 + soft), ang);
                                wa = 1 - wb;
                                break;
                            }
                            case "barn": {
                                float dist = (u - 0.5f).abs () * 2;
                                wb = 1 - smooth (p * (1 + soft) - soft, p * (1 + soft), dist);
                                wa = 1 - wb;
                                break;
                            }
                            case "zoom": {
                                double za = 1 + p * 0.5, zb = 1.5 - p * 0.5;
                                ax = (x - w / 2.0) / za + w / 2.0; ay = (y - h / 2.0) / za + h / 2.0;
                                bx = (x - w / 2.0) / zb + w / 2.0; by = (y - h / 2.0) / zb + h / 2.0;
                                break;
                            }
                            default:
                                break;
                        }
                        premul_sample (a, ax, ay, out ar, out ag, out ab, out aa);
                        premul_sample (b, bx, by, out brr, out bgg, out bbb, out ba);
                        float rr, rg, rb, ra;
                        if (kind == "dip") {
                            if (p < 0.5f) {
                                float k = p * 2;
                                rr = ar * (1 - k) + cr * k; rg = ag * (1 - k) + cg * k; rb = ab * (1 - k) + cb * k; ra = aa * (1 - k) + k;
                            } else {
                                float k = (p - 0.5f) * 2;
                                rr = cr * (1 - k) + brr * k; rg = cg * (1 - k) + bgg * k; rb = cb * (1 - k) + bbb * k; ra = (1 - k) + ba * k;
                            }
                        } else if (kind == "additive") {
                            rr = ar * float.min (1, 2 * (1 - p)) + brr * float.min (1, 2 * p);
                            rg = ag * float.min (1, 2 * (1 - p)) + bgg * float.min (1, 2 * p);
                            rb = ab * float.min (1, 2 * (1 - p)) + bbb * float.min (1, 2 * p);
                            ra = float.min (1, aa * float.min (1, 2 * (1 - p)) + ba * float.min (1, 2 * p));
                        } else if (kind == "push" || kind == "slide") {
                            rr = brr + ar * (1 - ba); rg = bgg + ag * (1 - ba); rb = bbb + ab * (1 - ba); ra = ba + aa * (1 - ba);
                        } else {
                            rr = ar * wa + brr * wb; rg = ag * wa + bgg * wb; rb = ab * wa + bbb * wb; ra = aa * wa + ba * wb;
                        }
                        size_t o = ((size_t) y * w + x) * 4;
                        if (ra > 1e-6f) {
                            result.data[o] = rr / ra; result.data[o + 1] = rg / ra; result.data[o + 2] = rb / ra;
                        }
                        result.data[o + 3] = ra.clamp (0, 1);
                    }
                }
            }, 4);
            return result;
        }

        public FloatImage from_surface (Cairo.ImageSurface surface) {
            surface.flush ();
            int w = surface.get_width (), h = surface.get_height ();
            int stride = surface.get_stride ();
            unowned uint8[] data = surface.get_data ();
            var img = new FloatImage (w, h);
            unowned float[] lut = Tone.table8 ();
            Parallel.range (h, (y0, y1) => {
                for (int y = y0; y < y1; y++) {
                    for (int x = 0; x < w; x++) {
                        int s = y * stride + x * 4;
                        uint8 a = data[s + 3];
                        size_t d = ((size_t) y * w + x) * 4;
                        if (a == 0) continue;
                        uint8 r = (uint8) int.min (255, data[s + 2] * 255 / a), g = (uint8) int.min (255, data[s + 1] * 255 / a), b = (uint8) int.min (255, data[s] * 255 / a);
                        img.data[d] = lut[r]; img.data[d + 1] = lut[g]; img.data[d + 2] = lut[b]; img.data[d + 3] = a / 255.0f;
                    }
                }
            });
            return img;
        }

        public Cairo.ImageSurface to_surface (FloatImage img) {
            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, img.width, img.height);
            int stride = surface.get_stride ();
            unowned uint8[] data = surface.get_data ();
            int w = img.width;
            for (int y = 0; y < img.height; y++) {
                for (int x = 0; x < w; x++) {
                    size_t i = ((size_t) y * w + x) * 4;
                    float a = img.data[i + 3].clamp (0, 1);
                    int s = y * stride + x * 4;
                    data[s + 2] = (uint8) (Tone.encode (img.data[i].clamp (0, 1)) * a * 255 + 0.5f);
                    data[s + 1] = (uint8) (Tone.encode (img.data[i + 1].clamp (0, 1)) * a * 255 + 0.5f);
                    data[s] = (uint8) (Tone.encode (img.data[i + 2].clamp (0, 1)) * a * 255 + 0.5f);
                    data[s + 3] = (uint8) (a * 255 + 0.5f);
                }
            }
            surface.mark_dirty ();
            return surface;
        }
    }
}
