using Gtk;

namespace Singularity.Apps.Montage {
    public class Viewer : Widget {
        Gdk.Texture? texture;
        Gdk.Texture? compare;
        Gee.ArrayList<Gdk.Texture?> grid = new Gee.ArrayList<Gdk.Texture?> ();
        public int grid_active = -1;
        public bool safe_areas;
        public string compare_mode = "split";
        public double aspect = 16.0 / 9.0;
        public string label_left = "";
        public string label_right = "";
        public string caption = "";
        string _timecode = "";

        public string timecode {
            get { return _timecode; }
            set {
                _timecode = value;
                queue_draw ();
            }
        }
        public signal void grid_clicked (int index);
        public signal void width_changed (int width);
        int last_width;

        public Viewer () {
            add_css_class ("montage-viewer");
            overflow = Overflow.HIDDEN;
            hexpand = true;
            vexpand = true;
            set_size_request (240, 135);
            var click = new GestureClick ();
            click.pressed.connect ((n, x, y) => {
                if (grid.size == 0) return;
                int cols = (int) Math.ceil (Math.sqrt (grid.size));
                int rows = (grid.size + cols - 1) / cols;
                Graphene.Rect r;
                frame_rect (out r);
                int c = (int) ((x - r.origin.x) / (r.size.width / cols));
                int rr = (int) ((y - r.origin.y) / (r.size.height / rows));
                int index = rr * cols + c;
                if (index >= 0 && index < grid.size) grid_clicked (index);
            });
            add_controller (click);
            update_property (AccessibleProperty.LABEL, _("Video monitor"), -1);
        }

        public void show_texture (Gdk.Texture? t) {
            texture = t;
            if (t != null && t.height > 0) aspect = (double) t.width / t.height;
            queue_draw ();
        }

        public void show_compare (Gdk.Texture? t) {
            compare = t;
            queue_draw ();
        }

        public void show_grid (Gee.List<Gdk.Texture?>? list, int active) {
            grid.clear ();
            if (list != null) grid.add_all (list);
            grid_active = active;
            queue_draw ();
        }

        public Gdk.Texture? current {
            get { return texture; }
        }

        public override void size_allocate (int width, int height, int baseline) {
            base.size_allocate (width, height, baseline);
            if (width != last_width) {
                last_width = width;
                width_changed (width);
            }
        }

        void frame_rect (out Graphene.Rect r) {
            double w = get_width (), h = get_height ();
            double fw = w, fh = w / aspect;
            if (fh > h) {
                fh = h;
                fw = h * aspect;
            }
            r = Graphene.Rect ().init ((float) ((w - fw) / 2), (float) ((h - fh) / 2), (float) fw, (float) fh);
        }

        public override void snapshot (Gtk.Snapshot snap) {
            Graphene.Rect r;
            frame_rect (out r);
            var bg = Gdk.RGBA ();
            bg.parse ("#000000");
            var rounded = Gsk.RoundedRect ();
            rounded.init_from_rect (r, 8);
            snap.push_rounded_clip (rounded);
            snap.append_color (bg, r);
            draw_frame (snap, r);
            snap.pop ();
            if (grid.size > 0) return;
            float bottom = r.origin.y + r.size.height - label_height () - 8;
            draw_label (snap, caption, r.origin.x + 10, bottom);
            if (_timecode != "") {
                var layout = create_pango_layout (_timecode);
                int tw, th;
                layout.get_pixel_size (out tw, out th);
                draw_label (snap, _timecode, r.origin.x + r.size.width - tw - 10, bottom);
            }
        }

        int label_height () {
            int w, h;
            create_pango_layout ("0").get_pixel_size (out w, out h);
            return h;
        }

        void draw_frame (Gtk.Snapshot snap, Graphene.Rect r) {
            if (grid.size > 0) {
                int cols = (int) Math.ceil (Math.sqrt (grid.size));
                int rows = (grid.size + cols - 1) / cols;
                float cw = r.size.width / cols, ch = r.size.height / rows;
                for (int i = 0; i < grid.size; i++) {
                    var cell = Graphene.Rect ().init (r.origin.x + (i % cols) * cw + 2, r.origin.y + (i / cols) * ch + 2, cw - 4, ch - 4);
                    if (grid[i] != null) snap.append_texture (grid[i], cell);
                    if (i == grid_active) {
                        var accent = Gdk.RGBA ();
                        accent.parse ("#e0303a");
                        var rr = Gsk.RoundedRect ();
                        rr.init_from_rect (cell, 0);
                        snap.append_border (rr, { 3, 3, 3, 3 }, { accent, accent, accent, accent });
                    }
                    draw_label (snap, "%d".printf (i + 1), cell.origin.x + 6, cell.origin.y + 4);
                }
                return;
            }
            if (texture != null && compare != null && compare_mode == "side") {
                var left = Graphene.Rect ().init (r.origin.x, r.origin.y + r.size.height / 4, r.size.width / 2 - 2, r.size.height / 2);
                var right = Graphene.Rect ().init (r.origin.x + r.size.width / 2 + 2, r.origin.y + r.size.height / 4, r.size.width / 2 - 2, r.size.height / 2);
                snap.append_texture (compare, left);
                snap.append_texture (texture, right);
                draw_label (snap, label_left, left.origin.x + 6, left.origin.y + 4);
                draw_label (snap, label_right, right.origin.x + 6, right.origin.y + 4);
                return;
            }
            if (texture != null) snap.append_texture (texture, r);
            if (texture != null && compare != null) {
                var half = Graphene.Rect ().init (r.origin.x, r.origin.y, r.size.width / 2, r.size.height);
                snap.push_clip (half);
                snap.append_texture (compare, r);
                snap.pop ();
                var line = Gdk.RGBA ();
                line.parse ("#ffffff");
                snap.append_color (line, Graphene.Rect ().init (r.origin.x + r.size.width / 2 - 1, r.origin.y, 2, r.size.height));
                draw_label (snap, label_left, r.origin.x + 8, r.origin.y + 6);
                draw_label (snap, label_right, r.origin.x + r.size.width / 2 + 8, r.origin.y + 6);
            }
            if (safe_areas) {
                var cr = snap.append_cairo (r);
                cr.set_source_rgba (1, 1, 1, 0.6);
                cr.set_line_width (1);
                foreach (double k in new double[] { 0.05, 0.1 }) {
                    cr.rectangle (r.origin.x + r.size.width * k, r.origin.y + r.size.height * k, r.size.width * (1 - 2 * k), r.size.height * (1 - 2 * k));
                    cr.stroke ();
                }
            }
        }

        void draw_label (Gtk.Snapshot snap, string text, float x, float y) {
            if (text == "") return;
            var layout = create_pango_layout (text);
            int w, h;
            layout.get_pixel_size (out w, out h);
            var bg = Gdk.RGBA ();
            bg.parse ("rgba(0,0,0,0.6)");
            var box = Gsk.RoundedRect ();
            box.init_from_rect (Graphene.Rect ().init (x - 6, y - 2, w + 12, h + 4), 6);
            snap.push_rounded_clip (box);
            snap.append_color (bg, box.bounds);
            snap.pop ();
            snap.save ();
            snap.translate (Graphene.Point ().init (x, y));
            var white = Gdk.RGBA ();
            white.parse ("#ffffff");
            snap.append_layout (layout, white);
            snap.restore ();
        }
    }
    public class ControlStrip : Box {
        public ControlStrip (int top = 4, int bottom = 4) {
            Object (orientation: Orientation.HORIZONTAL, spacing: 6);
            add_css_class ("sx-control-strip");
            margin_start = 10;
            margin_end = 10;
            margin_top = top;
            margin_bottom = bottom;
        }

        public Button add_icon_button (string icon_name, string tooltip) {
            var b = new Button.from_icon_name (icon_name);
            b.tooltip_text = tooltip;
            b.add_css_class ("flat");
            b.valign = Align.CENTER;
            append (b);
            return b;
        }

        public Button add_text_button (string label, string? tooltip = null) {
            var b = new Button.with_label (label);
            b.add_css_class ("flat");
            b.valign = Align.CENTER;
            if (tooltip != null) b.tooltip_text = tooltip;
            append (b);
            return b;
        }

        public ToggleButton add_icon_toggle (string icon_name, string tooltip) {
            var b = new ToggleButton ();
            b.icon_name = icon_name;
            b.tooltip_text = tooltip;
            b.add_css_class ("flat");
            b.valign = Align.CENTER;
            append (b);
            return b;
        }

        public ToggleButton add_text_toggle (string label, string? tooltip = null) {
            var b = new ToggleButton.with_label (label);
            b.add_css_class ("flat");
            b.valign = Align.CENTER;
            if (tooltip != null) b.tooltip_text = tooltip;
            append (b);
            return b;
        }

        public Label add_numeric_label () {
            var l = new Label ("");
            l.add_css_class ("numeric");
            l.valign = Align.CENTER;
            append (l);
            return l;
        }

        public void add_separator () {
            var sep = new Separator (Orientation.VERTICAL);
            sep.margin_top = sep.margin_bottom = 6;
            append (sep);
        }

        public void add_spacer () {
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            append (spacer);
        }
    }
}
