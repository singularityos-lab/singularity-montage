using Singularity.Imaging;

namespace Singularity.Apps.Montage {
    public class FxState : Object {
        public Gee.HashMap<string, Object> objects = new Gee.HashMap<string, Object> ();
        public Gee.HashMap<string, string> keys = new Gee.HashMap<string, string> ();
        public Mutex mutex;

        public Object? cached (string id, string key) {
            mutex.lock ();
            Object? result = keys[id] == key ? objects[id] : null;
            mutex.unlock ();
            return result;
        }

        public void store (string id, string key, Object value) {
            mutex.lock ();
            keys[id] = key;
            objects[id] = value;
            mutex.unlock ();
        }
    }

    public class FxContext : Object {
        public int64 key_time;
        public int64 source_time;
        public double scale = 1;
        public FxState state;
        public string? lut_root;

        public FxContext (FxState state) {
            this.state = state;
        }
    }

    public class CurveSet : Object {
        public CurveLut master;
        public CurveLut red;
        public CurveLut green;
        public CurveLut blue;
        public CurveLut? hue_sat;
        public CurveLut? hue_hue;
        public CurveLut? luma_sat;
    }

    public class StabilizeData : Object {
        int64[] times = {};
        double[] xs = {};
        double[] ys = {};
        double[] angles = {};
        public double zoom = 1;
        public int width = 1;

        public int size {
            get { return times.length; }
        }

        public static StabilizeData parse (string text) {
            var d = new StabilizeData ();
            foreach (var entry in text.split (";")) {
                if (entry.has_prefix ("w=")) {
                    d.width = int.max (1, int.parse (entry.substring (2)));
                    continue;
                }
                if (entry.has_prefix ("z=")) {
                    d.zoom = double.parse (entry.substring (2));
                    continue;
                }
                var p = entry.split (":");
                if (p.length != 2) continue;
                var v = p[1].split (",");
                if (v.length != 3) continue;
                d.times += int64.parse (p[0]);
                d.xs += double.parse (v[0]);
                d.ys += double.parse (v[1]);
                d.angles += double.parse (v[2]);
            }
            return d;
        }

        public bool lookup (int64 t, out double x, out double y, out double a) {
            x = y = a = 0;
            if (times.length == 0) return false;
            int lo = 0, hi = times.length - 1;
            while (lo < hi) {
                int mid = (lo + hi + 1) / 2;
                if (times[mid] <= t) lo = mid;
                else hi = mid - 1;
            }
            x = xs[lo];
            y = ys[lo];
            a = angles[lo];
            return true;
        }
    }

    namespace VideoFx {
        public void apply (Effect e, FloatImage img, FxContext ctx) {
            if (!e.enabled) return;
            switch (e.type) {
                case "color.primary": primary (e, img, ctx); break;
                case "color.wheels": wheels (e, img, ctx); break;
                case "color.curves": curves (e, img, ctx); break;
                case "color.lut": lut (e, img, ctx); break;
                case "color.match": match (e, img, ctx); break;
                case "color.bw": bw (e, img, ctx); break;
                case "key.chroma": chroma (e, img, ctx); break;
                case "key.luma": luma_key (e, img, ctx); break;
                case "mask": mask (e, img, ctx); break;
                case "stabilize": stabilize (e, img, ctx); break;
                case "blur": blur (e, img, ctx); break;
                case "sharpen": sharpen (e, img, ctx); break;
                case "vignette": vignette (e, img, ctx); break;
                case "mosaic": mosaic (e, img, ctx); break;
                case "invert": invert (e, img, ctx); break;
                case "glow": glow (e, img, ctx); break;
                default:
                    if (e.type.has_prefix ("gst:")) GstFilter.apply (e, img, ctx);
                    break;
            }
        }

        double v (Effect e, string name, FxContext ctx) {
            var a = e.params.values[name];
            return a != null ? a.at (ctx.key_time) : Catalog.default_of (e, name);
        }

        void per_pixel (FloatImage img, owned PixelFunc f) {
            int n = (int) img.pixel_count ();
            Parallel.range (n, (a, b) => {
                for (int p = a; p < b; p++) f (img.data, (size_t) p * 4);
            }, 4096);
        }

        delegate void PixelFunc (float[] d, size_t i);

        public void primary (Effect e, FloatImage img, FxContext ctx) {
            float exposure = (float) Math.pow (2, v (e, "exposure", ctx));
            float contrast = (float) v (e, "contrast", ctx);
            float sat = (float) (v (e, "saturation", ctx) / 100);
            float vib = (float) (v (e, "vibrance", ctx) / 100);
            float hi = (float) (v (e, "highlights", ctx) / 100);
            float sh = (float) (v (e, "shadows", ctx) / 100);
            float wh = (float) (v (e, "whites", ctx) / 100);
            float bl = (float) (v (e, "blacks", ctx) / 100);
            float gr, gg, gb;
            Grade.white_balance_gains (v (e, "temperature", ctx), v (e, "tint", ctx), out gr, out gg, out gb);
            float pivot = 0.18f;
            per_pixel (img, (d, i) => {
                float r = d[i] * exposure * gr, g = d[i + 1] * exposure * gg, b = d[i + 2] * exposure * gb;
                if (contrast != 1) {
                    r = r > 0 ? pivot * Math.powf (r / pivot, contrast) : r;
                    g = g > 0 ? pivot * Math.powf (g / pivot, contrast) : g;
                    b = b > 0 ? pivot * Math.powf (b / pivot, contrast) : b;
                }
                if (hi != 0 || sh != 0 || wh != 0 || bl != 0) {
                    float y = Grade.luma (r, g, b);
                    float py = Tone.encode (y.clamp (0, 1));
                    float hw = py * py;
                    float sw = (1 - py) * (1 - py);
                    float ny = py + hi * 0.25f * hw * (1 - py) * 4 + sh * 0.25f * sw * py * 4 + wh * 0.15f * py + bl * 0.15f * (1 - py);
                    float target = Tone.decode (ny.clamp (0, 1.5f));
                    float k = y > 1e-5f ? target / y : 1;
                    r *= k; g *= k; b *= k;
                }
                if (sat != 1 || vib != 0) {
                    float y = Grade.luma (r, g, b);
                    float s = sat;
                    if (vib != 0) {
                        float mx = float.max (r, float.max (g, b)), mn = float.min (r, float.min (g, b));
                        float cur = mx > 1e-5f ? (mx - mn) / mx : 0;
                        s *= 1 + vib * (1 - cur);
                    }
                    r = y + (r - y) * s;
                    g = y + (g - y) * s;
                    b = y + (b - y) * s;
                }
                d[i] = r; d[i + 1] = g; d[i + 2] = b;
            });
        }

        public void wheels (Effect e, FloatImage img, FxContext ctx) {
            float[] lift = new float[3], gamma = new float[3], gain = new float[3], offset = new float[3];
            string[] ch = { "r", "g", "b" };
            float ll = (float) v (e, "lift-l", ctx), gl = (float) v (e, "gamma-l", ctx), nl = (float) v (e, "gain-l", ctx), ol = (float) v (e, "offset-l", ctx);
            for (int c = 0; c < 3; c++) {
                lift[c] = (float) v (e, "lift-" + ch[c], ctx) * 0.5f + ll * 0.5f;
                gamma[c] = (float) Math.pow (2, -(v (e, "gamma-" + ch[c], ctx) + gl));
                gain[c] = (float) (1 + v (e, "gain-" + ch[c], ctx) + nl);
                offset[c] = (float) (v (e, "offset-" + ch[c], ctx) + ol) * 0.25f;
            }
            per_pixel (img, (d, i) => {
                for (int c = 0; c < 3; c++) {
                    float p = Tone.encode (d[i + c]);
                    p = p * gain[c] + lift[c] * (1 - p) + offset[c];
                    p = p > 0 ? Math.powf (p, gamma[c]) : p;
                    d[i + c] = Tone.decode (p);
                }
            });
        }

        CurveSet curve_set (Effect e, FxContext ctx) {
            string key = "%s|%s|%s|%s|%s|%s|%s".printf (e.params.text ("master"), e.params.text ("red"), e.params.text ("green"), e.params.text ("blue"),
                e.params.text ("hue-sat"), e.params.text ("hue-hue"), e.params.text ("luma-sat"));
            var cached = ctx.state.cached (e.id, key) as CurveSet;
            if (cached != null) return cached;
            var set = new CurveSet ();
            set.master = CurveLut.parse (e.params.text ("master", "0,0;1,1"));
            set.red = CurveLut.parse (e.params.text ("red", "0,0;1,1"));
            set.green = CurveLut.parse (e.params.text ("green", "0,0;1,1"));
            set.blue = CurveLut.parse (e.params.text ("blue", "0,0;1,1"));
            if (e.params.text ("hue-sat") != "") set.hue_sat = CurveLut.parse (e.params.text ("hue-sat"), true);
            if (e.params.text ("hue-hue") != "") set.hue_hue = CurveLut.parse (e.params.text ("hue-hue"), true);
            if (e.params.text ("luma-sat") != "") set.luma_sat = CurveLut.parse (e.params.text ("luma-sat"));
            ctx.state.store (e.id, key, set);
            return set;
        }

        public void curves (Effect e, FloatImage img, FxContext ctx) {
            var set = curve_set (e, ctx);
            bool rgb = !set.master.is_identity () || !set.red.is_identity () || !set.green.is_identity () || !set.blue.is_identity ();
            per_pixel (img, (d, i) => {
                float r = Tone.encode (d[i]), g = Tone.encode (d[i + 1]), b = Tone.encode (d[i + 2]);
                if (rgb) {
                    r = set.red.map (set.master.map (r));
                    g = set.green.map (set.master.map (g));
                    b = set.blue.map (set.master.map (b));
                }
                if (set.hue_sat != null || set.hue_hue != null || set.luma_sat != null) {
                    float h, s, val;
                    Grade.rgb_to_hsv (r, g, b, out h, out s, out val);
                    float y = Grade.luma (r, g, b);
                    if (set.hue_sat != null) s *= set.hue_sat.map_periodic (h) * 2;
                    if (set.luma_sat != null) s *= set.luma_sat.map (y.clamp (0, 1)) * 2;
                    if (set.hue_hue != null) h += set.hue_hue.map_periodic (h) - 0.5f;
                    Grade.hsv_to_rgb (h, s.clamp (0, 4), val, out r, out g, out b);
                }
                d[i] = Tone.decode (r); d[i + 1] = Tone.decode (g); d[i + 2] = Tone.decode (b);
            });
        }

        public Lut3D? load_lut (string path, FxContext ctx, string id) {
            if (path == "") return null;
            var cached = ctx.state.cached (id, path) as Lut3D;
            if (cached != null) return cached;
            try {
                string resolved = path;
                if (!Path.is_absolute (path) && ctx.lut_root != null) resolved = Path.build_filename (ctx.lut_root, path);
                var lut = Lut3D.load (resolved);
                ctx.state.store (id, path, lut);
                return lut;
            } catch (Error err) {
                warning ("LUT %s: %s", path, err.message);
                return null;
            }
        }

        public void lut (Effect e, FloatImage img, FxContext ctx) {
            var table = load_lut (e.params.text ("file"), ctx, e.id);
            if (table == null) return;
            float mix = (float) (v (e, "intensity", ctx) / 100);
            per_pixel (img, (d, i) => {
                float r = Tone.encode (d[i]), g = Tone.encode (d[i + 1]), b = Tone.encode (d[i + 2]);
                float or, og, ob;
                table.apply (r, g, b, out or, out og, out ob);
                d[i] = Tone.decode (r + (or - r) * mix);
                d[i + 1] = Tone.decode (g + (og - g) * mix);
                d[i + 2] = Tone.decode (b + (ob - b) * mix);
            });
        }

        public void match (Effect e, FloatImage img, FxContext ctx) {
            float gr = (float) v (e, "gain-r", ctx), gg = (float) v (e, "gain-g", ctx), gb = (float) v (e, "gain-b", ctx);
            float or = (float) v (e, "offset-r", ctx), og = (float) v (e, "offset-g", ctx), ob = (float) v (e, "offset-b", ctx);
            per_pixel (img, (d, i) => {
                d[i] = Tone.decode (Tone.encode (d[i]) * gr + or);
                d[i + 1] = Tone.decode (Tone.encode (d[i + 1]) * gg + og);
                d[i + 2] = Tone.decode (Tone.encode (d[i + 2]) * gb + ob);
            });
        }

        public void bw (Effect e, FloatImage img, FxContext ctx) {
            float amount = (float) (v (e, "amount", ctx) / 100);
            per_pixel (img, (d, i) => {
                float y = Grade.luma (d[i], d[i + 1], d[i + 2]);
                d[i] += (y - d[i]) * amount;
                d[i + 1] += (y - d[i + 1]) * amount;
                d[i + 2] += (y - d[i + 2]) * amount;
            });
        }

        public void parse_color (string text, out float r, out float g, out float b, out float a) {
            r = g = b = 0;
            a = 1;
            string t = text.strip ();
            if (!t.has_prefix ("#") || (t.length != 7 && t.length != 9)) return;
            r = hex (t.substring (1, 2)) / 255.0f;
            g = hex (t.substring (3, 2)) / 255.0f;
            b = hex (t.substring (5, 2)) / 255.0f;
            if (t.length == 9) a = hex (t.substring (7, 2)) / 255.0f;
        }

        int hex (string s) {
            int v = 0;
            for (int i = 0; i < s.length; i++) {
                char ch = s[i].tolower ();
                v *= 16;
                if (ch >= '0' && ch <= '9') v += ch - '0';
                else if (ch >= 'a' && ch <= 'f') v += ch - 'a' + 10;
            }
            return v;
        }

        public void chroma (Effect e, FloatImage img, FxContext ctx) {
            float kr, kg, kb, ka;
            parse_color (e.params.text ("color", "#00ff00ff"), out kr, out kg, out kb, out ka);
            float kcb = -0.1146f * kr - 0.3854f * kg + 0.5f * kb;
            float kcr = 0.5f * kr - 0.4542f * kg - 0.0458f * kb;
            float klen = Math.sqrtf (kcb * kcb + kcr * kcr);
            float tol = (float) (v (e, "tolerance", ctx) / 100) * 0.6f;
            float soft = float.max (0.001f, (float) (v (e, "softness", ctx) / 100) * 0.5f);
            float spill = (float) (v (e, "spill", ctx) / 100);
            double choke = v (e, "choke", ctx) * ctx.scale;
            double feather = v (e, "feather", ctx) * ctx.scale;
            bool matte = v (e, "matte", ctx) >= 0.5;
            int key_channel = kg >= kr && kg >= kb ? 1 : (kb >= kr ? 2 : 0);
            per_pixel (img, (d, i) => {
                float r = Tone.encode (d[i]), g = Tone.encode (d[i + 1]), b = Tone.encode (d[i + 2]);
                float cb = -0.1146f * r - 0.3854f * g + 0.5f * b;
                float cr = 0.5f * r - 0.4542f * g - 0.0458f * b;
                float dcb = cb - kcb, dcr = cr - kcr;
                float dist = Math.sqrtf (dcb * dcb + dcr * dcr);
                float alpha = ((dist - tol) / soft).clamp (0, 1);
                d[i + 3] *= alpha;
                if (spill > 0 && klen > 1e-5f) {
                    float k0 = d[i + key_channel];
                    float o1 = d[i + (key_channel + 1) % 3], o2 = d[i + (key_channel + 2) % 3];
                    float lim = (o1 + o2) / 2;
                    float excess = k0 - lim;
                    if (excess > 0) {
                        d[i + key_channel] = k0 - excess * spill;
                        float lift = excess * spill * 0.15f;
                        d[i + (key_channel + 1) % 3] = o1 + lift;
                        d[i + (key_channel + 2) % 3] = o2 + lift;
                    }
                }
            });
            if (choke.abs () >= 0.5) morph_alpha (img, (int) Math.round (choke));
            if (feather >= 0.3) blur_alpha (img, feather);
            if (matte) {
                per_pixel (img, (d, i) => {
                    float a = d[i + 3];
                    d[i] = d[i + 1] = d[i + 2] = a;
                    d[i + 3] = 1;
                });
            }
        }

        public void luma_key (Effect e, FloatImage img, FxContext ctx) {
            float low = (float) (v (e, "low", ctx) / 100), high = (float) (v (e, "high", ctx) / 100);
            float soft = float.max (0.001f, (float) (v (e, "softness", ctx) / 100));
            bool inv = v (e, "invert", ctx) >= 0.5;
            per_pixel (img, (d, i) => {
                float y = Tone.encode (Grade.luma (d[i], d[i + 1], d[i + 2]));
                float inside = float.min (((y - low) / soft + 1).clamp (0, 1), ((high - y) / soft + 1).clamp (0, 1));
                float alpha = inv ? inside : 1 - inside;
                d[i + 3] *= alpha;
            });
        }

        public void morph_alpha (FloatImage img, int radius) {
            int w = img.width, h = img.height;
            int r = radius.abs ();
            bool erode = radius > 0;
            var tmp = new float[w * h];
            Parallel.range (h, (y0, y1) => {
                for (int y = y0; y < y1; y++) {
                    for (int x = 0; x < w; x++) {
                        float m = erode ? 1 : 0;
                        for (int k = int.max (0, x - r); k <= int.min (w - 1, x + r); k++) {
                            float a = img.data[((size_t) y * w + k) * 4 + 3];
                            m = erode ? float.min (m, a) : float.max (m, a);
                        }
                        tmp[y * w + x] = m;
                    }
                }
            });
            Parallel.range (h, (y0, y1) => {
                for (int y = y0; y < y1; y++) {
                    for (int x = 0; x < w; x++) {
                        float m = erode ? 1 : 0;
                        for (int k = int.max (0, y - r); k <= int.min (h - 1, y + r); k++) {
                            float a = tmp[k * w + x];
                            m = erode ? float.min (m, a) : float.max (m, a);
                        }
                        img.data[((size_t) y * w + x) * 4 + 3] = m;
                    }
                }
            });
        }

        public void blur_alpha (FloatImage img, double sigma) {
            var plane = img.channel (3);
            var blurred = Filters.gaussian_plane (plane, img.width, img.height, sigma);
            img.set_channel (3, blurred);
        }

        public float[] rasterize_path (string path, int w, int h, double dx, double dy, double expansion) {
            var surface = new Cairo.ImageSurface (Cairo.Format.A8, w, h);
            var cr = new Cairo.Context (surface);
            var pts = new Gee.ArrayList<double?> ();
            foreach (var pair in path.split (";")) {
                var p = pair.split (",");
                if (p.length < 2) continue;
                pts.add (double.parse (p[0]) / 100 * w + dx);
                pts.add (double.parse (p[1]) / 100 * h + dy);
            }
            int n = pts.size / 2;
            if (n >= 3) {
                for (int i = 0; i < n; i++) {
                    double x0 = pts[i * 2], y0 = pts[i * 2 + 1];
                    double x1 = pts[((i + 1) % n) * 2], y1 = pts[((i + 1) % n) * 2 + 1];
                    double xp = pts[((i + n - 1) % n) * 2], yp = pts[((i + n - 1) % n) * 2 + 1];
                    double x2 = pts[((i + 2) % n) * 2], y2 = pts[((i + 2) % n) * 2 + 1];
                    if (i == 0) cr.move_to (x0, y0);
                    double c1x = x0 + (x1 - xp) / 6, c1y = y0 + (y1 - yp) / 6;
                    double c2x = x1 - (x2 - x0) / 6, c2y = y1 - (y2 - y0) / 6;
                    if (path.contains ("|smooth")) cr.curve_to (c1x, c1y, c2x, c2y, x1, y1);
                    else cr.line_to (x1, y1);
                }
                cr.close_path ();
                cr.set_source_rgba (0, 0, 0, 1);
                if (expansion > 0) {
                    cr.set_line_width (expansion * 2);
                    cr.set_line_join (Cairo.LineJoin.ROUND);
                    cr.fill_preserve ();
                    cr.stroke ();
                } else if (expansion < 0) {
                    cr.fill_preserve ();
                    cr.set_operator (Cairo.Operator.CLEAR);
                    cr.set_line_width (-expansion * 2);
                    cr.set_line_join (Cairo.LineJoin.ROUND);
                    cr.stroke ();
                } else {
                    cr.fill ();
                }
            }
            surface.flush ();
            var result = new float[w * h];
            unowned uint8[] data = surface.get_data ();
            int stride = surface.get_stride ();
            for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) result[y * w + x] = data[y * stride + x] / 255.0f;
            return result;
        }

        public void mask (Effect e, FloatImage img, FxContext ctx) {
            int w = img.width, h = img.height;
            double dx = v (e, "track-x", ctx) * ctx.scale, dy = v (e, "track-y", ctx) * ctx.scale;
            var plane = rasterize_path (e.params.text ("path"), w, h, dx, dy, v (e, "expansion", ctx) * ctx.scale);
            double feather = v (e, "feather", ctx) * ctx.scale;
            if (feather >= 0.3) plane = Filters.gaussian_plane (plane, w, h, feather / 2);
            float opacity = (float) (v (e, "opacity", ctx) / 100);
            bool inv = v (e, "invert", ctx) >= 0.5;
            string mode = e.params.text ("mode", "add");
            Parallel.range (h, (y0, y1) => {
                for (int y = y0; y < y1; y++) {
                    for (int x = 0; x < w; x++) {
                        float m = plane[y * w + x];
                        if (inv) m = 1 - m;
                        m *= opacity;
                        size_t i = ((size_t) y * w + x) * 4 + 3;
                        if (mode == "subtract") img.data[i] *= 1 - m;
                        else img.data[i] *= m;
                    }
                }
            });
        }

        public void stabilize (Effect e, FloatImage img, FxContext ctx) {
            string text = e.params.text ("data");
            if (text == "") return;
            var data = ctx.state.cached (e.id, text) as StabilizeData;
            if (data == null) {
                data = StabilizeData.parse (text);
                ctx.state.store (e.id, text, data);
            }
            double x, y, a;
            if (!data.lookup (ctx.source_time, out x, out y, out a)) return;
            double k = (double) img.width / data.width;
            double smooth = v (e, "smoothness", ctx) / 50.0;
            x *= k * smooth.clamp (0, 2);
            y *= k * smooth.clamp (0, 2);
            a *= smooth.clamp (0, 2);
            double zoom = v (e, "crop", ctx) >= 0.5 ? data.zoom : 1;
            var src = img.copy ();
            int w = img.width, h = img.height;
            double cx = w / 2.0, cy = h / 2.0;
            double ca = Math.cos (-a), sa = Math.sin (-a);
            Parallel.range (h, (y0, y1) => {
                for (int py = y0; py < y1; py++) {
                    for (int px = 0; px < w; px++) {
                        double ux = (px + 0.5 - cx) / zoom, uy = (py + 0.5 - cy) / zoom;
                        double sx = ca * ux - sa * uy + cx - x;
                        double sy = sa * ux + ca * uy + cy - y;
                        float r, g, b, al;
                        size_t i = img.offset (px, py);
                        if (sx < 0 || sy < 0 || sx >= w || sy >= h) {
                            img.data[i] = img.data[i + 1] = img.data[i + 2] = img.data[i + 3] = 0;
                            continue;
                        }
                        src.sample (sx, sy, out r, out g, out b, out al);
                        img.data[i] = r; img.data[i + 1] = g; img.data[i + 2] = b; img.data[i + 3] = al;
                    }
                }
            });
        }

        public void blur (Effect e, FloatImage img, FxContext ctx) {
            double r = v (e, "radius", ctx) * ctx.scale;
            if (r < 0.3) return;
            var blurred = Filters.gaussian (img, r / 2, true);
            Memory.copy (img.data, blurred.data, img.data.length * sizeof (float));
        }

        public void sharpen (Effect e, FloatImage img, FxContext ctx) {
            float amount = (float) (v (e, "amount", ctx) / 100);
            double r = v (e, "radius", ctx) * ctx.scale;
            var blurred = Filters.gaussian (img, double.max (0.3, r), false);
            per_pixel (img, (d, i) => {
                for (int c = 0; c < 3; c++) d[i + c] = d[i + c] + (d[i + c] - blurred.data[i + c]) * amount;
            });
        }

        public void vignette (Effect e, FloatImage img, FxContext ctx) {
            float amount = (float) (v (e, "amount", ctx) / 100);
            float size = (float) (v (e, "size", ctx) / 100);
            float soft = float.max (0.01f, (float) (v (e, "softness", ctx) / 100));
            int w = img.width, h = img.height;
            Parallel.range (h, (y0, y1) => {
                for (int y = y0; y < y1; y++) {
                    for (int x = 0; x < w; x++) {
                        float nx = (x + 0.5f) / w * 2 - 1, ny = (y + 0.5f) / h * 2 - 1;
                        float dist = Math.sqrtf (nx * nx + ny * ny) / 1.4142f;
                        float t = ((dist - size * 0.7f) / soft).clamp (0, 1);
                        t = t * t * (3 - 2 * t);
                        float k = amount >= 0 ? 1 - amount * t : 1 - amount * t;
                        size_t i = ((size_t) y * w + x) * 4;
                        img.data[i] *= k; img.data[i + 1] *= k; img.data[i + 2] *= k;
                    }
                }
            });
        }

        public void mosaic (Effect e, FloatImage img, FxContext ctx) {
            int cell = int.max (1, (int) Math.round (v (e, "size", ctx) * ctx.scale));
            int w = img.width, h = img.height;
            for (int cy = 0; cy < h; cy += cell) {
                for (int cx = 0; cx < w; cx += cell) {
                    float r = 0, g = 0, b = 0, a = 0;
                    int n = 0;
                    for (int y = cy; y < int.min (h, cy + cell); y++) for (int x = cx; x < int.min (w, cx + cell); x++) {
                        size_t i = img.offset (x, y);
                        r += img.data[i]; g += img.data[i + 1]; b += img.data[i + 2]; a += img.data[i + 3]; n++;
                    }
                    r /= n; g /= n; b /= n; a /= n;
                    for (int y = cy; y < int.min (h, cy + cell); y++) for (int x = cx; x < int.min (w, cx + cell); x++) img.set_pixel (x, y, r, g, b, a);
                }
            }
        }

        public void invert (Effect e, FloatImage img, FxContext ctx) {
            float amount = (float) (v (e, "amount", ctx) / 100);
            per_pixel (img, (d, i) => {
                for (int c = 0; c < 3; c++) {
                    float p = Tone.encode (d[i + c]);
                    d[i + c] = Tone.decode (p + (1 - 2 * p) * amount);
                }
            });
        }

        public void glow (Effect e, FloatImage img, FxContext ctx) {
            float threshold = (float) (v (e, "threshold", ctx) / 100);
            float intensity = (float) (v (e, "intensity", ctx) / 100);
            var bright = img.copy ();
            per_pixel (bright, (d, i) => {
                float y = Tone.encode (Grade.luma (d[i], d[i + 1], d[i + 2]));
                float k = ((y - threshold) / float.max (0.01f, 1 - threshold)).clamp (0, 1);
                d[i] *= k; d[i + 1] *= k; d[i + 2] *= k;
            });
            var blurred = Filters.gaussian (bright, double.max (0.5, v (e, "radius", ctx) * ctx.scale / 2), false);
            per_pixel (img, (d, i) => {
                for (int c = 0; c < 3; c++) d[i + c] += blurred.data[i + c] * intensity;
            });
        }
    }

    public class GstFilter : Object {
        Gst.Pipeline pipeline;
        Gst.App.Src src;
        Gst.App.Sink sink;
        int width;
        int height;
        public string? failure;

        public GstFilter (string element, string props, int width, int height) throws Error {
            this.width = width;
            this.height = height;
            var desc = "appsrc name=src format=time is-live=false do-timestamp=false ! videoconvert ! %s %s ! videoconvert ! video/x-raw,format=RGBA,width=%d,height=%d ! appsink name=sink sync=false"
                .printf (element, sanitize (props), width, height);
            pipeline = (Gst.Pipeline) Gst.parse_launch (desc);
            src = (Gst.App.Src) pipeline.get_by_name ("src");
            sink = (Gst.App.Sink) pipeline.get_by_name ("sink");
            src.caps = Gst.Caps.from_string ("video/x-raw,format=RGBA,width=%d,height=%d,framerate=0/1,pixel-aspect-ratio=1/1".printf (width, height));
            if (pipeline.set_state (Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE) throw new IOError.FAILED (_("The filter %s could not start.").printf (element));
        }

        static string sanitize (string props) {
            var sb = new StringBuilder ();
            foreach (var p in props.split (";")) {
                var kv = p.split ("=", 2);
                if (kv.length != 2) continue;
                string k = kv[0].strip (), val = kv[1].strip ();
                bool ok = k.length > 0;
                for (int i = 0; i < k.length; i++) if (!(k[i].isalnum () || k[i] == '-' || k[i] == '_')) ok = false;
                for (int i = 0; i < val.length; i++) if (val[i] == '!' || val[i] == ' ' || val[i] == '"' || val[i] == '\'') ok = false;
                if (ok) sb.append (" %s=%s".printf (k, val));
            }
            return sb.str;
        }

        public void process (FloatImage img, int64 pts) throws Error {
            var bytes = ColorPipeline.encode_rgba8 (img, false);
            var buffer = new Gst.Buffer.wrapped (bytes);
            buffer.pts = pts;
            buffer.duration = 33333333;
            src.push_buffer (buffer);
            var sample = sink.try_pull_sample (5 * Gst.SECOND);
            if (sample == null) throw new IOError.TIMED_OUT (_("The filter did not return a frame."));
            Gst.MapInfo map;
            var b = sample.get_buffer ();
            if (!b.map (out map, Gst.MapFlags.READ)) return;
            unowned float[] lut = Tone.table8 ();
            int n = width * height;
            for (int p = 0; p < n && p * 4 + 3 < map.size; p++) {
                img.data[p * 4] = lut[map.data[p * 4]];
                img.data[p * 4 + 1] = lut[map.data[p * 4 + 1]];
                img.data[p * 4 + 2] = lut[map.data[p * 4 + 2]];
                img.data[p * 4 + 3] = map.data[p * 4 + 3] / 255.0f;
            }
            b.unmap (map);
        }

        public static void apply (Effect e, FloatImage img, FxContext ctx) {
            string element = e.type.substring (4);
            string key = "%s|%s|%dx%d".printf (element, e.params.text ("props"), img.width, img.height);
            var filter = ctx.state.cached (e.id, key) as GstFilter;
            try {
                if (filter == null) {
                    filter = new GstFilter (element, e.params.text ("props"), img.width, img.height);
                    ctx.state.store (e.id, key, filter);
                }
                filter.process (img, ctx.source_time);
            } catch (Error err) {
                warning ("filter %s: %s", element, err.message);
            }
        }

        ~GstFilter () {
            if (pipeline != null) pipeline.set_state (Gst.State.NULL);
        }
    }
}
