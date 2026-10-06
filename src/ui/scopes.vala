using Gtk;
using Singularity.Imaging;

namespace Singularity.Apps.Montage {
    public class ScopeData : Object {
        public int width = 256;
        public int height = 128;
        public float[] waveform;
        public float[] parade;
        public float[] vector;
        public float[] histogram;

        public static ScopeData compute (FloatImage img) {
            var d = new ScopeData ();
            int w = d.width, h = d.height;
            d.waveform = new float[w * h];
            d.parade = new float[w * h * 3];
            d.vector = new float[256 * 256];
            d.histogram = new float[256 * 3];
            int step = int.max (1, (int) Math.sqrt ((double) img.pixel_count () / 60000));
            for (int y = 0; y < img.height; y += step) {
                for (int x = 0; x < img.width; x += step) {
                    size_t i = img.offset (x, y);
                    float a = img.data[i + 3];
                    float r = Tone.encode ((img.data[i] * a).clamp (0, 1)), g = Tone.encode ((img.data[i + 1] * a).clamp (0, 1)), b = Tone.encode ((img.data[i + 2] * a).clamp (0, 1));
                    float l = 0.2126f * r + 0.7152f * g + 0.0722f * b;
                    int col = x * w / img.width;
                    d.waveform[(int) ((1 - l) * (h - 1)) * w + col] += 1;
                    int pc = x * (w / 3) / img.width;
                    d.parade[(int) ((1 - r) * (h - 1)) * w * 3 + pc] += 1;
                    d.parade[(int) ((1 - g) * (h - 1)) * w * 3 + w / 3 + pc] += 1;
                    d.parade[(int) ((1 - b) * (h - 1)) * w * 3 + 2 * (w / 3) + pc] += 1;
                    float cb = -0.1146f * r - 0.3854f * g + 0.5f * b;
                    float cr = 0.5f * r - 0.4542f * g - 0.0458f * b;
                    int vx = (int) ((cb + 0.5f) * 255), vy = (int) ((0.5f - cr) * 255);
                    d.vector[vy.clamp (0, 255) * 256 + vx.clamp (0, 255)] += 1;
                    d.histogram[(int) (r * 255)] += 1;
                    d.histogram[256 + (int) (g * 255)] += 1;
                    d.histogram[512 + (int) (b * 255)] += 1;
                }
            }
            return d;
        }
    }

    public class Scopes : DrawingArea {
        public string mode = "waveform";
        ScopeData? data;

        public Scopes () {
            set_size_request (300, 180);
            set_draw_func (draw);
            update_property (AccessibleProperty.LABEL, _("Video scopes"), -1);
        }

        public void update (FloatImage img) {
            data = ScopeData.compute (img);
            queue_draw ();
        }

        void plot (Cairo.Context cr, float[] values, int w, int h, double x0, double y0, double dw, double dh, double r, double g, double b) {
            float max = 1;
            foreach (var v in values) max = float.max (max, v);
            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            unowned uint8[] px = surface.get_data ();
            int stride = surface.get_stride ();
            for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
                float v = values[y * w + x];
                if (v <= 0) continue;
                double k = Math.sqrt (v / max);
                int o = y * stride + x * 4;
                double a = double.min (1, 0.25 + k);
                px[o + 3] = (uint8) (a * 255);
                px[o + 2] = (uint8) (r * a * 255);
                px[o + 1] = (uint8) (g * a * 255);
                px[o] = (uint8) (b * a * 255);
            }
            surface.mark_dirty ();
            cr.save ();
            cr.translate (x0, y0);
            cr.scale (dw / w, dh / h);
            cr.set_source_surface (surface, 0, 0);
            cr.get_source ().set_filter (Cairo.Filter.BILINEAR);
            cr.paint ();
            cr.restore ();
        }

        void draw (DrawingArea a, Cairo.Context cr, int width, int height) {
            cr.set_source_rgb (0.06, 0.06, 0.07);
            cr.paint ();
            cr.set_source_rgba (1, 1, 1, 0.15);
            cr.set_line_width (1);
            if (data == null) return;
            switch (mode) {
                case "parade":
                    plot (cr, data.parade, data.width, data.height, 0, 0, width, height, 1, 1, 1);
                    for (int c = 0; c < 3; c++) {
                        cr.set_source_rgba (c == 0 ? 1 : 0.3, c == 1 ? 1 : 0.3, c == 2 ? 1 : 0.3, 0.25);
                        cr.rectangle (c * width / 3.0, 0, width / 3.0, height);
                        cr.stroke ();
                    }
                    break;
                case "vectorscope": {
                    double size = double.min (width, height);
                    double ox = (width - size) / 2, oy = (height - size) / 2;
                    cr.set_source_rgba (1, 1, 1, 0.2);
                    cr.arc (width / 2.0, height / 2.0, size / 2 - 2, 0, 2 * Math.PI);
                    cr.stroke ();
                    double[,] targets = { { 0.75, 0, 0 }, { 0, 0.75, 0 }, { 0, 0, 0.75 }, { 0.75, 0.75, 0 }, { 0, 0.75, 0.75 }, { 0.75, 0, 0.75 } };
                    for (int i = 0; i < 6; i++) {
                        double r = targets[i, 0], g = targets[i, 1], b = targets[i, 2];
                        double cb = -0.1146 * r - 0.3854 * g + 0.5 * b, crr = 0.5 * r - 0.4542 * g - 0.0458 * b;
                        cr.rectangle (ox + (cb + 0.5) * size - 4, oy + (0.5 - crr) * size - 4, 8, 8);
                        cr.stroke ();
                    }
                    cr.move_to (width / 2.0, height / 2.0);
                    cr.line_to (ox + (-0.1146 * 0.85 - 0.3854 * 0.6 + 0.5 * 0.45 + 0.5) * size * 1.0, oy + (0.5 - (0.5 * 0.85 - 0.4542 * 0.6 - 0.0458 * 0.45)) * size);
                    cr.stroke ();
                    plot (cr, data.vector, 256, 256, ox, oy, size, size, 0.6, 1, 0.7);
                    break;
                }
                case "histogram": {
                    float max = 1;
                    foreach (var v in data.histogram) max = float.max (max, v);
                    for (int c = 0; c < 3; c++) {
                        cr.set_source_rgba (c == 0 ? 1 : 0.2, c == 1 ? 1 : 0.2, c == 2 ? 1 : 0.2, 0.5);
                        cr.move_to (0, height);
                        for (int i = 0; i < 256; i++) cr.line_to (i * width / 255.0, height - Math.sqrt (data.histogram[c * 256 + i] / max) * height);
                        cr.line_to (width, height);
                        cr.close_path ();
                        cr.fill ();
                    }
                    break;
                }
                default:
                    for (int i = 0; i <= 4; i++) {
                        cr.move_to (0, i * height / 4.0);
                        cr.line_to (width, i * height / 4.0);
                    }
                    cr.stroke ();
                    plot (cr, data.waveform, data.width, data.height, 0, 0, width, height, 0.6, 1, 0.7);
                    break;
            }
        }
    }
}
