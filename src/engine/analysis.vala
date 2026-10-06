using Singularity.Imaging;
using Singularity.Audio;

namespace Singularity.Apps.Montage {
    public delegate bool Progress (double fraction);

    namespace Analysis {
        float[] gray (Frame f) {
            var g = new float[f.width * f.height];
            for (int i = 0; i < f.width * f.height; i++) g[i] = (0.299f * f.bytes[i * 4] + 0.587f * f.bytes[i * 4 + 1] + 0.114f * f.bytes[i * 4 + 2]) / 255.0f;
            return g;
        }

        public Gee.ArrayList<int64?> detect_scenes (string uri, int64 start, int64 end, double sensitivity, Progress? progress = null) throws Error {
            var cuts = new Gee.ArrayList<int64?> ();
            var m = Probe.probe (uri);
            if (!m.has_video) return cuts;
            int w = 64, h = int.max (2, (int) (64.0 * m.height / int.max (1, m.width))) & ~1;
            var reader = new VideoReader (uri, w, h);
            int64 frame = Tc.frame_duration (m.fps_n, m.fps_d);
            int64 stop = end > 0 ? int64.min (end, m.duration) : m.duration;
            float[]? prev_hist = null;
            float[]? prev_gray = null;
            var scores = new Gee.ArrayList<double?> ();
            var times = new Gee.ArrayList<int64?> ();
            for (int64 t = start; t < stop; t += frame) {
                var f = reader.frame_at (t);
                if (f == null) break;
                var hist = new float[48];
                for (int i = 0; i < w * h; i++) {
                    hist[f.bytes[i * 4] >> 4]++;
                    hist[16 + (f.bytes[i * 4 + 1] >> 4)]++;
                    hist[32 + (f.bytes[i * 4 + 2] >> 4)]++;
                }
                for (int i = 0; i < 48; i++) hist[i] /= w * h;
                var g = gray (f);
                if (prev_hist != null) {
                    double hd = 0, pd = 0;
                    for (int i = 0; i < 48; i++) hd += (hist[i] - prev_hist[i]).abs ();
                    for (int i = 0; i < g.length; i++) pd += (g[i] - prev_gray[i]).abs ();
                    pd /= g.length;
                    scores.add (hd / 6 + pd);
                    times.add (f.pts);
                }
                prev_hist = hist;
                prev_gray = g;
                if (progress != null && !progress ((double) (t - start) / double.max (1, stop - start))) break;
            }
            reader.close ();
            double threshold_base = 0.12 + (1 - sensitivity.clamp (0, 1)) * 0.35;
            int64 min_gap = (int64) (0.5 * Tc.SECOND);
            int64 last = start;
            for (int i = 0; i < scores.size; i++) {
                double local = 0;
                int n = 0;
                for (int k = int.max (0, i - 12); k < int.min (scores.size, i + 12); k++) {
                    if (k == i) continue;
                    local += scores[k];
                    n++;
                }
                local = n > 0 ? local / n : 0;
                if (scores[i] > threshold_base && scores[i] > local * 3 && times[i] - last >= min_gap) {
                    cuts.add (times[i]);
                    last = times[i];
                }
            }
            return cuts;
        }

        public float[] envelope (string uri, int64 from, int64 length, int rate_hz) throws Error {
            var reader = new AudioReader (uri, 48000);
            int step = 48000 / rate_hz;
            int count = (int) (length * rate_hz / Tc.SECOND);
            var env = new float[count];
            var buf = new float[step * 2 * 100];
            int64 start = from * 48000 / Tc.SECOND;
            for (int i = 0; i < count; i += 100) {
                int n = int.min (100, count - i);
                reader.read (start + (int64) i * step, n * step, buf);
                for (int k = 0; k < n; k++) {
                    double sum = 0;
                    for (int s = 0; s < step; s++) {
                        float v = (buf[(k * step + s) * 2] + buf[(k * step + s) * 2 + 1]) / 2;
                        sum += v * v;
                    }
                    env[i + k] = (float) Math.sqrt (sum / step);
                }
            }
            reader.close ();
            double mean = 0;
            foreach (var v in env) mean += v;
            mean /= int.max (1, env.length);
            for (int i = 0; i < env.length; i++) {
                float d = env[i] - (float) mean;
                env[i] = d;
            }
            return env;
        }

        public int64 audio_offset (string reference, string other, int64 max_offset, out double confidence) throws Error {
            int rate = 200;
            int64 length = 60 * Tc.SECOND;
            var a = envelope (reference, 0, length, rate);
            var b = envelope (other, 0, length, rate);
            int max_lag = (int) (max_offset * rate / Tc.SECOND);
            int n = 1;
            while (n < a.length + b.length) n <<= 1;
            var ar = new double[n];
            var ai = new double[n];
            var br = new double[n];
            var bi = new double[n];
            for (int i = 0; i < a.length; i++) ar[i] = a[i];
            for (int i = 0; i < b.length; i++) br[i] = b[i];
            Fft.transform (ar, ai, false);
            Fft.transform (br, bi, false);
            var cr = new double[n];
            var ci = new double[n];
            for (int i = 0; i < n; i++) {
                cr[i] = ar[i] * br[i] + ai[i] * bi[i];
                ci[i] = ai[i] * br[i] - ar[i] * bi[i];
            }
            Fft.transform (cr, ci, true);
            double best = -double.MAX, second = -double.MAX, energy = 0;
            int best_lag = 0;
            for (int lag = -max_lag; lag <= max_lag; lag++) {
                double v = cr[(lag + n) % n];
                energy += v.abs ();
                if (v > best) {
                    second = best;
                    best = v;
                    best_lag = lag;
                } else if (v > second && (lag - best_lag).abs () > 10) {
                    second = v;
                }
            }
            double norm_a = 0, norm_b = 0;
            foreach (var v in a) norm_a += v * v;
            foreach (var v in b) norm_b += v * v;
            confidence = best / double.max (1e-9, Math.sqrt (norm_a * norm_b));
            return (int64) best_lag * Tc.SECOND / rate;
        }

        public string stabilize (string uri, int64 start, int64 end, double smoothness, Progress? progress = null) throws Error {
            var m = Probe.probe (uri);
            int w = 320, h = int.max (2, (int) (320.0 * m.height / int.max (1, m.width))) & ~1;
            var reader = new VideoReader (uri, w, h);
            int64 frame = Tc.frame_duration (m.fps_n, m.fps_d);
            int64 stop = end > 0 ? int64.min (end, m.duration) : m.duration;
            var xs = new Gee.ArrayList<double?> ();
            var ys = new Gee.ArrayList<double?> ();
            var as = new Gee.ArrayList<double?> ();
            var ts = new Gee.ArrayList<int64?> ();
            float[]? prev = null;
            double cx = 0, cy = 0, ca = 0;
            for (int64 t = start; t < stop; t += frame) {
                var f = reader.frame_at (t);
                if (f == null) break;
                var g = gray (f);
                if (prev != null) {
                    double dx, dy, da;
                    motion (prev, g, w, h, out dx, out dy, out da);
                    cx += dx;
                    cy += dy;
                    ca += da;
                }
                xs.add (cx);
                ys.add (cy);
                as.add (ca);
                ts.add (f.pts);
                prev = g;
                if (progress != null && !progress ((double) (t - start) / double.max (1, stop - start))) break;
            }
            reader.close ();
            int radius = int.max (1, (int) (smoothness.clamp (0.05, 1) * 30));
            var sb = new StringBuilder ();
            sb.append ("w=%d".printf (w));
            double max_shift = 0;
            for (int i = 0; i < xs.size; i++) {
                double sx = 0, sy = 0, sa = 0, wsum = 0;
                for (int k = int.max (0, i - radius); k <= int.min (xs.size - 1, i + radius); k++) {
                    double wk = Math.exp (-((double) (k - i) * (k - i)) / (2.0 * radius * radius / 4));
                    sx += xs[k] * wk;
                    sy += ys[k] * wk;
                    sa += as[k] * wk;
                    wsum += wk;
                }
                double fx = sx / wsum - xs[i], fy = sy / wsum - ys[i], fa = sa / wsum - as[i];
                max_shift = double.max (max_shift, double.max ((fx * 2 / w).abs (), (fy * 2 / h).abs ()) + fa.abs () * 0.5);
                int64 stamp = ts[i];
                sb.append (";%lld:%.3f,%.3f,%.5f".printf (stamp, fx, fy, fa));
            }
            double zoom = 1 + double.min (0.3, max_shift * 1.05);
            return sb.str + ";z=%.4f".printf (zoom);
        }

        void motion (float[] a, float[] b, int w, int h, out double dx, out double dy, out double da) {
            int block = 16, search = 16;
            var px = new Gee.ArrayList<double?> ();
            var py = new Gee.ArrayList<double?> ();
            var vx = new Gee.ArrayList<double?> ();
            var vy = new Gee.ArrayList<double?> ();
            for (int by = search + block; by < h - search - block * 2; by += block * 2) {
                for (int bx = search + block; bx < w - search - block * 2; bx += block * 2) {
                    double var_sum = 0, mean = 0;
                    for (int y = 0; y < block; y++) for (int x = 0; x < block; x++) mean += a[(by + y) * w + bx + x];
                    mean /= block * block;
                    for (int y = 0; y < block; y++) for (int x = 0; x < block; x++) {
                        double d = a[(by + y) * w + bx + x] - mean;
                        var_sum += d * d;
                    }
                    if (var_sum / (block * block) < 0.0008) continue;
                    double best = double.MAX;
                    int bdx = 0, bdy = 0;
                    for (int sy = -search; sy <= search; sy++) {
                        for (int sx = -search; sx <= search; sx++) {
                            double sad = 0;
                            for (int y = 0; y < block; y += 2) {
                                for (int x = 0; x < block; x += 2) sad += (a[(by + y) * w + bx + x] - b[(by + y + sy) * w + bx + x + sx]).abs ();
                                if (sad >= best) break;
                            }
                            if (sad < best) {
                                best = sad;
                                bdx = sx;
                                bdy = sy;
                            }
                        }
                    }
                    px.add (bx + block / 2.0 - w / 2.0);
                    py.add (by + block / 2.0 - h / 2.0);
                    vx.add (bdx);
                    vy.add (bdy);
                }
            }
            dx = dy = da = 0;
            if (vx.size == 0) return;
            var sx_sorted = new Gee.ArrayList<double?> ();
            var sy_sorted = new Gee.ArrayList<double?> ();
            sx_sorted.add_all (vx);
            sy_sorted.add_all (vy);
            sx_sorted.sort ((p, q) => p < q ? -1 : (p > q ? 1 : 0));
            sy_sorted.sort ((p, q) => p < q ? -1 : (p > q ? 1 : 0));
            dx = sx_sorted[sx_sorted.size / 2];
            dy = sy_sorted[sy_sorted.size / 2];
            double num = 0, den = 0;
            for (int i = 0; i < vx.size; i++) {
                if ((vx[i] - dx).abs () > 3 || (vy[i] - dy).abs () > 3) continue;
                double rx = vx[i] - dx, ry = vy[i] - dy;
                num += px[i] * ry - py[i] * rx;
                den += px[i] * px[i] + py[i] * py[i];
            }
            da = den > 0 ? num / den : 0;
        }

        public void track_point (string uri, int64 start, int64 end, double x, double y, int size, int width, int height,
                                 Gee.ArrayList<int64?> times, Gee.ArrayList<double?> xs, Gee.ArrayList<double?> ys, Progress? progress = null) throws Error {
            var m = Probe.probe (uri);
            int w = int.min (640, m.width) & ~1;
            int h = int.max (2, (int) ((double) w * m.height / int.max (1, m.width))) & ~1;
            double scale = (double) w / width;
            var reader = new VideoReader (uri, w, h);
            int64 frame = Tc.frame_duration (m.fps_n, m.fps_d);
            int half = int.max (4, (int) (size * scale / 2));
            int search = half;
            double cx = x * scale, cy = y * scale;
            float[]? template = null;
            int64 stop = end > 0 ? int64.min (end, m.duration) : m.duration;
            for (int64 t = start; t < stop; t += frame) {
                var f = reader.frame_at (t);
                if (f == null) break;
                var g = gray (f);
                if (template == null) {
                    template = new float[(half * 2) * (half * 2)];
                    for (int yy = 0; yy < half * 2; yy++) for (int xx = 0; xx < half * 2; xx++) {
                        int sx = ((int) cx - half + xx).clamp (0, w - 1), sy = ((int) cy - half + yy).clamp (0, h - 1);
                        template[yy * half * 2 + xx] = g[sy * w + sx];
                    }
                } else {
                    double best = double.MAX;
                    int bx = 0, by = 0;
                    for (int dy = -search; dy <= search; dy++) {
                        for (int dx = -search; dx <= search; dx++) {
                            double sad = 0;
                            for (int yy = 0; yy < half * 2; yy += 2) {
                                for (int xx = 0; xx < half * 2; xx += 2) {
                                    int sx = ((int) cx + dx - half + xx).clamp (0, w - 1), sy = ((int) cy + dy - half + yy).clamp (0, h - 1);
                                    sad += (g[sy * w + sx] - template[yy * half * 2 + xx]).abs ();
                                }
                                if (sad >= best) break;
                            }
                            if (sad < best) {
                                best = sad;
                                bx = dx;
                                by = dy;
                            }
                        }
                    }
                    cx += bx;
                    cy += by;
                    for (int yy = 0; yy < half * 2; yy++) for (int xx = 0; xx < half * 2; xx++) {
                        int sx = ((int) cx - half + xx).clamp (0, w - 1), sy = ((int) cy - half + yy).clamp (0, h - 1);
                        template[yy * half * 2 + xx] = template[yy * half * 2 + xx] * 0.7f + g[sy * w + sx] * 0.3f;
                    }
                }
                times.add (f.pts);
                xs.add (cx / scale);
                ys.add (cy / scale);
                if (progress != null && !progress ((double) (t - start) / double.max (1, stop - start))) break;
            }
            reader.close ();
        }

        public void color_stats (FloatImage img, double[] mean, double[] std) {
            int n = (int) img.pixel_count ();
            for (int c = 0; c < 3; c++) {
                double sum = 0, sq = 0;
                int count = 0;
                for (int p = 0; p < n; p += 3) {
                    double v = Tone.encode (img.data[p * 4 + c].clamp (0, 1));
                    sum += v;
                    sq += v * v;
                    count++;
                }
                mean[c] = sum / count;
                std[c] = Math.sqrt (double.max (1e-8, sq / count - mean[c] * mean[c]));
            }
        }

        public Effect match_color (FloatImage source, FloatImage reference, string label) {
            var ms = new double[3];
            var ss = new double[3];
            var mr = new double[3];
            var sr = new double[3];
            color_stats (source, ms, ss);
            color_stats (reference, mr, sr);
            var e = Catalog.find ("color.match").create ();
            string[] ch = { "r", "g", "b" };
            for (int c = 0; c < 3; c++) {
                double gain = (sr[c] / ss[c]).clamp (0.25, 4);
                double offset = mr[c] - gain * ms[c];
                e.params.values["gain-" + ch[c]].value = gain;
                e.params.values["offset-" + ch[c]].value = offset.clamp (-1, 1);
            }
            e.params.texts["reference"] = label;
            return e;
        }

        public class DuckPlan : Object {
            public int64[] times;
            public Gee.ArrayList<double?> gains;
            public Gee.ArrayList<string> music = new Gee.ArrayList<string> ();
        }

        public DuckPlan plan_duck (Project snapshot, string sequence_id, double amount_db, Progress? progress = null) throws Error {
            var seq = snapshot.find_sequence (sequence_id);
            var plan = new DuckPlan ();
            int voices = 0;
            foreach (var c in seq.clips) {
                var t = seq.track (c.track);
                if (t == null || t.kind != TrackKind.AUDIO) continue;
                string role = c.role != "" ? c.role : t.role;
                if (role == "dialogue") voices++;
                else {
                    if (role == "music") plan.music.add (c.id);
                    c.enabled = false;
                }
            }
            if (voices == 0 || plan.music.size == 0) throw new IOError.INVALID_ARGUMENT (_("Set the role of clips or tracks to Dialogue and Music first."));
            var mixer = new AudioMixer (snapshot, seq, 48000);
            int64 total = mixer.to_sample (seq.duration);
            var all = new float[total * 2];
            int block = 4800;
            var buf = new float[block * 2];
            for (int64 i = 0; i < total; i += block) {
                int n = (int) int64.min (block, total - i);
                mixer.render (i, n, buf);
                Memory.copy ((uint8*) all + i * 8, buf, n * 8);
                if (progress != null) progress ((double) i / total);
            }
            mixer.close ();
            var ducker = new Ducker ();
            ducker.amount_db = amount_db;
            plan.gains = ducker.envelope (all, (int) total, 2, 48000, 100000000, out plan.times);
            return plan;
        }

        public int apply_duck (Project p, Sequence s, DuckPlan plan) {
            p.checkpoint (_("Automatic Ducking"));
            int keys = 0;
            foreach (var id in plan.music) {
                var c = s.clip (id);
                if (c == null) continue;
                var vol = c.params.ensure ("volume", 0);
                double base_db = vol.animated ? 0 : vol.value;
                vol.keys.clear ();
                double last = double.MAX;
                int64 skipped = -1;
                for (int i = 0; i < plan.times.length; i++) {
                    int64 t = plan.times[i];
                    if (t < c.position || t >= c.end) continue;
                    double g = plan.gains[i] + base_db;
                    bool final_key = i + 1 >= plan.times.length || plan.times[i + 1] >= c.end;
                    if ((g - last).abs () < 0.75 && !final_key) {
                        skipped = t;
                        continue;
                    }
                    if (skipped >= 0 && last != double.MAX) {
                        vol.set_key (c.key_time (skipped), last, Singularity.Keyframes.Interpolation.LINEAR);
                        keys++;
                    }
                    skipped = -1;
                    vol.set_key (c.key_time (t), g, Singularity.Keyframes.Interpolation.LINEAR);
                    last = g;
                    keys++;
                }
                vol.value = base_db;
            }
            p.commit ();
            return keys;
        }

        public double clip_loudness (Project p, Sequence s, Clip c) throws Error {
            var snapshot = p.clone ();
            var seq = snapshot.find_sequence (s.id);
            foreach (var o in seq.clips) if (o.id != c.id) o.enabled = false;
            foreach (var t in seq.tracks) {
                t.volume.keys.clear ();
                t.volume.value = 0;
                t.muted = false;
                t.solo = false;
            }
            var clip = seq.clip (c.id);
            clip.params.ensure ("volume", 0).keys.clear ();
            clip.params.values["volume"].value = 0;
            var mixer = new AudioMixer (snapshot, seq, 48000);
            mixer.meter = new LoudnessMeter (48000, 2);
            int64 s0 = mixer.to_sample (c.position), s1 = mixer.to_sample (c.end);
            var buf = new float[4096 * 2];
            for (int64 i = s0; i < s1; i += 4096) mixer.render (i, (int) int64.min (4096, s1 - i), buf);
            mixer.close ();
            return mixer.meter.integrated;
        }
    }
}
