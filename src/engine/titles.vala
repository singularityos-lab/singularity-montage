using Singularity.Imaging;

namespace Singularity.Apps.Montage {
    namespace Titles {
        public string expand (string text, TitleData data) {
            string result = text;
            foreach (var e in data.fields.entries) result = result.replace ("{" + e.key + "}", e.value);
            return result;
        }

        void set_rgba (Cairo.Context cr, string color, double alpha_scale = 1) {
            float r, g, b, a;
            VideoFx.parse_color (color, out r, out g, out b, out a);
            cr.set_source_rgba (r, g, b, a * alpha_scale);
        }

        Pango.Layout layout_for (Cairo.Context cr, TitleLayer l, string text, double scale, int w) {
            var layout = Pango.cairo_create_layout (cr);
            var desc = Pango.FontDescription.from_string (l.font);
            desc.set_absolute_size (l.size * scale * Pango.SCALE);
            layout.set_font_description (desc);
            layout.set_width ((int) (w * l.width / 100 * Pango.SCALE));
            layout.set_wrap (Pango.WrapMode.WORD_CHAR);
            layout.set_alignment (l.align == "left" ? Pango.Alignment.LEFT : (l.align == "right" ? Pango.Alignment.RIGHT : Pango.Alignment.CENTER));
            if (l.spacing != 0) layout.set_spacing ((int) (l.spacing * scale * Pango.SCALE));
            var attrs = new Pango.AttrList ();
            if (l.tracking != 0) attrs.insert (Pango.attr_letter_spacing_new ((int) (l.tracking * scale * Pango.SCALE)));
            layout.set_attributes (attrs);
            layout.set_text (text, -1);
            return layout;
        }

        public FloatImage render (TitleData data, int w, int h, double scale, int64 local, int64 duration) {
            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context (surface);
            double progress = duration > 0 ? ((double) local / duration).clamp (0, 1) : 0;
            double alpha = 1, slide_x = 0, slide_y = 0;
            double typed = 1;
            int64 anim = int64.max (1, data.anim_duration);
            if (local < anim && data.anim_in != "none") {
                double k = (double) local / anim;
                k = 1 - Math.pow (1 - k, 3);
                switch (data.anim_in) {
                    case "fade": alpha *= k; break;
                    case "slide-up": slide_y += (1 - k) * h * 0.15; alpha *= k; break;
                    case "slide-left": slide_x += (1 - k) * w * 0.2; alpha *= k; break;
                    case "type": typed = k; break;
                }
            }
            if (duration - local < anim && data.anim_out != "none") {
                double k = ((double) (duration - local) / anim).clamp (0, 1);
                switch (data.anim_out) {
                    case "fade": alpha *= k; break;
                    case "slide-up": slide_y -= (1 - k) * h * 0.15; alpha *= k; break;
                    case "slide-left": slide_x -= (1 - k) * w * 0.2; alpha *= k; break;
                    case "type": typed = double.min (typed, k); break;
                }
            }
            double block_top = double.MAX, block_bottom = -double.MAX, block_left = double.MAX, block_right = -double.MAX;
            var layouts = new Gee.ArrayList<Pango.Layout> ();
            foreach (var l in data.layers) {
                string text = expand (l.text, data);
                if (typed < 1) {
                    int chars = (int) Math.round (text.char_count () * typed);
                    text = text.substring (0, text.index_of_nth_char (chars));
                }
                var layout = layout_for (cr, l, text, scale, w);
                layouts.add (layout);
                int lw, lh;
                layout.get_pixel_size (out lw, out lh);
                double cx = w * l.x / 100, cy = h * l.y / 100;
                block_top = double.min (block_top, cy - lh / 2.0);
                block_bottom = double.max (block_bottom, cy + lh / 2.0);
                block_left = double.min (block_left, cx - lw / 2.0);
                block_right = double.max (block_right, cx + lw / 2.0);
            }
            if (data.mode == "roll" && layouts.size > 0) {
                double travel = h + (block_bottom - block_top);
                slide_y += h - block_top - progress * travel;
            } else if (data.mode == "crawl" && layouts.size > 0) {
                double travel = w + (block_right - block_left);
                slide_x += w - block_left - progress * travel;
            }
            for (int i = 0; i < data.layers.size; i++) {
                var l = data.layers[i];
                var layout = layouts[i];
                int lw, lh;
                layout.get_pixel_size (out lw, out lh);
                double box_w = w * l.width / 100;
                double cx = w * l.x / 100 + slide_x, cy = h * l.y / 100 + slide_y;
                double ox = cx - box_w / 2, oy = cy - lh / 2.0;
                Pango.Rectangle ink, logical;
                layout.get_pixel_extents (out ink, out logical);
                if (l.box) {
                    double pad = l.box_padding * scale;
                    double bx = ox + logical.x - pad, by = oy + logical.y - pad, bw = logical.width + pad * 2, bh = logical.height + pad * 2;
                    double r = double.min (pad, bh / 2);
                    cr.new_path ();
                    cr.arc (bx + bw - r, by + r, r, -Math.PI / 2, 0);
                    cr.arc (bx + bw - r, by + bh - r, r, 0, Math.PI / 2);
                    cr.arc (bx + r, by + bh - r, r, Math.PI / 2, Math.PI);
                    cr.arc (bx + r, by + r, r, Math.PI, 3 * Math.PI / 2);
                    cr.close_path ();
                    set_rgba (cr, l.box_color, alpha);
                    cr.fill ();
                }
                if (l.shadow > 0) {
                    var shadow = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
                    var sc = new Cairo.Context (shadow);
                    sc.move_to (ox + l.shadow_x * scale, oy + l.shadow_y * scale);
                    set_rgba (sc, l.shadow_color, alpha);
                    Pango.cairo_show_layout (sc, layout);
                    if (l.outline > 0) {
                        sc.move_to (ox + l.shadow_x * scale, oy + l.shadow_y * scale);
                        Pango.cairo_layout_path (sc, layout);
                        sc.set_line_width (l.outline * scale * 2);
                        sc.stroke ();
                    }
                    var blurred = Compose.from_surface (shadow);
                    if (l.shadow * scale >= 0.3) blurred = Filters.gaussian (blurred, l.shadow * scale / 2, true);
                    var back = Compose.to_surface (blurred);
                    cr.set_source_surface (back, 0, 0);
                    cr.paint ();
                }
                if (l.outline > 0) {
                    cr.move_to (ox, oy);
                    Pango.cairo_layout_path (cr, layout);
                    set_rgba (cr, l.outline_color, alpha);
                    cr.set_line_width (l.outline * scale * 2);
                    cr.set_line_join (Cairo.LineJoin.ROUND);
                    cr.stroke ();
                }
                cr.move_to (ox, oy);
                set_rgba (cr, l.color, alpha);
                Pango.cairo_show_layout (cr, layout);
            }
            return Compose.from_surface (surface);
        }

        public class Template : Object {
            public string id;
            public string name;
            public string category;
            public TitleData data;

            public Template (string id, string name, string category, TitleData data) {
                this.id = id;
                this.name = name;
                this.category = category;
                this.data = data;
            }
        }

        TitleLayer layer (string text, string font, double size, double x, double y, string align = "center") {
            var l = new TitleLayer ();
            l.text = text;
            l.font = font;
            l.size = size;
            l.x = x;
            l.y = y;
            l.align = align;
            return l;
        }

        public Gee.ArrayList<Template> builtin () {
            var r = new Gee.ArrayList<Template> ();
            var plain = new TitleData ();
            plain.layers.add (layer ("{title}", "Sans Bold", 96, 50, 50));
            plain.fields["title"] = _("Title");
            plain.anim_in = plain.anim_out = "fade";
            r.add (new Template ("title", _("Centred Title"), _("Titles"), plain));
            var lower = new TitleData ();
            var name = layer ("{name}", "Sans Bold", 54, 30, 78, "left");
            name.width = 50;
            name.box = true;
            name.box_color = "#101820d0";
            var role = layer ("{role}", "Sans", 34, 30, 86, "left");
            role.width = 50;
            role.color = "#f0c040ff";
            lower.layers.add (name);
            lower.layers.add (role);
            lower.fields["name"] = _("Name Surname");
            lower.fields["role"] = _("Role");
            lower.anim_in = lower.anim_out = "slide-left";
            r.add (new Template ("lower-third", _("Lower Third"), _("Lower Thirds"), lower));
            var outline = new TitleData ();
            var big = layer ("{title}", "Sans Heavy", 120, 50, 45);
            big.outline = 4;
            big.shadow = 12;
            outline.layers.add (big);
            var sub = layer ("{subtitle}", "Sans Italic", 48, 50, 60);
            sub.shadow = 8;
            outline.layers.add (sub);
            outline.fields["title"] = _("Big Title");
            outline.fields["subtitle"] = _("Subtitle");
            outline.anim_in = "slide-up";
            outline.anim_out = "fade";
            r.add (new Template ("outline", _("Outlined Title with Subtitle"), _("Titles"), outline));
            var credits = new TitleData ();
            credits.mode = "roll";
            var c = layer ("{credits}", "Sans", 44, 50, 50);
            c.spacing = 18;
            credits.layers.add (c);
            credits.fields["credits"] = _("Directed by\nName\n\nEdited by\nName\n\nMusic by\nName");
            r.add (new Template ("credits", _("Rolling Credits"), _("Credits"), credits));
            var crawl = new TitleData ();
            crawl.mode = "crawl";
            var news = layer ("{text}", "Sans Bold", 40, 50, 92);
            news.width = 400;
            news.box = true;
            crawl.layers.add (news);
            crawl.fields["text"] = _("Breaking news crawl text");
            r.add (new Template ("crawl", _("News Crawl"), _("Credits"), crawl));
            var typer = new TitleData ();
            typer.layers.add (layer ("{text}", "Monospace Bold", 64, 50, 50));
            typer.fields["text"] = _("Typed text");
            typer.anim_in = "type";
            typer.anim_duration = 1500000000;
            r.add (new Template ("typewriter", _("Typewriter"), _("Titles"), typer));
            r.add_all (user_templates ());
            return r;
        }

        public string templates_dir () {
            return Path.build_filename (Environment.get_user_data_dir (), "singularity-montage", "templates");
        }

        public Gee.ArrayList<Template> user_templates () {
            var r = new Gee.ArrayList<Template> ();
            var dirs = new Gee.ArrayList<string> ();
            dirs.add (templates_dir ());
            foreach (var d in Environment.get_system_data_dirs ()) dirs.add (Path.build_filename (d, "singularity-montage", "templates"));
            foreach (var dir in dirs) {
                try {
                    var e = File.new_for_path (dir).enumerate_children ("standard::name", FileQueryInfoFlags.NONE);
                    FileInfo? info;
                    while ((info = e.next_file ()) != null) {
                        if (!info.get_name ().has_suffix (".json")) continue;
                        try {
                            string text;
                            FileUtils.get_contents (Path.build_filename (dir, info.get_name ()), out text);
                            var o = Js.parse (text);
                            var td = TitleData.read (Js.obj (o, "title") ?? o);
                            string id = Js.str (o, "id", info.get_name ());
                            td.template_id = id;
                            r.add (new Template (id, Js.str (o, "name", info.get_name ()), Js.str (o, "category", _("My Templates")), td));
                        } catch (Error err) {
                            warning ("template %s: %s", info.get_name (), err.message);
                        }
                    }
                } catch (Error err) {
                }
            }
            return r;
        }

        public void save_template (string name, TitleData data) throws Error {
            var dir = File.new_for_path (templates_dir ());
            if (!dir.query_exists ()) dir.make_directory_with_parents ();
            var b = new Json.Builder ();
            b.begin_object ();
            string id = "user-" + new_id ();
            Js.s (b, "id", id);
            Js.s (b, "name", name);
            Js.s (b, "category", _("My Templates"));
            b.set_member_name ("title");
            data.write (b);
            b.end_object ();
            FileUtils.set_contents (dir.get_child (id + ".json").get_path (), Js.write (b.get_root (), true));
        }
    }
}
