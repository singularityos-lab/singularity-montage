using Singularity.Imaging;
using Singularity.Keyframes;

namespace Singularity.Apps.Montage {
    public class CompositionLayer : Object {
        public string type = "rect";
        public string name = "";
        public int64 start;
        public int64 end = int64.MAX;
        public Gee.HashMap<string, AnimatedValue> props = new Gee.HashMap<string, AnimatedValue> ();
        public string fill = "#ffffffff";
        public string stroke = "";
        public double stroke_width;
        public string text = "";
        public string font = "Sans 48";
        public string src = "";
        public string path = "";

        public double get_prop (string name, int64 t, double fallback) {
            var v = props[name];
            return v != null ? v.at (t) : fallback;
        }
    }

    public class Composition : Object {
        public int width = 1920;
        public int height = 1080;
        public int64 duration = 5000000000;
        public string base_dir = "";
        public Gee.ArrayList<CompositionLayer> layers = new Gee.ArrayList<CompositionLayer> ();
        Gee.HashMap<string, Cairo.ImageSurface> images = new Gee.HashMap<string, Cairo.ImageSurface> ();

        public static Composition load (File file) throws Error {
            uint8[] data;
            string name = file.get_basename () ?? "";
            if (name.has_suffix (".keyframe")) {
                var archive = ZipArchive.read (file);
                data = archive.get ("composition.json");
                if (data == null) throw new IOError.INVALID_DATA (_("The Keyframe file has no composition."));
            } else {
                file.load_contents (null, out data, null);
            }
            var c = parse ((string) data);
            var parent = file.get_parent ();
            c.base_dir = parent != null ? (parent.get_path () ?? "") : "";
            return c;
        }

        public static Composition parse (string text) throws Error {
            var o = Js.parse (text);
            string format = Js.str (o, "format");
            if (format != "keyframe-composition" && format != "montage-composition") throw new IOError.INVALID_DATA (_("This is not a composition."));
            var c = new Composition ();
            c.width = (int) Js.integer (o, "width", 1920).clamp (16, 16384);
            c.height = (int) Js.integer (o, "height", 1080).clamp (16, 16384);
            c.duration = Js.integer (o, "duration", 5000000000);
            foreach (var lo in Js.objects (o, "layers")) {
                var l = new CompositionLayer ();
                l.type = Js.str (lo, "type", "rect");
                l.name = Js.str (lo, "name");
                l.start = Js.integer (lo, "start", 0);
                l.end = Js.integer (lo, "end", int64.MAX);
                l.fill = Js.str (lo, "fill", "#ffffffff");
                l.stroke = Js.str (lo, "stroke");
                l.stroke_width = Js.num (lo, "stroke-width");
                l.text = Js.str (lo, "text");
                l.font = Js.str (lo, "font", "Sans 48");
                l.src = Js.str (lo, "src");
                l.path = Js.str (lo, "path");
                var props = Js.obj (lo, "props");
                if (props != null) foreach (var k in props.get_members ()) l.props[k] = AnimatedValue.from_json (props.get_member (k));
                c.layers.add (l);
            }
            return c;
        }

        public FloatImage render (int64 t, int w, int h) {
            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context (surface);
            cr.scale ((double) w / width, (double) h / height);
            foreach (var l in layers) {
                if (t < l.start || t >= l.end) continue;
                int64 lt = t - l.start;
                double opacity = l.get_prop ("opacity", lt, 100) / 100;
                if (opacity <= 0) continue;
                cr.save ();
                double x = l.get_prop ("x", lt, width / 2.0), y = l.get_prop ("y", lt, height / 2.0);
                double lw = l.get_prop ("width", lt, 200), lh = l.get_prop ("height", lt, 200);
                double scale = l.get_prop ("scale", lt, 100) / 100;
                cr.translate (x, y);
                cr.rotate (l.get_prop ("rotation", lt, 0) * Math.PI / 180);
                cr.scale (scale, scale);
                cr.push_group ();
                switch (l.type) {
                    case "ellipse":
                        cr.save ();
                        cr.scale (lw / 2, lh / 2);
                        cr.arc (0, 0, 1, 0, 2 * Math.PI);
                        cr.restore ();
                        paint_shape (cr, l);
                        break;
                    case "text": {
                        var layout = Pango.cairo_create_layout (cr);
                        layout.set_font_description (Pango.FontDescription.from_string (l.font));
                        layout.set_text (l.text, -1);
                        int tw, th;
                        layout.get_pixel_size (out tw, out th);
                        cr.move_to (-tw / 2.0, -th / 2.0);
                        Pango.cairo_layout_path (cr, layout);
                        paint_shape (cr, l);
                        break;
                    }
                    case "image": {
                        var img = image (l.src);
                        if (img != null) {
                            cr.scale (lw / img.get_width (), lh / img.get_height ());
                            cr.set_source_surface (img, -img.get_width () / 2.0, -img.get_height () / 2.0);
                            cr.paint ();
                        }
                        break;
                    }
                    case "path": {
                        bool first = true;
                        foreach (var pair in l.path.split (";")) {
                            var p = pair.split (",");
                            if (p.length < 2) continue;
                            if (first) cr.move_to (double.parse (p[0]), double.parse (p[1]));
                            else cr.line_to (double.parse (p[0]), double.parse (p[1]));
                            first = false;
                        }
                        if (l.fill != "") cr.close_path ();
                        paint_shape (cr, l);
                        break;
                    }
                    default:
                        double radius = l.get_prop ("radius", lt, 0);
                        if (radius > 0) {
                            double r = double.min (radius, double.min (lw, lh) / 2);
                            cr.new_path ();
                            cr.arc (lw / 2 - r, -lh / 2 + r, r, -Math.PI / 2, 0);
                            cr.arc (lw / 2 - r, lh / 2 - r, r, 0, Math.PI / 2);
                            cr.arc (-lw / 2 + r, lh / 2 - r, r, Math.PI / 2, Math.PI);
                            cr.arc (-lw / 2 + r, -lh / 2 + r, r, Math.PI, 3 * Math.PI / 2);
                            cr.close_path ();
                        } else {
                            cr.rectangle (-lw / 2, -lh / 2, lw, lh);
                        }
                        paint_shape (cr, l);
                        break;
                }
                cr.pop_group_to_source ();
                cr.paint_with_alpha (opacity);
                cr.restore ();
            }
            return Compose.from_surface (surface);
        }

        void paint_shape (Cairo.Context cr, CompositionLayer l) {
            float r, g, b, a;
            if (l.fill != "") {
                VideoFx.parse_color (l.fill, out r, out g, out b, out a);
                cr.set_source_rgba (r, g, b, a);
                if (l.stroke != "" && l.stroke_width > 0) cr.fill_preserve ();
                else cr.fill ();
            }
            if (l.stroke != "" && l.stroke_width > 0) {
                VideoFx.parse_color (l.stroke, out r, out g, out b, out a);
                cr.set_source_rgba (r, g, b, a);
                cr.set_line_width (l.stroke_width);
                cr.stroke ();
            }
            cr.new_path ();
        }

        Cairo.ImageSurface? image (string src) {
            if (src == "") return null;
            if (images.has_key (src)) return images[src];
            string path = Path.is_absolute (src) ? src : Path.build_filename (base_dir, src);
            Cairo.ImageSurface? surface = null;
            try {
                var pixbuf = new Gdk.Pixbuf.from_file (path);
                surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, pixbuf.width, pixbuf.height);
                var cr = new Cairo.Context (surface);
                Gdk.cairo_set_source_pixbuf (cr, pixbuf, 0, 0);
                cr.paint ();
            } catch (Error e) {
                warning ("composition image %s: %s", src, e.message);
            }
            images[src] = surface;
            return surface;
        }
    }
}
