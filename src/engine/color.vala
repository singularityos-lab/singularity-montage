using Singularity.Imaging;

namespace Singularity.Apps.Montage {
    namespace Tone {
        const int SIZE = 4096;
        float[]? encode_table;
        float[]? decode8;
        float[]? decode16;
        Mutex lock;

        void init () {
            lock.lock ();
            if (encode_table == null) {
                var e = new float[SIZE + 1];
                for (int i = 0; i <= SIZE; i++) e[i] = Transfer.linear_to_srgb ((float) i / SIZE);
                var d = new float[256];
                for (int i = 0; i < 256; i++) d[i] = Transfer.srgb_to_linear (i / 255.0f);
                var w = new float[65536];
                for (int i = 0; i < 65536; i++) w[i] = Transfer.srgb_to_linear (i / 65535.0f);
                decode8 = d;
                decode16 = w;
                encode_table = e;
            }
            lock.unlock ();
        }

        public inline float encode (float v) {
            if (v <= 0) return v < 0 ? -Transfer.linear_to_srgb (-v) : 0;
            if (v >= 1) return Transfer.linear_to_srgb (v);
            float x = v * SIZE;
            int i = (int) x;
            float f = x - i;
            return encode_table[i] * (1 - f) + encode_table[i + 1] * f;
        }

        public inline float decode (float v) {
            return Transfer.srgb_to_linear (v);
        }

        public unowned float[] table8 () {
            init ();
            return decode8;
        }

        public unowned float[] table16 () {
            init ();
            return decode16;
        }

        public void ready () {
            init ();
        }

        public double pq_to_nits (double v) {
            const double m1 = 0.1593017578125, m2 = 78.84375, c1 = 0.8359375, c2 = 18.8515625, c3 = 18.6875;
            double p = Math.pow (v.clamp (0, 1), 1 / m2);
            return 10000 * Math.pow (double.max (p - c1, 0) / (c2 - c3 * p), 1 / m1);
        }

        public double nits_to_pq (double nits) {
            const double m1 = 0.1593017578125, m2 = 78.84375, c1 = 0.8359375, c2 = 18.8515625, c3 = 18.6875;
            double y = Math.pow ((nits / 10000).clamp (0, 1), m1);
            return Math.pow ((c1 + c2 * y) / (1 + c3 * y), m2);
        }

        public double hlg_to_scene (double v) {
            const double a = 0.17883277, b = 0.28466892, c = 0.55991073;
            v = v.clamp (0, 1);
            return v <= 0.5 ? v * v / 3 : (Math.exp ((v - c) / a) + b) / 12;
        }

        public double scene_to_hlg (double e) {
            const double a = 0.17883277, b = 0.28466892, c = 0.55991073;
            e = e.clamp (0, 1);
            return e <= 1.0 / 12 ? Math.sqrt (3 * e) : a * Math.log (12 * e - b) + c;
        }

        public const double REFERENCE_WHITE = 203;
    }

    public class ColorPipeline : Object {
        public static double[] matrix (string from, string to) {
            if (from == to) return { 1, 0, 0, 0, 1, 0, 0, 0, 1 };
            var a = from == "rec2020" ? Primaries.rec2020 () : Primaries.rec709 ();
            var b = to == "rec2020" ? Primaries.rec2020 () : Primaries.rec709 ();
            return Primaries.conversion (a, b);
        }

        public static string primaries_of (string colorimetry, string transfer) {
            if (colorimetry.contains ("bt2020") || colorimetry.has_prefix ("bt2100") || transfer != "sdr") return "rec2020";
            return "rec709";
        }

        public static string working_of (string sequence_space) {
            return sequence_space.has_prefix ("rec2020") ? "rec2020" : "rec709";
        }

        public static FloatImage to_working (Frame f, string transfer, string primaries, string working) {
            Tone.ready ();
            var img = new FloatImage (f.width, f.height);
            int w = f.width, h = f.height;
            bool convert = primaries != working;
            double[] m = convert ? matrix (primaries, working) : new double[0];
            if (!f.wide) {
                unowned float[] lut = Tone.table8 ();
                unowned uint8[] src = f.bytes;
                Parallel.range (h, (y0, y1) => {
                    for (int y = y0; y < y1; y++) {
                        size_t row = (size_t) y * w * 4;
                        for (int x = 0; x < w; x++) {
                            size_t i = row + x * 4;
                            img.data[i] = lut[src[i]];
                            img.data[i + 1] = lut[src[i + 1]];
                            img.data[i + 2] = lut[src[i + 2]];
                            img.data[i + 3] = src[i + 3] / 255.0f;
                        }
                    }
                });
            } else {
                unowned uint16[] src = f.words;
                float[] lut;
                if (transfer == "pq") {
                    lut = new float[65536];
                    for (int i = 0; i < 65536; i++) lut[i] = (float) (Tone.pq_to_nits (i / 65535.0) / Tone.REFERENCE_WHITE);
                } else if (transfer == "hlg") {
                    lut = new float[65536];
                    for (int i = 0; i < 65536; i++) lut[i] = (float) (Tone.hlg_to_scene (i / 65535.0) * 1000.0 / Tone.REFERENCE_WHITE);
                } else {
                    lut = Tone.table16 ();
                }
                Parallel.range (h, (y0, y1) => {
                    for (int y = y0; y < y1; y++) {
                        size_t row = (size_t) y * w * 4;
                        for (int x = 0; x < w; x++) {
                            size_t i = row + x * 4;
                            img.data[i] = lut[src[i]];
                            img.data[i + 1] = lut[src[i + 1]];
                            img.data[i + 2] = lut[src[i + 2]];
                            img.data[i + 3] = src[i + 3] / 65535.0f;
                        }
                    }
                });
            }
            if (convert) apply_matrix (img, m);
            return img;
        }

        public static void apply_matrix (FloatImage img, double[] m) {
            float m0 = (float) m[0], m1 = (float) m[1], m2 = (float) m[2], m3 = (float) m[3], m4 = (float) m[4], m5 = (float) m[5], m6 = (float) m[6], m7 = (float) m[7], m8 = (float) m[8];
            int n = (int) img.pixel_count ();
            Parallel.range (n, (a, b) => {
                for (int p = a; p < b; p++) {
                    size_t i = (size_t) p * 4;
                    float r = img.data[i], g = img.data[i + 1], bl = img.data[i + 2];
                    img.data[i] = m0 * r + m1 * g + m2 * bl;
                    img.data[i + 1] = m3 * r + m4 * g + m5 * bl;
                    img.data[i + 2] = m6 * r + m7 * g + m8 * bl;
                }
            }, 4096);
        }

        public static void tone_map_sdr (FloatImage img) {
            int n = (int) img.pixel_count ();
            Parallel.range (n, (a, b) => {
                for (int p = a; p < b; p++) {
                    size_t i = (size_t) p * 4;
                    float mx = float.max (img.data[i], float.max (img.data[i + 1], img.data[i + 2]));
                    if (mx <= 0.8f) continue;
                    float knee = 0.8f;
                    float over = mx - knee;
                    float mapped = knee + (1 - knee) * over / (over + (1 - knee));
                    float s = mapped / mx;
                    img.data[i] *= s;
                    img.data[i + 1] *= s;
                    img.data[i + 2] *= s;
                }
            }, 4096);
        }

        public static uint8[] encode_rgba8 (FloatImage img, bool premultiply_black) {
            Tone.ready ();
            int n = (int) img.pixel_count ();
            var out_data = new uint8[n * 4];
            Parallel.range (n, (a, b) => {
                for (int p = a; p < b; p++) {
                    size_t i = (size_t) p * 4;
                    float alpha = img.data[i + 3].clamp (0, 1);
                    for (int c = 0; c < 3; c++) {
                        float v = img.data[i + c];
                        if (premultiply_black) v *= alpha;
                        out_data[i + c] = (uint8) (Tone.encode (v.clamp (0, 1)) * 255 + 0.5f);
                    }
                    out_data[i + 3] = premultiply_black ? 255 : (uint8) (alpha * 255 + 0.5f);
                }
            }, 4096);
            return out_data;
        }

        public static uint16[] encode_rgba16 (FloatImage img, string transfer) {
            Tone.ready ();
            int n = (int) img.pixel_count ();
            var out_data = new uint16[n * 4];
            Parallel.range (n, (a, b) => {
                for (int p = a; p < b; p++) {
                    size_t i = (size_t) p * 4;
                    float alpha = img.data[i + 3].clamp (0, 1);
                    for (int c = 0; c < 3; c++) {
                        double v = double.max (0, img.data[i + c] * alpha);
                        double e;
                        if (transfer == "pq") e = Tone.nits_to_pq (v * Tone.REFERENCE_WHITE);
                        else if (transfer == "hlg") e = Tone.scene_to_hlg (v * Tone.REFERENCE_WHITE / 1000.0);
                        else e = Tone.encode ((float) v.clamp (0, 1));
                        out_data[i + c] = (uint16) (e.clamp (0, 1) * 65535 + 0.5);
                    }
                    out_data[i + 3] = 65535;
                }
            }, 2048);
            return out_data;
        }
    }

    public class CurveLut : Object {
        public float[] table = new float[1025];

        public CurveLut.identity () {
            for (int i = 0; i <= 1024; i++) table[i] = i / 1024.0f;
        }

        public CurveLut (double[] xs, double[] ys) {
            int n = xs.length;
            if (n < 2) {
                for (int i = 0; i <= 1024; i++) table[i] = i / 1024.0f;
                return;
            }
            var m = new double[n];
            var d = new double[n - 1];
            for (int i = 0; i < n - 1; i++) d[i] = (ys[i + 1] - ys[i]) / double.max (1e-9, xs[i + 1] - xs[i]);
            m[0] = d[0];
            m[n - 1] = d[n - 2];
            for (int i = 1; i < n - 1; i++) m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
            for (int i = 0; i < n - 1; i++) {
                if (d[i] == 0) {
                    m[i] = m[i + 1] = 0;
                    continue;
                }
                double a = m[i] / d[i], b = m[i + 1] / d[i];
                double s = a * a + b * b;
                if (s > 9) {
                    double t = 3 / Math.sqrt (s);
                    m[i] = t * a * d[i];
                    m[i + 1] = t * b * d[i];
                }
            }
            for (int k = 0; k <= 1024; k++) {
                double x = k / 1024.0;
                double y;
                if (x <= xs[0]) y = ys[0];
                else if (x >= xs[n - 1]) y = ys[n - 1];
                else {
                    int i = 0;
                    while (i < n - 2 && x > xs[i + 1]) i++;
                    double h = xs[i + 1] - xs[i];
                    double t = (x - xs[i]) / h;
                    double t2 = t * t, t3 = t2 * t;
                    y = (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h * m[i] + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h * m[i + 1];
                }
                table[k] = (float) y;
            }
        }

        public static CurveLut parse (string text, bool periodic = false) {
            var xs = new Gee.ArrayList<double?> ();
            var ys = new Gee.ArrayList<double?> ();
            foreach (var pair in text.split (";")) {
                var p = pair.strip ().split (",");
                if (p.length != 2) continue;
                xs.add (double.parse (p[0]).clamp (0, 1));
                ys.add (double.parse (p[1]));
            }
            if (xs.size < 2) return new CurveLut.identity ();
            var order = new Gee.ArrayList<int> ();
            for (int i = 0; i < xs.size; i++) order.add (i);
            order.sort ((a, b) => xs[a] < xs[b] ? -1 : (xs[a] > xs[b] ? 1 : 0));
            double[] x = {}, y = {};
            if (periodic && xs[order[0]] > 0) {
                x += xs[order[order.size - 1]] - 1;
                y += ys[order[order.size - 1]];
            }
            foreach (int i in order) {
                x += xs[i];
                y += ys[i];
            }
            if (periodic && xs[order[order.size - 1]] < 1) {
                x += xs[order[0]] + 1;
                y += ys[order[0]];
            }
            return new CurveLut (x, y);
        }

        public bool is_identity () {
            for (int i = 0; i <= 1024; i += 16) if ((table[i] - i / 1024.0f).abs () > 1e-4) return false;
            return true;
        }

        public inline float map (float v) {
            if (v <= 0) return table[0] + v;
            if (v >= 1) return table[1024] + (v - 1);
            float x = v * 1024;
            int i = (int) x;
            float f = x - i;
            return table[i] * (1 - f) + table[i + 1] * f;
        }

        public inline float map_periodic (float v) {
            v = v - Math.floorf (v);
            return map (v);
        }
    }

    public class Lut3D : Object {
        public int size;
        public float[] data;
        public float[]? shaper;
        public float domain_min = 0;
        public float domain_max = 1;
        public string title = "";

        public static Lut3D load (string path) throws Error {
            string text;
            FileUtils.get_contents (path, out text);
            if (path.down ().has_suffix (".3dl")) return parse_3dl (text);
            return parse_cube (text);
        }

        public static Lut3D parse_cube (string text) throws Error {
            var lut = new Lut3D ();
            int size1d = 0;
            var values = new Gee.ArrayList<float?> ();
            foreach (var raw in text.split ("\n")) {
                string line = raw.strip ();
                if (line == "" || line.has_prefix ("#")) continue;
                if (line.has_prefix ("TITLE")) {
                    lut.title = line.substring (5).strip ().replace ("\"", "");
                    continue;
                }
                if (line.has_prefix ("LUT_3D_SIZE")) {
                    lut.size = int.parse (line.substring (11).strip ());
                    continue;
                }
                if (line.has_prefix ("LUT_1D_SIZE")) {
                    size1d = int.parse (line.substring (11).strip ());
                    continue;
                }
                if (line.has_prefix ("DOMAIN_MIN")) {
                    lut.domain_min = (float) double.parse (line.substring (10).strip ().split (" ")[0]);
                    continue;
                }
                if (line.has_prefix ("DOMAIN_MAX")) {
                    lut.domain_max = (float) double.parse (line.substring (10).strip ().split (" ")[0]);
                    continue;
                }
                if (line.has_prefix ("LUT_")) continue;
                var parts = line.split_set (" \t");
                int count = 0;
                foreach (var p in parts) {
                    if (p == "") continue;
                    double v;
                    if (!double.try_parse (p, out v)) throw new IOError.INVALID_DATA (_("The LUT has an invalid value: %s").printf (p));
                    values.add ((float) v);
                    count++;
                }
                if (count != 3) throw new IOError.INVALID_DATA (_("Each LUT entry needs three values."));
            }
            if (lut.size == 0 && size1d > 1) {
                if (values.size != size1d * 3) throw new IOError.INVALID_DATA (_("The 1D LUT has the wrong number of entries."));
                lut.size = 2;
                lut.shaper = new float[size1d * 3];
                for (int i = 0; i < values.size; i++) lut.shaper[i] = values[i];
                lut.data = { 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0, 0, 0, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1 };
                return lut;
            }
            if (lut.size < 2 || lut.size > 256) throw new IOError.INVALID_DATA (_("The LUT size is not supported."));
            if (values.size != lut.size * lut.size * lut.size * 3) throw new IOError.INVALID_DATA (_("The LUT has the wrong number of entries."));
            lut.data = new float[values.size];
            for (int i = 0; i < values.size; i++) lut.data[i] = values[i];
            return lut;
        }

        public static Lut3D parse_3dl (string text) throws Error {
            var lut = new Lut3D ();
            var rows = new Gee.ArrayList<int?> ();
            int header = -1;
            int max_value = 0;
            foreach (var raw in text.split ("\n")) {
                string line = raw.strip ();
                if (line == "" || line.has_prefix ("#") || line.has_prefix ("<") || line.has_prefix ("Mesh") || line.has_prefix ("3DMESH")) continue;
                var parts = new Gee.ArrayList<string> ();
                foreach (var p in line.split_set (" \t")) if (p != "") parts.add (p);
                if (parts.size > 3 && header < 0) {
                    header = parts.size;
                    continue;
                }
                if (parts.size != 3) continue;
                foreach (var p in parts) {
                    int v = int.parse (p);
                    rows.add (v);
                    max_value = int.max (max_value, v);
                }
            }
            int count = rows.size / 3;
            int size = (int) Math.round (Math.cbrt (count));
            if (size < 2 || size * size * size != count) throw new IOError.INVALID_DATA (_("The 3DL table is not a cube."));
            float scale = max_value > 4095 ? 65535 : (max_value > 1023 ? 4095 : 1023);
            lut.size = size;
            lut.data = new float[count * 3];
            for (int r = 0; r < size; r++) {
                for (int g = 0; g < size; g++) {
                    for (int b = 0; b < size; b++) {
                        int src = ((r * size + g) * size + b) * 3;
                        int dst = ((b * size + g) * size + r) * 3;
                        lut.data[dst] = rows[src] / scale;
                        lut.data[dst + 1] = rows[src + 1] / scale;
                        lut.data[dst + 2] = rows[src + 2] / scale;
                    }
                }
            }
            return lut;
        }

        public string to_cube () {
            var sb = new StringBuilder ();
            if (title != "") sb.append ("TITLE \"%s\"\n".printf (title));
            sb.append ("LUT_3D_SIZE %d\n".printf (size));
            for (int i = 0; i < size * size * size; i++)
                sb.append ("%.6f %.6f %.6f\n".printf (data[i * 3], data[i * 3 + 1], data[i * 3 + 2]));
            return sb.str;
        }

        inline float shape (float v, int c) {
            if (shaper == null) return v;
            int n = shaper.length / 3;
            float x = v.clamp (0, 1) * (n - 1);
            int i = int.min ((int) x, n - 2);
            float f = x - i;
            return shaper[i * 3 + c] * (1 - f) + shaper[(i + 1) * 3 + c] * f;
        }

        public void apply (float r, float g, float b, out float or, out float og, out float ob) {
            float span = domain_max - domain_min;
            r = shape (((r - domain_min) / span).clamp (0, 1), 0);
            g = shape (((g - domain_min) / span).clamp (0, 1), 1);
            b = shape (((b - domain_min) / span).clamp (0, 1), 2);
            if (shaper != null) {
                or = r; og = g; ob = b;
                return;
            }
            float n = size - 1;
            float fr = r * n, fg = g * n, fb = b * n;
            int r0 = int.min ((int) fr, size - 2), g0 = int.min ((int) fg, size - 2), b0 = int.min ((int) fb, size - 2);
            float dr = fr - r0, dg = fg - g0, db = fb - b0;
            or = trilinear (r0, g0, b0, dr, dg, db, 0);
            og = trilinear (r0, g0, b0, dr, dg, db, 1);
            ob = trilinear (r0, g0, b0, dr, dg, db, 2);
        }

        inline float trilinear (int r0, int g0, int b0, float dr, float dg, float db, int c) {
            float c000 = at (r0, g0, b0, c), c100 = at (r0 + 1, g0, b0, c), c010 = at (r0, g0 + 1, b0, c), c110 = at (r0 + 1, g0 + 1, b0, c);
            float c001 = at (r0, g0, b0 + 1, c), c101 = at (r0 + 1, g0, b0 + 1, c), c011 = at (r0, g0 + 1, b0 + 1, c), c111 = at (r0 + 1, g0 + 1, b0 + 1, c);
            float c00 = c000 + (c100 - c000) * dr, c10 = c010 + (c110 - c010) * dr;
            float c01 = c001 + (c101 - c001) * dr, c11 = c011 + (c111 - c011) * dr;
            float c0 = c00 + (c10 - c00) * dg, c1 = c01 + (c11 - c01) * dg;
            return c0 + (c1 - c0) * db;
        }

        inline float at (int r, int g, int b, int c) {
            return data[((b * size + g) * size + r) * 3 + c];
        }
    }

    namespace Grade {
        public void blackbody (double kelvin, out double r, out double g, out double b) {
            double t = kelvin.clamp (1000, 40000) / 100;
            if (t <= 66) {
                r = 255;
                g = 99.4708025861 * Math.log (t) - 161.1195681661;
                b = t <= 19 ? 0 : 138.5177312231 * Math.log (t - 10) - 305.0447927307;
            } else {
                r = 329.698727446 * Math.pow (t - 60, -0.1332047592);
                g = 288.1221695283 * Math.pow (t - 60, -0.0755148492);
                b = 255;
            }
            r = Tone.decode ((float) (r.clamp (0, 255) / 255));
            g = Tone.decode ((float) (g.clamp (0, 255) / 255));
            b = Tone.decode ((float) (b.clamp (0, 255) / 255));
        }

        public void white_balance_gains (double temperature, double tint, out float gr, out float gg, out float gb) {
            double kelvin = 6500 * Math.pow (2, -temperature / 100.0);
            double r0, g0, b0, r1, g1, b1;
            blackbody (6500, out r0, out g0, out b0);
            blackbody (kelvin, out r1, out g1, out b1);
            double rr = r0 / double.max (1e-6, r1), rg = g0 / double.max (1e-6, g1), rb = b0 / double.max (1e-6, b1);
            double l = 0.2126 * rr + 0.7152 * rg + 0.0722 * rb;
            rr /= l; rg /= l; rb /= l;
            double tg = Math.pow (2, -tint / 200.0);
            gr = (float) rr;
            gg = (float) (rg * tg);
            gb = (float) rb;
        }

        public inline float luma (float r, float g, float b) {
            return 0.2126f * r + 0.7152f * g + 0.0722f * b;
        }

        public void rgb_to_hsv (float r, float g, float b, out float h, out float s, out float v) {
            float mx = float.max (r, float.max (g, b)), mn = float.min (r, float.min (g, b));
            v = mx;
            float d = mx - mn;
            s = mx > 1e-6f ? d / mx : 0;
            if (d <= 1e-6f) {
                h = 0;
                return;
            }
            if (mx == r) h = ((g - b) / d) / 6;
            else if (mx == g) h = (2 + (b - r) / d) / 6;
            else h = (4 + (r - g) / d) / 6;
            if (h < 0) h += 1;
        }

        public void hsv_to_rgb (float h, float s, float v, out float r, out float g, out float b) {
            h = (h - Math.floorf (h)) * 6;
            int i = (int) h;
            float f = h - i, p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f));
            switch (i % 6) {
                case 0: r = v; g = t; b = p; break;
                case 1: r = q; g = v; b = p; break;
                case 2: r = p; g = v; b = t; break;
                case 3: r = p; g = q; b = v; break;
                case 4: r = t; g = p; b = v; break;
                default: r = v; g = p; b = q; break;
            }
        }
    }
}
