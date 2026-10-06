using Gtk;
using Singularity.Widgets;
using Singularity.Imaging;

namespace Singularity.Apps.Montage {
    public class ColorWheel : DrawingArea {
        public string label;
        public double r;
        public double g;
        public double b;
        public signal void changed ();
        double drag_x;
        double drag_y;

        public ColorWheel (string label) {
            this.label = label;
            set_size_request (104, 120);
            set_draw_func (draw);
            var drag = new GestureDrag ();
            drag.drag_begin.connect ((x, y) => {
                drag_x = x;
                drag_y = y;
                set_from (x, y);
            });
            drag.drag_update.connect ((dx, dy) => set_from (drag_x + dx, drag_y + dy));
            add_controller (drag);
            var click = new GestureClick ();
            click.pressed.connect ((n, x, y) => {
                if (n == 2) {
                    r = g = b = 0;
                    queue_draw ();
                    changed ();
                }
            });
            add_controller (click);
            tooltip_text = _("Drag to tint, double click to reset");
            update_property (AccessibleProperty.LABEL, label, -1);
        }

        double radius () {
            return double.min (get_width (), get_height () - 18) / 2 - 4;
        }

        void set_from (double x, double y) {
            double cx = get_width () / 2.0, cy = (get_height () - 18) / 2.0;
            double rad = radius ();
            double dx = (x - cx) / rad, dy = (y - cy) / rad;
            double len = Math.sqrt (dx * dx + dy * dy);
            if (len > 1) {
                dx /= len;
                dy /= len;
                len = 1;
            }
            double hue = Math.atan2 (-dy, dx) / (2 * Math.PI);
            if (hue < 0) hue += 1;
            float rr, gg, bb;
            Grade.hsv_to_rgb ((float) hue, 1, 1, out rr, out gg, out bb);
            double amount = len * 0.35;
            double mean = (rr + gg + bb) / 3.0;
            r = (rr - mean) * amount;
            g = (gg - mean) * amount;
            b = (bb - mean) * amount;
            queue_draw ();
            changed ();
        }

        void draw (DrawingArea a, Cairo.Context cr, int w, int h) {
            double cx = w / 2.0, cy = (h - 18) / 2.0, rad = radius ();
            for (int i = 0; i < 72; i++) {
                double a0 = i * 2 * Math.PI / 72, a1 = (i + 1) * 2 * Math.PI / 72;
                float rr, gg, bb;
                Grade.hsv_to_rgb (i / 72.0f, 0.55f, 0.8f, out rr, out gg, out bb);
                cr.set_source_rgb (rr, gg, bb);
                cr.move_to (cx, cy);
                cr.arc_negative (cx, cy, rad, -a0, -a1);
                cr.close_path ();
                cr.fill ();
            }
            var grad = new Cairo.Pattern.radial (cx, cy, 0, cx, cy, rad);
            grad.add_color_stop_rgba (0, 0.5, 0.5, 0.5, 1);
            grad.add_color_stop_rgba (1, 0.5, 0.5, 0.5, 0);
            cr.set_source (grad);
            cr.arc (cx, cy, rad, 0, 2 * Math.PI);
            cr.fill ();
            double mean = (r + g + b) / 3;
            double cr_v = r - mean, cg = g - mean, cbv = b - mean;
            float hue, sat, val;
            Grade.rgb_to_hsv ((float) (cr_v + 0.5), (float) (cg + 0.5), (float) (cbv + 0.5), out hue, out sat, out val);
            double len = Math.sqrt (cr_v * cr_v + cg * cg + cbv * cbv) / 0.35 / 0.82;
            double px = cx + Math.cos (hue * 2 * Math.PI) * len.clamp (0, 1) * rad;
            double py = cy - Math.sin (hue * 2 * Math.PI) * len.clamp (0, 1) * rad;
            cr.set_source_rgb (1, 1, 1);
            cr.set_line_width (2);
            cr.arc (px, py, 5, 0, 2 * Math.PI);
            cr.stroke ();
            var fg = get_color ();
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 1);
            cr.select_font_face ("sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
            cr.set_font_size (11);
            Cairo.TextExtents ext;
            cr.text_extents (label, out ext);
            cr.move_to (cx - ext.width / 2, h - 4);
            cr.show_text (label);
        }
    }

    public class CurveEditor : DrawingArea {
        public Gee.ArrayList<double?> xs = new Gee.ArrayList<double?> ();
        public Gee.ArrayList<double?> ys = new Gee.ArrayList<double?> ();
        public bool periodic;
        public string color = "#ffffff";
        public signal void changed ();
        int dragging = -1;

        public CurveEditor () {
            set_size_request (260, 180);
            set_draw_func (draw);
            var drag = new GestureDrag ();
            drag.drag_begin.connect ((x, y) => {
                dragging = nearest (x, y);
                if (dragging < 0) {
                    add_point (x / get_width (), 1 - y / get_height ());
                    dragging = nearest (x, y);
                }
            });
            drag.drag_update.connect ((dx, dy) => {
                if (dragging < 0) return;
                double sx, sy;
                drag.get_start_point (out sx, out sy);
                xs[dragging] = ((sx + dx) / get_width ()).clamp (0, 1);
                ys[dragging] = (1 - (sy + dy) / get_height ()).clamp (0, 1);
                queue_draw ();
            });
            drag.drag_end.connect (() => {
                dragging = -1;
                changed ();
            });
            add_controller (drag);
            var right = new GestureClick ();
            right.button = 3;
            right.pressed.connect ((n, x, y) => {
                int i = nearest (x, y);
                if (i >= 0 && xs.size > 2) {
                    xs.remove_at (i);
                    ys.remove_at (i);
                    queue_draw ();
                    changed ();
                }
            });
            add_controller (right);
            tooltip_text = _("Drag points, click to add, right click to remove");
        }

        void add_point (double x, double y) {
            xs.add (x.clamp (0, 1));
            ys.add (y.clamp (0, 1));
        }

        int nearest (double x, double y) {
            for (int i = 0; i < xs.size; i++) {
                double px = xs[i] * get_width (), py = (1 - ys[i]) * get_height ();
                if ((px - x).abs () < 9 && (py - y).abs () < 9) return i;
            }
            return -1;
        }

        public void load (string text, bool periodic) {
            this.periodic = periodic;
            xs.clear ();
            ys.clear ();
            foreach (var pair in text.split (";")) {
                var p = pair.split (",");
                if (p.length != 2) continue;
                add_point (double.parse (p[0]), double.parse (p[1]));
            }
            if (xs.size == 0) {
                if (periodic) {
                    add_point (0, 0.5);
                    add_point (0.5, 0.5);
                } else {
                    add_point (0, 0);
                    add_point (1, 1);
                }
            }
            queue_draw ();
        }

        public string serialize () {
            var parts = new Gee.ArrayList<string> ();
            for (int i = 0; i < xs.size; i++) {
                double x = xs[i], y = ys[i];
                parts.add ("%.4f,%.4f".printf (x, y));
            }
            return string.joinv (";", parts.to_array ());
        }

        void draw (DrawingArea a, Cairo.Context cr, int w, int h) {
            cr.set_source_rgb (0.08, 0.08, 0.09);
            cr.paint ();
            cr.set_source_rgba (1, 1, 1, 0.1);
            cr.set_line_width (1);
            for (int i = 1; i < 4; i++) {
                cr.move_to (i * w / 4.0, 0);
                cr.line_to (i * w / 4.0, h);
                cr.move_to (0, i * h / 4.0);
                cr.line_to (w, i * h / 4.0);
            }
            cr.stroke ();
            if (periodic) {
                for (int i = 0; i < w; i += 4) {
                    float r, g, b;
                    Grade.hsv_to_rgb ((float) i / w, 0.7f, 0.8f, out r, out g, out b);
                    cr.set_source_rgba (r, g, b, 0.8);
                    cr.rectangle (i, h - 6, 4, 6);
                    cr.fill ();
                }
            }
            var lut = CurveLut.parse (serialize (), periodic);
            var c = Gdk.RGBA ();
            c.parse (color);
            cr.set_source_rgba (c.red, c.green, c.blue, 0.95);
            cr.set_line_width (2);
            for (int x = 0; x <= w; x++) {
                double v = periodic ? lut.map_periodic ((float) x / w) : lut.map ((float) x / w);
                double y = (1 - v.clamp (0, 1)) * h;
                if (x == 0) cr.move_to (x, y);
                else cr.line_to (x, y);
            }
            cr.stroke ();
            for (int i = 0; i < xs.size; i++) {
                cr.arc (xs[i] * w, (1 - ys[i]) * h, 4.5, 0, 2 * Math.PI);
                cr.fill ();
            }
        }
    }

    public class ColorPanel : Box {
        MontageWindow w;
        Controller ctl;
        Scopes scopes = new Scopes ();
        Box clip_box = new Box (Orientation.VERTICAL, 12);
        string shown = "";
        public static FloatImage? reference;
        public static string reference_label = "";

        public ColorPanel (MontageWindow w) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.w = w;
            ctl = w.ctl;
            spacing = 12;
            vexpand = true;
            clip_box.vexpand = true;
            var scope_group = new PreferencesGroup ();
            scope_group.title = _("Scopes");
            string[] modes = { "waveform", "parade", "vectorscope", "histogram" };
            scopes.margin_top = scopes.margin_bottom = 8;
            scopes.margin_start = scopes.margin_end = 8;
            scope_group.add_row (scopes);
            scope_group.add_row (Rows.choice (_("Scope"), null, { _("Waveform"), _("RGB Parade"), _("Vectorscope"), _("Histogram") }, 0, (i) => {
                scopes.mode = modes[i];
                scopes.queue_draw ();
            }));
            append (scope_group);
            var space = new PreferencesGroup ();
            space.title = _("Sequence Colour");
            string[] spaces = { "rec709", "rec2020-pq", "rec2020-hlg" };
            int space_index = 0;
            for (int i = 0; i < 3; i++) if (spaces[i] == ctl.seq.color_space) space_index = i;
            var space_row = Rows.choice (_("Colour Space"), _("HDR sequences export as 10 bit PQ or HLG"), { _("Rec.709 SDR"), _("Rec.2020 HDR PQ"), _("Rec.2020 HDR HLG") }, space_index, (i) => {
                if (ctl.seq.color_space == spaces[i]) return;
                ctl.project.checkpoint (_("Colour Space"));
                ctl.seq.color_space = spaces[i];
                ctl.project.commit ();
            });
            space.add_row (space_row);
            append (space);
            append (clip_box);
            ctl.program.frame.connect ((f) => {
                if (f.image != null && get_mapped ()) scopes.update (f.image);
            });
            map.connect (() => {
                ctl.program.keep_images = true;
                ctl.program.seek (ctl.program.position);
                rebuild ();
            });
            unmap.connect (() => ctl.program.keep_images = false);
            ctl.selection_changed.connect (rebuild);
            ctl.project.changed.connect (() => {
                string sig = ctl.primary != null ? ctl.primary.id : "";
                if (sig != shown) rebuild ();
            });
        }

        Effect ensure (Clip c, string type) {
            var e = c.find_effect (type);
            if (e != null) return e;
            ctl.project.checkpoint (_("Colour"));
            e = Catalog.find (type).create ();
            int at = 0;
            while (at < c.effects.size && c.effects[at].type.has_prefix ("color.")) at++;
            c.effects.insert (at, e);
            ctl.project.commit ();
            return e;
        }

        void clear () {
            Widget? x;
            while ((x = clip_box.get_first_child ()) != null) clip_box.remove (x);
        }

        void rebuild () {
            if (!get_mapped ()) return;
            clear ();
            var c = ctl.primary;
            shown = c != null ? c.id : "";
            var t = c != null ? ctl.seq.track (c.track) : null;
            if (c == null || t == null || t.kind != TrackKind.VIDEO) {
                var page = new StatusPage ();
                page.compact = true;
                page.icon_name = "dev.sinty.montage";
                page.title = _("No Video Clip Selected");
                page.description = _("Select a video clip or an adjustment layer on the timeline to grade it.");
                page.vexpand = true;
                page.valign = Align.CENTER;
                clip_box.append (page);
                return;
            }
            var primary_group = new PreferencesGroup ();
            primary_group.title = _("Primary Correction");
            var primary = c.find_effect ("color.primary");
            if (primary == null) {
                primary_group.add_row (Rows.action (_("Add Primary Correction"), _("Exposure, contrast, saturation and white balance"), () => {
                    ensure (c, "color.primary");
                    rebuild ();
                }));
            } else {
                var info = Catalog.find ("color.primary");
                foreach (var spec in info.params) primary_group.add_row (effect_row (c, primary, spec));
            }
            clip_box.append (primary_group);
            var wheel_group = new PreferencesGroup ();
            wheel_group.title = _("Colour Wheels");
            var wheels_box = new Box (Orientation.HORIZONTAL, 6);
            wheels_box.homogeneous = true;
            var e = c.find_effect ("color.wheels");
            foreach (var key in new string[] { "lift", "gamma", "gain" }) {
                string k = key;
                var wheel = new ColorWheel (k == "lift" ? _("Shadows") : (k == "gamma" ? _("Midtones") : _("Highlights")));
                if (e != null) {
                    wheel.r = e.params.get_value (k + "-r", 0, 0);
                    wheel.g = e.params.get_value (k + "-g", 0, 0);
                    wheel.b = e.params.get_value (k + "-b", 0, 0);
                }
                wheel.changed.connect (() => {
                    var fx = ensure (c, "color.wheels");
                    ctl.project.checkpoint_once (c.id + "wheel" + k, _("Colour Wheel"));
                    fx.params.ensure (k + "-r", 0).value = wheel.r;
                    fx.params.ensure (k + "-g", 0).value = wheel.g;
                    fx.params.ensure (k + "-b", 0).value = wheel.b;
                    ctl.project.commit ();
                });
                wheels_box.append (wheel);
            }
            wheel_group.add_row (wheels_box);
            foreach (var key in new string[] { "lift", "gamma", "gain" }) {
                string k = key;
                var spec = new ParamSpec (k + "-l", (k == "lift" ? _("Shadows") : (k == "gamma" ? _("Midtones") : _("Highlights"))) + " " + _("Level"), -1, 1, 0, 0.01);
                var row = new SpinRow (spec.label, null, -1, 1, 0.01, e != null ? e.params.get_value (k + "-l", 0, 0) : 0);
                row.spin_btn.digits = 2;
                row.spin_btn.value_changed.connect (() => {
                    var fx = ensure (c, "color.wheels");
                    ctl.project.checkpoint_once (c.id + k + "-l", _("Colour Wheel"));
                    fx.params.ensure (k + "-l", 0).value = row.value;
                    ctl.project.commit ();
                });
                wheel_group.add_row (row);
            }
            clip_box.append (wheel_group);
            var curve_group = new PreferencesGroup ();
            curve_group.title = _("Curves");
            var curves = c.find_effect ("color.curves");
            string[] keys = { "master", "red", "green", "blue", "hue-sat", "hue-hue", "luma-sat" };
            string[] colors = { "#ffffff", "#ff5050", "#50e070", "#5080ff", "#ffd050", "#ff80ff", "#80e0ff" };
            var editor = new CurveEditor ();
            int curve_index = 0;
            var which = Rows.choice (_("Channel"), null, { _("Master"), _("Red"), _("Green"), _("Blue"), _("Hue vs Saturation"), _("Hue vs Hue"), _("Luma vs Saturation") }, 0, (i) => {
                curve_index = i;
                string k = keys[i];
                var fx = c.find_effect ("color.curves");
                editor.color = colors[i];
                editor.load (fx != null ? fx.params.text (k) : "", k.has_prefix ("hue"));
            });
            editor.load (curves != null ? curves.params.text ("master") : "", false);
            editor.changed.connect (() => {
                var fx = ensure (c, "color.curves");
                ctl.project.checkpoint (_("Curves"));
                fx.params.texts[keys[curve_index]] = editor.serialize ();
                ctl.project.commit ();
            });
            editor.margin_top = editor.margin_bottom = 8;
            editor.margin_start = editor.margin_end = 8;
            curve_group.add_row (editor);
            curve_group.add_row (which);
            clip_box.append (curve_group);
            var lut_group = new PreferencesGroup ();
            lut_group.title = _("Look");
            var lut = c.find_effect ("color.lut");
            var lut_row = new ActionRow (_("LUT"), lut != null && lut.params.text ("file") != "" ? Path.get_basename (lut.params.text ("file")) : _("Load a .cube or .3dl file"));
            var choose = new Button.with_label (_("Choose…"));
            choose.valign = Align.CENTER;
            choose.clicked.connect (() => {
                FileOps.open_dialog.begin (w, { FileOps.filter (_("LUT Files"), { "cube", "3dl" }) }, (o, r) => {
                    var f = FileOps.open_dialog.end (r);
                    if (f == null) return;
                    try {
                        Lut3D.load (f.get_path ());
                    } catch (Error err) {
                        w.say (err.message);
                        return;
                    }
                    var fx = ensure (c, "color.lut");
                    ctl.project.checkpoint (_("LUT"));
                    fx.params.texts["file"] = f.get_path ();
                    ctl.project.commit ();
                    rebuild ();
                });
            });
            lut_row.add_suffix (choose);
            lut_group.add_row (lut_row);
            if (lut != null) lut_group.add_row (effect_row (c, lut, Catalog.find ("color.lut").spec ("intensity")));
            clip_box.append (lut_group);
            var match_group = new PreferencesGroup ();
            match_group.title = _("Colour Match");
            var ref_row = new ActionRow (_("Reference"), reference != null ? reference_label : _("Pick a shot to match the others to"));
            var set_ref = new Button.with_label (_("Use Current Frame"));
            set_ref.valign = Align.CENTER;
            set_ref.clicked.connect (() => {
                var snap = ctl.project.clone ();
                var r = new Renderer (snap, snap.sequence, 0.25, false);
                reference = r.render (ctl.playhead);
                r.close ();
                reference_label = "%s %s".printf (ctl.project.clip_label (c), Tc.format (ctl.playhead, ctl.seq.fps_n, ctl.seq.fps_d));
                w.program_view.compare_mode = "split";
                w.program_view.label_left = _("Reference");
                w.program_view.label_right = _("Current");
                w.program_view.show_compare (TrimPreview.texture (reference));
                rebuild ();
            });
            ref_row.add_suffix (set_ref);
            match_group.add_row (ref_row);
            var match = Rows.action (_("Match Selected Clip"), _("Grade the selected clip to look like the reference"), () => match_selected (w));
            match.sensitive = reference != null;
            match_group.add_row (match);
            match_group.add_row (Rows.action (_("Hide Comparison"), null, () => w.program_view.show_compare (null)));
            clip_box.append (match_group);
        }

        ParamRow effect_row (Clip c, Effect e, ParamSpec spec) {
            string cid = c.id, eid = e.id;
            return new ParamRow (ctl, eid + spec.name, spec.label, spec, () => {
                var clip = ctl.seq.clip (cid);
                if (clip == null) return null;
                foreach (var fx in clip.effects) if (fx.id == eid) return fx.params.ensure (spec.name, spec.fallback);
                return null;
            }, () => {
                var clip = ctl.seq.clip (cid);
                return clip != null ? clip.key_time (ctl.program.position) : 0;
            });
        }

        public static void match_selected (MontageWindow w) {
            var c = w.ctl.primary;
            if (c == null) {
                w.say (_("Select the clip to match."));
                return;
            }
            if (reference == null) {
                w.say (_("Set a reference frame in the Colour workspace first."));
                return;
            }
            var snap = w.project.clone ();
            var sc = snap.sequence.clip (c.id);
            if (sc == null) return;
            sc.effects.clear ();
            var r = new Renderer (snap, snap.sequence, 0.25, false);
            int64 t = w.ctl.playhead >= c.position && w.ctl.playhead < c.end ? w.ctl.playhead : c.position + c.duration / 2;
            var source = r.render (t);
            r.close ();
            var e = Analysis.match_color (source, reference, reference_label);
            w.project.checkpoint (_("Colour Match"));
            var old = c.find_effect ("color.match");
            if (old != null) c.effects.remove (old);
            c.effects.insert (0, e);
            w.project.commit ();
            w.say (_("Matched %s to %s.").printf (w.project.clip_label (c), reference_label));
        }
    }
}
