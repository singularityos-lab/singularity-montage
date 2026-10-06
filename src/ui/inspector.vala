using Gtk;
using Singularity.Widgets;
using Singularity.Keyframes;

namespace Singularity.Apps.Montage {
    public class KeyButton : Button {
        public bool on;
        public bool animated;

        public KeyButton () {
            add_css_class ("flat");
            add_css_class ("circular");
            valign = Align.CENTER;
            var area = new DrawingArea ();
            area.set_size_request (14, 14);
            area.set_draw_func ((a, cr, w, h) => {
                var c = a.get_color ();
                cr.set_source_rgba (c.red, c.green, c.blue, animated ? 1 : 0.45);
                cr.move_to (w / 2.0, 1);
                cr.line_to (w - 1, h / 2.0);
                cr.line_to (w / 2.0, h - 1);
                cr.line_to (1, h / 2.0);
                cr.close_path ();
                if (on) cr.fill ();
                else {
                    cr.set_line_width (1.5);
                    cr.stroke ();
                }
            });
            child = area;
            tooltip_text = _("Add or remove a keyframe at the playhead");
        }

        public void set_state (bool animated, bool on) {
            this.animated = animated;
            this.on = on;
            child.queue_draw ();
        }
    }

    public delegate AnimatedValue? ValueSource ();
    public delegate int64 KeySource ();

    public class ParamRow : ActionRow {
        public SpinButton spin;
        KeyButton key = new KeyButton ();
        Controller ctl;
        owned ValueSource source;
        owned KeySource key_time;
        bool updating;
        string id;
        Button prev_button;
        Button next_button;

        public ParamRow (Controller ctl, string id, string title, ParamSpec spec, owned ValueSource source, owned KeySource key_time) {
            base (title, spec.unit != "" ? spec.unit : null);
            this.ctl = ctl;
            this.id = id;
            this.source = (owned) source;
            this.key_time = (owned) key_time;
            spin = new SpinButton.with_range (spec.min, spec.max, spec.step);
            spin.digits = spec.step < 0.01 ? 3 : (spec.step < 1 ? 2 : 0);
            spin.valign = Align.CENTER;
            spin.width_chars = 7;
            spin.value_changed.connect (on_value);
            key.clicked.connect (toggle_key);
            var prev = new Button.from_icon_name ("go-previous-symbolic");
            prev.add_css_class ("flat");
            prev.valign = Align.CENTER;
            prev.tooltip_text = _("Previous keyframe");
            prev.clicked.connect (() => jump (false));
            var next = new Button.from_icon_name ("go-next-symbolic");
            next.add_css_class ("flat");
            next.valign = Align.CENTER;
            next.tooltip_text = _("Next keyframe");
            next.clicked.connect (() => jump (true));
            prev.visible = false;
            next.visible = false;
            add_suffix (spin);
            add_suffix (prev);
            add_suffix (key);
            add_suffix (next);
            prev_button = prev;
            next_button = next;
            refresh ();
        }

        public void refresh () {
            var v = source ();
            if (v == null) return;
            updating = true;
            int64 k = key_time ();
            spin.value = v.at (k);
            key.set_state (v.animated, v.index_at (k) >= 0);
            if (prev_button != null) {
                prev_button.visible = v.animated;
                next_button.visible = v.animated;
            }
            updating = false;
        }

        void on_value () {
            if (updating) return;
            var v = source ();
            if (v == null) return;
            ctl.project.checkpoint_once (id, _("Change %s").printf (title));
            v.set_at (key_time (), spin.value);
            ctl.project.commit ();
            refresh ();
        }

        void toggle_key () {
            var v = source ();
            if (v == null) return;
            int64 k = key_time ();
            ctl.project.checkpoint (_("Keyframe"));
            if (v.index_at (k) >= 0) v.remove_key (k);
            else v.set_key (k, v.at (k));
            ctl.project.commit ();
            refresh ();
        }

        void jump (bool forward) {
            var v = source ();
            if (v == null || !v.animated) return;
            int64 k = key_time ();
            int64 target = forward ? v.next_key (k) : v.previous_key (k);
            if (target == int64.MAX || target == int64.MIN) return;
            ctl.seek (ctl.program.position + (target - k));
        }
    }

    public class Inspector : Box {
        Controller ctl;
        Box content = new Box (Orientation.VERTICAL, 14);
        Gee.ArrayList<ParamRow> rows = new Gee.ArrayList<ParamRow> ();
        string shown = "";
        bool editing;
        public MediaItem? media;

        public Inspector (Controller ctl) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.ctl = ctl;
            vexpand = true;
            content.vexpand = true;
            append (content);
            ctl.selection_changed.connect (() => rebuild (true));
            ctl.project.changed.connect (() => {
                if (!editing) rebuild (false);
                else foreach (var r in rows) r.refresh ();
            });
            ctl.program.position_changed.connect ((t) => {
                foreach (var r in rows) r.refresh ();
            });
            rebuild (true);
        }

        public void show_media (MediaItem? m) {
            media = m;
            rebuild (true);
        }

        string signature () {
            var c = ctl.primary;
            if (c == null) return media != null ? "media:" + media.id : "none";
            var sb = new StringBuilder (c.id);
            sb.append (c.kind.key ());
            foreach (var e in c.effects) sb.append (e.id);
            foreach (var t in ctl.seq.transitions_of (c.id)) sb.append (t.id + t.kind);
            if (c.title != null) sb.append ("%d%s".printf (c.title.layers.size, c.title.template_id));
            return sb.str;
        }

        void clear () {
            Widget? w;
            while ((w = content.get_first_child ()) != null) content.remove (w);
            rows.clear ();
        }

        public void rebuild (bool force) {
            string sig = signature ();
            if (!force && sig == shown) {
                foreach (var r in rows) r.refresh ();
                return;
            }
            shown = sig;
            clear ();
            var c = ctl.primary;
            if (c == null) {
                if (media != null) build_media (media);
                else {
                    var page = new StatusPage ();
                    page.icon_name = "dev.sinty.montage";
                    page.title = _("Nothing Selected");
                    page.description = _("Select a clip on the timeline to change its motion, colour, audio and effects.");
                    page.vexpand = true;
                    page.valign = Align.CENTER;
                    content.append (page);
                }
                return;
            }
            build_clip (c);
        }

        void with_edit (owned Delegates.Action action) {
            editing = true;
            action ();
            editing = false;
        }

        ParamRow param_row (Clip c, string name) {
            ParamSpec? spec = null;
            foreach (var s in Catalog.clip_params ()) if (s.name == name) spec = s;
            string cid = c.id;
            var row = new ParamRow (ctl, cid + name, spec.label, spec, () => {
                var clip = ctl.seq.clip (cid);
                return clip != null ? clip.params.ensure (name, spec.fallback) : null;
            }, () => {
                var clip = ctl.seq.clip (cid);
                return clip != null ? clip.key_time (ctl.program.position) : 0;
            });
            row.spin.value_changed.connect (() => { editing = true; Idle.add (() => { editing = false; return Source.REMOVE; }); });
            rows.add (row);
            return row;
        }

        ParamRow effect_row (Clip c, Effect e, ParamSpec spec) {
            string cid = c.id, eid = e.id;
            var row = new ParamRow (ctl, eid + spec.name, spec.label, spec, () => {
                var clip = ctl.seq.clip (cid);
                if (clip == null) return null;
                foreach (var fx in clip.effects) if (fx.id == eid) return fx.params.ensure (spec.name, spec.fallback);
                return null;
            }, () => {
                var clip = ctl.seq.clip (cid);
                return clip != null ? clip.key_time (ctl.program.position) : 0;
            });
            row.spin.value_changed.connect (() => { editing = true; Idle.add (() => { editing = false; return Source.REMOVE; }); });
            rows.add (row);
            return row;
        }

        void heading (string text, string? subtitle = null) {
            var l = new Label (text);
            l.add_css_class ("title-2");
            l.halign = Align.START;
            l.ellipsize = Pango.EllipsizeMode.MIDDLE;
            content.append (l);
            if (subtitle != null) {
                var s = new Label (subtitle);
                s.add_css_class ("dim-label");
                s.halign = Align.START;
                s.wrap = true;
                s.xalign = 0;
                content.append (s);
            }
        }

        void change (string label, owned Delegates.Action action) {
            editing = true;
            ctl.project.checkpoint (label);
            action ();
            ctl.project.commit ();
            editing = false;
        }

        SelectionRow choice (string title, string? subtitle, string[] labels, int selected, owned Rows.IndexChanged changed) {
            return Rows.choice (title, subtitle, labels, selected, (owned) changed);
        }

        void build_clip (Clip c) {
            var track = ctl.seq.track (c.track);
            bool audio = track != null && track.kind == TrackKind.AUDIO;
            heading (ctl.project.clip_label (c), "%s  %s".printf (Tc.format (c.position, ctl.seq.fps_n, ctl.seq.fps_d), Tc.format (c.duration, ctl.seq.fps_n, ctl.seq.fps_d)));
            var basic = new PreferencesGroup ();
            basic.title = _("Clip");
            var name = new EntryRow (_("Name"));
            name.text = c.name;
            name.entry_activated.connect (() => change (_("Rename"), () => { c.name = name.text; }));
            basic.add_row (name);
            var enabled = new SwitchRow (_("Enabled"), _("Disabled clips are skipped in playback and export"), c.enabled);
            enabled.switch_btn.notify["active"].connect (() => change (_("Enable"), () => { c.enabled = enabled.active; }));
            basic.add_row (enabled);
            basic.add_row (choice (_("Label"), null, { _("None"), _("Red"), _("Orange"), _("Yellow"), _("Green"), _("Violet"), _("Cyan"), _("Pink") }, c.label, (sel) => change (_("Label"), () => { c.label = (int) sel; })));
            content.append (basic);
            switch (c.kind) {
                case ClipKind.TITLE: build_title (c); break;
                case ClipKind.COLOR: build_color_clip (c); break;
                case ClipKind.SUBTITLE: build_subtitle (c); return;
                case ClipKind.MULTICAM: build_multicam (c); break;
                case ClipKind.COMPOSITION: build_composition (c); break;
                default: break;
            }
            if (!audio && c.kind != ClipKind.ADJUSTMENT) {
                var motion = new PreferencesGroup ();
                motion.title = _("Motion");
                foreach (var n in new string[] { "x", "y", "scale", "scale-x", "scale-y", "rotation", "anchor-x", "anchor-y" }) motion.add_row (param_row (c, n));
                string[] fits = { "fit", "fill", "none" };
                int fit_index = 0;
                for (int i = 0; i < fits.length; i++) if (c.params.text ("fit", "fit") == fits[i]) fit_index = i;
                motion.add_row (choice (_("Frame Fit"), _("How the picture fills the sequence frame"), { _("Fit"), _("Fill"), _("Original Size") }, fit_index, (sel) => change (_("Frame Fit"), () => { c.params.texts["fit"] = fits[sel]; })));
                content.append (motion);
            }
            if (!audio) {
                var opacity = new PreferencesGroup ();
                opacity.title = _("Opacity and Blending");
                opacity.add_row (param_row (c, "opacity"));
                var modes = new Gee.ArrayList<string> ();
                var keys = new Gee.ArrayList<string> ();
                for (int i = 0; i < Singularity.Imaging.BlendMode.COUNT; i++) {
                    var mode = (Singularity.Imaging.BlendMode) i;
                    modes.add (mode.label ());
                    keys.add (mode.key ());
                }
                opacity.add_row (choice (_("Blend Mode"), null, modes.to_array (), keys.index_of (c.blend), (sel) => change (_("Blend Mode"), () => { c.blend = keys[sel]; })));
                if (c.kind != ClipKind.ADJUSTMENT) foreach (var n in new string[] { "crop-left", "crop-right", "crop-top", "crop-bottom" }) opacity.add_row (param_row (c, n));
                content.append (opacity);
            }
            if (c.kind == ClipKind.MEDIA || c.kind == ClipKind.SEQUENCE || c.kind == ClipKind.MULTICAM) build_speed (c);
            if (audio) {
                var sound = new PreferencesGroup ();
                sound.title = _("Audio");
                sound.add_row (param_row (c, "volume"));
                sound.add_row (param_row (c, "pan"));
                string[] roles = { "", "dialogue", "music", "effects" };
                int ri = 0;
                for (int i = 0; i < roles.length; i++) if (c.role == roles[i]) ri = i;
                sound.add_row (choice (_("Role"), _("Music clips duck under dialogue"), { _("None"), _("Dialogue"), _("Music"), _("Effects") }, ri, (sel) => change (_("Role"), () => { c.role = roles[sel]; })));
                content.append (sound);
            }
            var km = ctl.project.find_media (c.media);
            if (!audio && km != null && km.uri.has_suffix (".keyframe")) build_keyframe_values (c, km);
            if (!audio && (c.kind == ClipKind.MEDIA || c.kind == ClipKind.MULTICAM)) {
                var color = new PreferencesGroup ();
                color.title = _("Input Colour");
                string[] spaces = { "auto", "rec709", "rec2020-pq", "rec2020-hlg" };
                int si = 0;
                for (int i = 0; i < spaces.length; i++) if (c.color_space == spaces[i]) si = i;
                color.add_row (choice (_("Colour Space"), _("Override what the file reports"), { _("Automatic"), "Rec.709", "Rec.2020 PQ", "Rec.2020 HLG" }, si, (sel) => change (_("Colour Space"), () => { c.color_space = spaces[sel]; })));
                content.append (color);
            }
            build_transitions (c);
            build_effects (c, audio);
        }

        void build_keyframe_values (Clip c, MediaItem m) {
            var labels = new Gee.ArrayList<string> ();
            try {
                var zip = ZipArchive.read (File.new_for_uri (m.uri));
                var o = Js.parse (zip.text ("project.json") ?? "{}");
                var comps = Js.objects (o, "compositions");
                foreach (var item in Js.objects (o, "items")) if (Js.str (item, "type") == "composition") comps.add (item);
                foreach (var comp in comps) foreach (var e in Js.objects (comp, "essential")) {
                    string l = Js.str (e, "label");
                    if (l != "" && !labels.contains (l)) labels.add (l);
                }
            } catch (Error e) {
                return;
            }
            var g = new PreferencesGroup ();
            g.title = _("Template Values");
            Json.Object current;
            try {
                current = Js.parse (c.params.text ("keyframe-overrides", "{}"));
            } catch (Error e) {
                current = new Json.Object ();
            }
            if (labels.size == 0) g.description = _("This Keyframe composition has no Essential Graphics parameters.");
            foreach (var label in labels) {
                string l = label;
                var row = new EntryRow (l);
                if (current.has_member (l)) {
                    var n = current.get_member (l);
                    row.text = n.get_value_type () == typeof (string) ? n.get_string () : "%g".printf (n.get_double ());
                }
                row.entry_activated.connect (() => change (_("Template Value"), () => {
                    double num;
                    if (double.try_parse (row.text, out num)) current.set_double_member (l, num);
                    else current.set_string_member (l, row.text);
                    var node = new Json.Node (Json.NodeType.OBJECT);
                    node.set_object (current);
                    c.params.texts["keyframe-overrides"] = Js.write (node);
                }));
                g.add_row (row);
            }
            content.append (g);
        }

        void build_speed (Clip c) {
            var g = new PreferencesGroup ();
            g.title = _("Speed");
            var speed = new SpinRow (_("Speed"), _("Percent of normal speed"), 1, 10000, 5, c.params.get_value ("speed", c.in_point, 100));
            speed.spin_btn.digits = 0;
            g.add_row (speed);
            var reverse = new SwitchRow (_("Reverse"), null, c.reverse);
            g.add_row (reverse);
            var blend = new SwitchRow (_("Frame Blending"), _("Mix neighbouring frames for smooth slow motion"), c.frame_blend);
            g.add_row (blend);
            var ripple = new SwitchRow (_("Ripple Later Clips"), _("Move the following clips when the length changes"), true);
            g.add_row (ripple);
            g.add_row (Rows.action (_("Apply Speed"), null, () => {
                try {
                    editing = true;
                    ctl.edits.set_speed (c.id, speed.value, reverse.active, ripple.active, blend.active);
                    editing = false;
                    rebuild (true);
                } catch (Error e) {
                    ctl.say (e.message);
                }
            }));
            g.add_row (Rows.action (_("Add Speed Ramp Keyframe"), _("Animate the speed from the playhead for ramps"), () => {
                change (_("Speed Ramp"), () => {
                    var v = c.params.ensure ("speed", 100);
                    v.set_key (c.key_time (ctl.program.position), speed.value, Interpolation.EASE_IN_OUT);
                });
                rebuild (true);
            }));
            content.append (g);
            if (c.params.values.has_key ("speed") && c.params.values["speed"].animated) {
                var spec = new ParamSpec ("speed", _("Ramp Speed at Playhead"), 1, 10000, 100, 1, "%");
                string cid = c.id;
                var row = new ParamRow (ctl, cid + "ramp", spec.label, spec, () => {
                    var clip = ctl.seq.clip (cid);
                    return clip != null ? clip.params.ensure ("speed", 100) : null;
                }, () => {
                    var clip = ctl.seq.clip (cid);
                    return clip != null ? clip.key_time (ctl.program.position) : 0;
                });
                rows.add (row);
                g.add_row (row);
            }
        }

        void build_transitions (Clip c) {
            var list = ctl.seq.transitions_of (c.id);
            var g = new PreferencesGroup ();
            g.title = _("Transitions");
            string[] kinds = { "dissolve", "additive", "dip", "wipe", "push", "slide", "iris", "clock", "barn", "zoom", "constant-gain" };
            string[] names = { _("Cross Dissolve"), _("Additive Dissolve"), _("Dip to Colour"), _("Wipe"), _("Push"), _("Slide"), _("Iris"), _("Clock Wipe"), _("Barn Door"), _("Cross Zoom"), _("Constant Gain Fade") };
            foreach (var item in list) {
                var t = item;
                string side = t.from_clip == c.id ? (t.to_clip == "" ? _("Fade Out") : _("Outgoing")) : (t.from_clip == "" ? _("Fade In") : _("Incoming"));
                var exp = new ExpanderRow (side, null);
                int ki = 0;
                for (int i = 0; i < kinds.length; i++) if (kinds[i] == t.kind) ki = i;
                exp.add_row (choice (_("Kind"), null, names, ki, (sel) => change (_("Transition"), () => { t.kind = kinds[sel]; })));
                var dur = new SpinRow (_("Duration"), _("Seconds"), 0.04, 30, 0.04, (double) t.duration / Tc.SECOND);
                dur.spin_btn.digits = 2;
                dur.spin_btn.value_changed.connect (() => {
                    editing = true;
                    ctl.project.checkpoint_once (t.id + "dur", _("Transition Duration"));
                    t.duration = ctl.seq.snap ((int64) (dur.value * Tc.SECOND));
                    ctl.project.commit ();
                    editing = false;
                });
                exp.add_row (dur);
                exp.add_row (choice (_("Alignment"), null, { _("End at Cut"), _("Centre on Cut"), _("Start at Cut") }, t.align + 1, (sel) => change (_("Transition Alignment"), () => { t.align = (int) sel - 1; })));
                string[] dirs = { "left", "right", "up", "down" };
                int di = 0;
                for (int i = 0; i < dirs.length; i++) if (dirs[i] == t.direction) di = i;
                exp.add_row (choice (_("Direction"), null, { _("Left"), _("Right"), _("Up"), _("Down") }, di, (sel) => change (_("Transition Direction"), () => { t.direction = dirs[sel]; })));
                var colour_row = new ActionRow (_("Colour"), _("For Dip to Colour"));
                var cb = new ColorDialogButton (new ColorDialog ());
                var rgba = Gdk.RGBA ();
                rgba.parse (t.color.length == 9 ? t.color.substring (0, 7) : t.color);
                cb.rgba = rgba;
                cb.valign = Align.CENTER;
                cb.notify["rgba"].connect (() => change (_("Transition Colour"), () => { t.color = hex_of (button_rgba (cb)); }));
                colour_row.add_suffix (cb);
                exp.add_row (colour_row);
                exp.add_row (Rows.remove (_("Remove Transition"), () => {
                    change (_("Remove Transition"), () => { ctl.seq.transitions.remove (t); });
                    rebuild (true);
                }));
                g.add_row (exp);
            }
            g.add_row (Rows.action (_("Add Transition at Start"), null, () => add_transition (c, false)));
            g.add_row (Rows.action (_("Add Transition at End"), null, () => add_transition (c, true)));
            content.append (g);
        }

        void add_transition (Clip c, bool at_end) {
            try {
                var track = ctl.seq.track (c.track);
                string kind = track != null && track.kind == TrackKind.AUDIO ? "dissolve" : "dissolve";
                double seconds = ((MontageApp) GLib.Application.get_default ()).get_int ("transition-frames", 25);
                ctl.edits.add_transition (c.id, at_end, kind, Tc.from_frames ((int64) seconds, ctl.seq.fps_n, ctl.seq.fps_d), 0);
                rebuild (true);
            } catch (Error e) {
                ctl.say (e.message);
            }
        }

        public static Gdk.RGBA button_rgba (ColorDialogButton b) {
            var v = Value (typeof (Gdk.RGBA));
            b.get_property ("rgba", ref v);
            Gdk.RGBA* c = (Gdk.RGBA*) v.get_boxed ();
            return c != null ? *c : Gdk.RGBA ();
        }

        public static string hex_of (Gdk.RGBA c) {
            return "#%02x%02x%02x%02x".printf ((int) (c.red * 255 + 0.5), (int) (c.green * 255 + 0.5), (int) (c.blue * 255 + 0.5), (int) (c.alpha * 255 + 0.5));
        }

        public static Gdk.RGBA rgba_of (string hex) {
            float r, g, b, a;
            VideoFx.parse_color (hex, out r, out g, out b, out a);
            var c = Gdk.RGBA ();
            c.red = r; c.green = g; c.blue = b; c.alpha = a;
            return c;
        }

        void build_effects (Clip c, bool audio) {
            var g = new PreferencesGroup ();
            g.title = _("Effects");
            for (int i = 0; i < c.effects.size; i++) {
                var e = c.effects[i];
                int index = i;
                var info = Catalog.find (e.type);
                if (info == null) continue;
                if (!audio && info.audio) continue;
                if (audio && !info.audio) continue;
                var exp = new ExpanderRow (info.label, info.category);
                var on = new SwitchRow (_("Enabled"), null, e.enabled);
                on.switch_btn.notify["active"].connect (() => change (_("Effect"), () => { e.enabled = on.active; }));
                exp.add_row (on);
                foreach (var spec in info.params) exp.add_row (effect_row (c, e, spec));
                foreach (var ts in info.texts) {
                    if (ts.kind == "hidden" || ts.kind == "curve" || ts.kind == "hue-curve" || ts.kind == "path") continue;
                    var tspec = ts;
                    if (ts.kind == "file") {
                        var row = new ActionRow (ts.label, e.params.text (ts.name) != "" ? Path.get_basename (e.params.text (ts.name)) : _("None chosen"));
                        var choose = new Button.with_label (_("Choose…"));
                        choose.valign = Align.CENTER;
                        choose.clicked.connect (() => {
                            var dialog = new FileDialog ();
                            var filter = new FileFilter ();
                            filter.name = _("LUT Files");
                            filter.add_suffix ("cube");
                            filter.add_suffix ("3dl");
                            var filters = new GLib.ListStore (typeof (FileFilter));
                            filters.append (filter);
                            dialog.filters = filters;
                            dialog.open.begin (get_root () as Gtk.Window, null, (o, r) => {
                                try {
                                    var f = dialog.open.end (r);
                                    change (_("LUT"), () => { e.params.texts[tspec.name] = f.get_path (); });
                                    rebuild (true);
                                } catch (Error err) {
                                }
                            });
                        });
                        row.add_suffix (choose);
                        exp.add_row (row);
                    } else if (ts.kind == "color") {
                        var row = new ActionRow (ts.label);
                        var cb = new ColorDialogButton (new ColorDialog ());
                        cb.rgba = rgba_of (e.params.text (ts.name, ts.fallback));
                        cb.valign = Align.CENTER;
                        cb.notify["rgba"].connect (() => change (ts.label, () => { e.params.texts[tspec.name] = hex_of (button_rgba (cb)); }));
                        row.add_suffix (cb);
                        exp.add_row (row);
                    } else if (ts.kind == "choice") {
                        int sel = 0;
                        for (int k = 0; k < ts.choices.length; k++) if (ts.choices[k] == e.params.text (ts.name, ts.fallback)) sel = k;
                        exp.add_row (choice (ts.label, null, ts.choices, sel, (picked) => change (tspec.label, () => { e.params.texts[tspec.name] = tspec.choices[picked]; })));
                    } else if (ts.kind == "text") {
                        var row = new EntryRow (ts.label);
                        row.text = e.params.text (ts.name);
                        row.entry_activated.connect (() => change (tspec.label, () => { e.params.texts[tspec.name] = row.text; }));
                        exp.add_row (row);
                    }
                }
                var order = new ActionRow (_("Order"), _("Effects apply from top to bottom"));
                var up = new Button.from_icon_name ("go-up-symbolic");
                up.add_css_class ("flat");
                up.valign = Align.CENTER;
                up.tooltip_text = _("Move Up");
                up.sensitive = index > 0;
                up.clicked.connect (() => {
                    change (_("Reorder Effects"), () => {
                        var moved = c.effects.remove_at (index);
                        c.effects.insert (index - 1, moved);
                    });
                    rebuild (true);
                });
                var down = new Button.from_icon_name ("go-down-symbolic");
                down.add_css_class ("flat");
                down.valign = Align.CENTER;
                down.tooltip_text = _("Move Down");
                down.sensitive = index < c.effects.size - 1;
                down.clicked.connect (() => {
                    change (_("Reorder Effects"), () => {
                        var moved = c.effects.remove_at (index);
                        c.effects.insert (index + 1, moved);
                    });
                    rebuild (true);
                });
                order.add_suffix (up);
                order.add_suffix (down);
                exp.add_row (order);
                exp.add_row (Rows.remove (_("Remove Effect"), () => {
                    change (_("Remove Effect"), () => { c.effects.remove (e); });
                    rebuild (true);
                }));
                g.add_row (exp);
            }
            var add = new MenuButton ();
            add.label = _("Add Effect");
            add.always_show_arrow = false;
            add.valign = Align.CENTER;
            var pop = new Popover ();
            var list = new Box (Orientation.VERTICAL, 2);
            list.margin_top = list.margin_bottom = list.margin_start = list.margin_end = 6;
            string category = "";
            var all = new Gee.ArrayList<EffectInfo> ();
            all.add_all (Catalog.all ());
            if (!audio) all.add_all (Catalog.installed_filters ());
            foreach (var info in all) {
                if (info.audio != audio) continue;
                if (info.category != category) {
                    category = info.category;
                    var h = new Label (category);
                    h.add_css_class ("heading");
                    h.halign = Align.START;
                    h.margin_top = 6;
                    list.append (h);
                }
                var item = info;
                var b = new Button.with_label (info.label);
                b.add_css_class ("flat");
                b.halign = Align.FILL;
                ((Label) b.child).xalign = 0;
                b.clicked.connect (() => {
                    pop.popdown ();
                    change (_("Add Effect"), () => { c.effects.add (item.create ()); });
                    rebuild (true);
                });
                list.append (b);
            }
            var scroll = new ScrolledWindow ();
            scroll.child = list;
            scroll.set_size_request (280, 420);
            pop.child = scroll;
            add.popover = pop;
            g.add_header_suffix (add);
            if (g.get_rows ().size == 0) g.description = audio ? _("No audio effects on this clip.") : _("No effects on this clip.");
            content.append (g);
        }

        void build_color_clip (Clip c) {
            var g = new PreferencesGroup ();
            g.title = _("Colour Matte");
            var row = new ActionRow (_("Colour"));
            var cb = new ColorDialogButton (new ColorDialog ());
            cb.rgba = rgba_of (c.color);
            cb.valign = Align.CENTER;
            cb.notify["rgba"].connect (() => change (_("Matte Colour"), () => { c.color = hex_of (button_rgba (cb)); }));
            row.add_suffix (cb);
            g.add_row (row);
            content.append (g);
        }

        void build_title (Clip c) {
            if (c.title == null) c.title = new TitleData ();
            var td = c.title;
            var g = new PreferencesGroup ();
            g.title = _("Title");
            var templates = Titles.builtin ();
            var names = new Gee.ArrayList<string> ();
            int current = -1;
            names.add (_("Custom"));
            for (int i = 0; i < templates.size; i++) {
                names.add (templates[i].name);
                if (templates[i].id == td.template_id) current = i;
            }
            g.add_row (choice (_("Template"), _("Lower thirds, titles and credits with editable fields"), names.to_array (), current + 1, (sel) => {
                if (sel == 0) return;
                var t = templates[sel - 1];
                change (_("Title Template"), () => {
                    var keep = new Gee.HashMap<string, string> ();
                    foreach (var e in td.fields.entries) keep[e.key] = e.value;
                    c.title = t.data.copy ();
                    c.title.template_id = t.id;
                    foreach (var e in keep.entries) if (c.title.fields.has_key (e.key)) c.title.fields[e.key] = e.value;
                });
                rebuild (true);
            }));
            foreach (var e in td.fields.entries) {
                string key = e.key;
                var row = new EntryRow (key.substring (0, 1).up () + key.substring (1));
                row.text = e.value;
                row.entry_changed.connect (() => {
                    editing = true;
                    ctl.project.checkpoint_once (c.id + key, _("Title Text"));
                    td.fields[key] = row.text;
                    ctl.project.commit ();
                    editing = false;
                });
                g.add_row (row);
            }
            string[] modes = { "still", "roll", "crawl" };
            int mi = 0;
            for (int i = 0; i < modes.length; i++) if (modes[i] == td.mode) mi = i;
            g.add_row (choice (_("Motion"), null, { _("Still"), _("Rolling Credits"), _("Crawl") }, mi, (sel) => change (_("Title Motion"), () => { td.mode = modes[sel]; })));
            string[] anims = { "none", "fade", "slide-up", "slide-left", "type" };
            string[] anim_names = { _("None"), _("Fade"), _("Slide Up"), _("Slide In"), _("Typewriter") };
            int ai = 0, ao = 0;
            for (int i = 0; i < anims.length; i++) {
                if (anims[i] == td.anim_in) ai = i;
                if (anims[i] == td.anim_out) ao = i;
            }
            g.add_row (choice (_("Animate In"), null, anim_names, ai, (sel) => change (_("Title Animation"), () => { td.anim_in = anims[sel]; })));
            g.add_row (choice (_("Animate Out"), null, anim_names, ao, (sel) => change (_("Title Animation"), () => { td.anim_out = anims[sel]; })));
            g.add_row (Rows.action (_("Save as Template"), null, () => {
                try {
                    Titles.save_template (ctl.project.clip_label (c), td);
                    ctl.say (_("Template saved. It now appears in the template list."));
                } catch (Error e) {
                    ctl.say (e.message);
                }
            }));
            content.append (g);
            for (int i = 0; i < td.layers.size; i++) {
                var l = td.layers[i];
                var lg = new PreferencesGroup ();
                lg.title = _("Text Layer %d").printf (i + 1);
                if (!l.text.contains ("{")) {
                    var text = new EntryRow (_("Text"));
                    text.text = l.text;
                    text.entry_changed.connect (() => {
                        editing = true;
                        ctl.project.checkpoint_once (c.id + "text", _("Title Text"));
                        l.text = text.text;
                        ctl.project.commit ();
                        editing = false;
                    });
                    lg.add_row (text);
                }
                var font_row = new ActionRow (_("Font"));
                var font = new FontDialogButton (new FontDialog ());
                font.font_desc = Pango.FontDescription.from_string (l.font);
                font.valign = Align.CENTER;
                font.notify["font-desc"].connect (() => change (_("Font"), () => {
                    var fd = font.font_desc.copy ();
                    fd.unset_fields (Pango.FontMask.SIZE);
                    l.font = fd.to_string ();
                }));
                font_row.add_suffix (font);
                lg.add_row (font_row);
                lg.add_row (title_spin (c, _("Size"), 6, 600, l.size, (v) => { l.size = v; }));
                lg.add_row (title_color (_("Colour"), l.color, (v) => { l.color = v; }));
                lg.add_row (title_spin (c, _("Outline"), 0, 40, l.outline, (v) => { l.outline = v; }));
                lg.add_row (title_color (_("Outline Colour"), l.outline_color, (v) => { l.outline_color = v; }));
                lg.add_row (title_spin (c, _("Shadow Blur"), 0, 80, l.shadow, (v) => { l.shadow = v; }));
                lg.add_row (title_spin (c, _("Horizontal Position"), -50, 150, l.x, (v) => { l.x = v; }));
                lg.add_row (title_spin (c, _("Vertical Position"), -50, 150, l.y, (v) => { l.y = v; }));
                var box = new SwitchRow (_("Background Box"), null, l.box);
                box.switch_btn.notify["active"].connect (() => change (_("Title Box"), () => { l.box = box.active; }));
                lg.add_row (box);
                string[] aligns = { "left", "center", "right" };
                int al = 1;
                for (int k = 0; k < 3; k++) if (aligns[k] == l.align) al = k;
                lg.add_row (choice (_("Alignment"), null, { _("Left"), _("Centre"), _("Right") }, al, (sel) => change (_("Title Alignment"), () => { l.align = aligns[sel]; })));
                content.append (lg);
            }
        }

        public delegate void DoubleSetter (double v);
        public delegate void TextSetter (string v);

        SpinRow title_spin (Clip c, string label, double min, double max, double value, owned DoubleSetter setter) {
            var row = new SpinRow (label, null, min, max, 1, value);
            row.spin_btn.value_changed.connect (() => {
                editing = true;
                ctl.project.checkpoint_once (c.id + label, label);
                setter (row.value);
                ctl.project.commit ();
                editing = false;
            });
            return row;
        }

        ActionRow title_color (string label, string value, owned TextSetter setter) {
            var row = new ActionRow (label);
            var cb = new ColorDialogButton (new ColorDialog ());
            cb.rgba = rgba_of (value);
            cb.valign = Align.CENTER;
            cb.notify["rgba"].connect (() => change (label, () => { setter (hex_of (button_rgba (cb))); }));
            row.add_suffix (cb);
            return row;
        }

        void build_subtitle (Clip c) {
            var g = new PreferencesGroup ();
            g.title = _("Caption");
            var text = new EntryRow (_("Text"));
            text.text = c.text;
            text.entry_changed.connect (() => {
                editing = true;
                ctl.project.checkpoint_once (c.id + "caption", _("Caption Text"));
                c.text = text.text;
                ctl.project.commit ();
                editing = false;
            });
            g.add_row (text);
            g.add_row (title_color (_("Colour"), c.params.text ("color", "#ffffffff"), (v) => { c.params.texts["color"] = v; }));
            string[] positions = { "bottom", "middle", "top" };
            int pi = 0;
            for (int i = 0; i < 3; i++) if (positions[i] == c.params.text ("position", "bottom")) pi = i;
            g.add_row (choice (_("Position"), null, { _("Bottom"), _("Middle"), _("Top") }, pi, (sel) => change (_("Caption Position"), () => { c.params.texts["position"] = positions[sel]; })));
            var box = new SwitchRow (_("Background Box"), null, c.params.text ("box", "false") == "true");
            box.switch_btn.notify["active"].connect (() => change (_("Caption Box"), () => { c.params.texts["box"] = box.active ? "true" : "false"; }));
            g.add_row (box);
            var size = new SpinRow (_("Size"), null, 12, 200, 1, double.parse (c.params.text ("size", "48")));
            size.spin_btn.value_changed.connect (() => {
                editing = true;
                ctl.project.checkpoint_once (c.id + "size", _("Caption Size"));
                c.params.texts["size"] = "%g".printf (size.value);
                ctl.project.commit ();
                editing = false;
            });
            g.add_row (size);
            content.append (g);
        }

        void build_multicam (Clip c) {
            var m = ctl.project.find_media (c.media);
            if (m == null) return;
            var g = new PreferencesGroup ();
            g.title = _("Multicamera");
            g.description = _("Pick an angle, or press its number key while the Program monitor shows the angles, to cut at the playhead.");
            for (int i = 0; i < m.angles.size; i++) {
                int angle = i;
                g.add_row (Rows.action ("%d  %s".printf (i + 1, m.angles[i].name), null, () => MulticamOps.cut (ctl, c, ctl.program.position, angle)));
            }
            foreach (var cut in c.cuts) {
                var row = new ActionRow (Tc.format (c.position + cut.time, ctl.seq.fps_n, ctl.seq.fps_d), m.angles.size > cut.angle ? m.angles[cut.angle].name : "");
                g.add_row (row);
            }
            content.append (g);
        }

        void build_composition (Clip c) {
            var g = new PreferencesGroup ();
            g.title = _("Linked Composition");
            var row = new ActionRow (File.new_for_uri (c.composition).get_basename () ?? "", _("Updates when the file is saved in Keyframe"));
            var open = new Button.with_label (_("Open in Keyframe"));
            open.valign = Align.CENTER;
            open.clicked.connect (() => {
                try {
                    AppInfo.launch_default_for_uri (c.composition, null);
                } catch (Error e) {
                    ctl.say (e.message);
                }
            });
            row.add_suffix (open);
            g.add_row (row);
            content.append (g);
        }

        void build_media (MediaItem m) {
            heading (m.name, m.uri.has_prefix ("file://") ? File.new_for_uri (m.uri).get_path () : m.uri);
            var g = new PreferencesGroup ();
            g.title = _("Organise");
            g.add_row (choice (_("Label"), null, { _("None"), _("Red"), _("Orange"), _("Yellow"), _("Green"), _("Violet"), _("Cyan"), _("Pink") }, m.label, (sel) => change (_("Label"), () => { m.label = (int) sel; })));
            var rating = new SpinRow (_("Rating"), _("Stars"), 0, 5, 1, m.rating);
            rating.spin_btn.value_changed.connect (() => change (_("Rating"), () => { m.rating = (int) rating.value; }));
            g.add_row (rating);
            var tags = new EntryRow (_("Tags"));
            tags.text = string.joinv (", ", m.tags.to_array ());
            tags.entry_activated.connect (() => change (_("Tags"), () => {
                m.tags.clear ();
                foreach (var t in tags.text.split (",")) if (t.strip () != "") m.tags.add (t.strip ());
            }));
            g.add_row (tags);
            var notes = new EntryRow (_("Notes"));
            notes.text = m.notes;
            notes.entry_activated.connect (() => change (_("Notes"), () => { m.notes = notes.text; }));
            g.add_row (notes);
            var bins = new Gee.ArrayList<string> ();
            var bin_ids = new Gee.ArrayList<string> ();
            bins.add (_("Unsorted"));
            bin_ids.add ("");
            foreach (var b in ctl.project.bins) {
                bins.add (b.name);
                bin_ids.add (b.id);
            }
            g.add_row (choice (_("Bin"), null, bins.to_array (), int.max (0, bin_ids.index_of (m.bin)), (sel) => change (_("Move to Bin"), () => { m.bin = bin_ids[(int) sel]; })));
            content.append (g);
            var meta = new PreferencesGroup ();
            meta.title = _("Metadata");
            foreach (var e in m.metadata.entries) {
                string key = e.key;
                var row = new EntryRow (key.substring (0, 1).up () + key.substring (1));
                row.text = e.value;
                row.entry_activated.connect (() => change (_("Metadata"), () => { m.metadata[key] = row.text; }));
                meta.add_row (row);
            }
            foreach (var key in new string[] { "scene", "take", "camera angle", "description" }) {
                if (m.metadata.has_key (key)) continue;
                string k = key;
                var row = new EntryRow (k.substring (0, 1).up () + k.substring (1));
                row.entry_activated.connect (() => change (_("Metadata"), () => { if (row.text != "") m.metadata[k] = row.text; }));
                meta.add_row (row);
            }
            content.append (meta);
            var media = new PreferencesGroup ();
            media.title = _("Playback");
            var proxy = new ActionRow (_("Proxy"), m.proxy_state == "ready" ? _("Ready, used for smooth editing") : (m.proxy_state == "none" ? _("Not created") : m.proxy_state));
            var make = new Button.with_label (_("Create Proxy"));
            make.valign = Align.CENTER;
            make.sensitive = m.has_video && !m.still;
            make.clicked.connect (() => ctl.proxies.request (m));
            proxy.add_suffix (make);
            media.add_row (proxy);
            var marks = new ActionRow (_("Source Marks"), m.mark_in >= 0 || m.mark_out >= 0 ? "%s - %s".printf (Tc.clock (int64.max (0, m.mark_in)), Tc.clock (m.mark_out >= 0 ? m.mark_out : m.duration)) : _("Whole clip"));
            media.add_row (marks);
            content.append (media);
        }
    }

    namespace Delegates {
        public delegate void Action ();
    }

    public class ChoiceRow : SelectionRow {
        string[] labels;
        uint _index;

        public uint index {
            get { return _index; }
            set {
                if (labels.length == 0) return;
                _index = value.clamp (0, labels.length - 1);
                current_value = labels[_index];
            }
        }

        public ChoiceRow (string title, string? subtitle, string[] labels, uint index = 0) {
            base (title, labels, labels.length > 0 ? labels[index.clamp (0, labels.length - 1)] : "");
            this.labels = labels;
            _index = labels.length > 0 ? index.clamp (0, labels.length - 1) : 0;
            if (subtitle != null) this.subtitle = subtitle;
            selected.connect ((item) => {
                for (int i = 0; i < this.labels.length; i++) {
                    if (this.labels[i] == item) {
                        _index = i;
                        notify_property ("index");
                        return;
                    }
                }
            });
        }
    }

    namespace Rows {
        public delegate void IndexChanged (int index);

        public SelectionRow choice (string title, string? subtitle, string[] labels, int selected, owned IndexChanged changed) {
            int current = labels.length > 0 ? selected.clamp (0, labels.length - 1) : 0;
            var row = new SelectionRow (title, labels, labels.length > 0 ? labels[current] : "");
            if (subtitle != null) row.subtitle = subtitle;
            string[] copy = labels;
            row.selected.connect ((item) => {
                for (int i = 0; i < copy.length; i++) {
                    if (copy[i] == item) {
                        changed (i);
                        return;
                    }
                }
            });
            return row;
        }

        public ActionRow action (string title, string? subtitle, owned Delegates.Action run) {
            var row = new ActionRow (title, subtitle);
            var arrow = new Image.from_icon_name ("go-next-symbolic");
            arrow.add_css_class ("dim-label");
            row.add_suffix (arrow);
            row.activated.connect (() => run ());
            return row;
        }

        public ActionRow remove (string title, owned Delegates.Action run) {
            var row = new ActionRow (title);
            row.add_css_class ("montage-remove-row");
            var trash = new Button.from_icon_name ("user-trash-symbolic");
            trash.add_css_class ("flat");
            trash.add_css_class ("destructive-action");
            trash.valign = Align.CENTER;
            trash.tooltip_text = title;
            trash.clicked.connect (() => run ());
            row.add_suffix (trash);
            row.activated.connect (() => run ());
            return row;
        }

    }
    public class InspectorPanel : Widget {
        public Stack stack { get; private set; }
        public SidebarTabs tabs { get; private set; }
        Box box;
        int target;

        public InspectorPanel (int width) {
            target = width;
            add_css_class ("sx-inspector");
            hexpand = false;
            overflow = Overflow.HIDDEN;
            box = new Box (Orientation.VERTICAL, 0);
            box.set_parent (this);
            stack = new Stack ();
            stack.vexpand = true;
            stack.transition_type = StackTransitionType.CROSSFADE;
            tabs = new SidebarTabs ();
            tabs.homogeneous = false;
            tabs.reserve_bubble_band = true;
            tabs.selected.connect ((name) => {
                if (stack.visible_child_name != name) stack.visible_child_name = name;
            });
            stack.notify["visible-child-name"].connect (() => {
                if (stack.visible_child_name != null) tabs.set_active (stack.visible_child_name);
            });
            tabs.margin_start = 14;
            tabs.margin_end = 14;
            box.append (tabs);
            box.append (stack);
        }

        public void add_page (string name, string title, Widget content) {
            var s = new ScrolledWindow ();
            s.hscrollbar_policy = PolicyType.NEVER;
            s.vexpand = true;
            content.margin_start = 14;
            content.margin_end = 14;
            content.margin_top = 4;
            content.margin_bottom = 24;
            s.child = content;
            stack.add_titled (s, name, title);
            tabs.add_option (name, title);
            tabs.get_last_child ().hexpand = true;
        }

        public string page {
            owned get {
                return stack.visible_child_name;
            }
            set {
                stack.visible_child_name = value;
            }
        }

        public override void dispose () {
            if (box != null) box.unparent ();
            box = null;
            base.dispose ();
        }

        public override SizeRequestMode get_request_mode () {
            return SizeRequestMode.HEIGHT_FOR_WIDTH;
        }

        public override void measure (Orientation o, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            minimum_baseline = natural_baseline = -1;
            if (o == Orientation.HORIZONTAL) {
                minimum = natural = target;
                return;
            }
            box.measure (o, target, out minimum, out natural, null, null);
        }

        public override void size_allocate (int width, int height, int baseline) {
            box.allocate (int.max (width, 0), height, baseline, null);
        }
    }
}
