using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Montage {
    public class Meter : DrawingArea {
        public double level;
        public double peak_hold;

        public Meter () {
            add_css_class ("montage-meter");
            set_size_request (8, 60);
            set_draw_func ((a, cr, w, h) => {
                var fg = a.get_color ();
                cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.1);
                cr.paint ();
                double db = Singularity.Audio.gain_to_db (level);
                double k = ((db + 60) / 66).clamp (0, 1);
                var grad = new Cairo.Pattern.linear (0, h, 0, 0);
                grad.add_color_stop_rgb (0, 0.2, 0.75, 0.35);
                grad.add_color_stop_rgb (0.75, 0.9, 0.8, 0.2);
                grad.add_color_stop_rgb (1, 0.9, 0.2, 0.2);
                cr.set_source (grad);
                cr.rectangle (0, h * (1 - k), w, h * k);
                cr.fill ();
                double hold = ((Singularity.Audio.gain_to_db (peak_hold) + 60) / 66).clamp (0, 1);
                cr.set_source_rgb (1, 1, 1);
                cr.rectangle (0, h * (1 - hold), w, 1.5);
                cr.fill ();
            });
        }

        public void push (double value) {
            level = level * 0.6 + value * 0.4;
            if (value > peak_hold) peak_hold = value;
            else peak_hold *= 0.985;
            queue_draw ();
        }
    }

    public class ChannelStrip : Box {
        public signal void picked ();
        public Meter? meter;
        Label value_label;

        public ChannelStrip (string name, bool selected) {
            Object (orientation: Orientation.VERTICAL, spacing: 6);
            add_css_class ("sx-channel-strip");
            if (selected) add_css_class ("selected");
            set_size_request (96, -1);
            var title = new Label (name);
            title.add_css_class ("heading");
            title.ellipsize = Pango.EllipsizeMode.END;
            title.max_width_chars = 8;
            append (title);
            var click = new GestureClick ();
            click.pressed.connect (() => picked ());
            add_controller (click);
        }

        public Scale add_pan (double value) {
            var pan = new Scale.with_range (Orientation.HORIZONTAL, -100, 100, 1);
            pan.add_css_class ("sx-strip-pan");
            pan.draw_value = false;
            pan.set_value (value);
            pan.add_mark (0, PositionType.BOTTOM, null);
            pan.tooltip_text = _("Pan");
            pan.update_property (AccessibleProperty.LABEL, _("Pan"), -1);
            pan.valign = Align.CENTER;
            var holder = new Box (Orientation.HORIZONTAL, 0);
            holder.set_size_request (-1, 26);
            pan.hexpand = true;
            holder.append (pan);
            append (holder);
            return pan;
        }

        public void add_pan_placeholder () {
            var pan = add_pan (0);
            pan.opacity = 0;
            pan.can_target = false;
            pan.can_focus = false;
        }

        public Scale add_fader (double value, Widget[] meters) {
            var mid = new Box (Orientation.HORIZONTAL, 4);
            mid.halign = Align.CENTER;
            var fader = new Scale.with_range (Orientation.VERTICAL, -60, 12, 0.5);
            fader.inverted = true;
            fader.draw_value = false;
            fader.set_value (value);
            fader.set_size_request (-1, 168);
            fader.add_mark (0, PositionType.LEFT, "0");
            fader.add_mark (-12, PositionType.LEFT, null);
            fader.add_mark (-36, PositionType.LEFT, null);
            fader.update_property (AccessibleProperty.LABEL, _("Volume"), -1);
            mid.append (fader);
            foreach (var m in meters) {
                m.margin_top = m.margin_bottom = 9;
                mid.append (m);
            }
            append (mid);
            value_label = new Label ("");
            value_label.add_css_class ("caption");
            value_label.add_css_class ("numeric");
            append (value_label);
            show_value (value);
            fader.value_changed.connect (() => show_value (fader.get_value ()));
            return fader;
        }

        void show_value (double db) {
            value_label.label = db <= -59.9 ? _("Off") : "%+.1f dB".printf (db);
        }

        public Box add_toggle_row () {
            var toggles = new Box (Orientation.HORIZONTAL, 4);
            toggles.halign = Align.CENTER;
            append (toggles);
            return toggles;
        }

        public static ToggleButton toggle (Box row, string text, string tooltip, string kind, bool active) {
            var b = new ToggleButton.with_label (text);
            b.tooltip_text = tooltip;
            b.add_css_class ("flat");
            b.add_css_class ("sx-strip-toggle");
            b.add_css_class (kind);
            b.active = active;
            row.append (b);
            return b;
        }

        public delegate void Picked (int index);

        public Button add_menu (string[] labels, int current, string tooltip, owned Picked picked) {
            var b = new Button ();
            b.add_css_class ("flat");
            b.add_css_class ("sx-strip-menu");
            b.tooltip_text = tooltip;
            var box = new Box (Orientation.HORIZONTAL, 2);
            var label = new Label (labels[current.clamp (0, labels.length - 1)]);
            label.ellipsize = Pango.EllipsizeMode.END;
            label.hexpand = true;
            label.add_css_class ("caption");
            box.append (label);
            var arrow = new Image.from_icon_name ("pan-down-symbolic");
            arrow.pixel_size = 12;
            box.append (arrow);
            b.child = box;
            string[] items = labels;
            b.clicked.connect (() => {
                var menu = new ContextMenu (b);
                for (int i = 0; i < items.length; i++) {
                    int index = i;
                    menu.add_item (items[i], index == current ? "object-select-symbolic" : null, () => picked (index));
                }
                menu.popup ();
            });
            append (b);
            return b;
        }
    }

    public class MixerPanel : Box {
        MontageWindow w;
        Controller ctl;
        Box strips = new Box (Orientation.HORIZONTAL, 0);
        Box details = new Box (Orientation.VERTICAL, 12);
        Gee.HashMap<string, Meter> meters = new Gee.HashMap<string, Meter> ();
        Meter master_left = new Meter ();
        Meter master_right = new Meter ();
        ActionRow loudness_row;
        public bool automation;
        string selected = "";
        uint timer;

        public MixerPanel (MontageWindow w) {
            Object (orientation: Orientation.VERTICAL, spacing: 12);
            this.w = w;
            ctl = w.ctl;
            var group = new PreferencesGroup ();
            group.title = _("Mixer");
            var hscroll = new ScrolledWindow ();
            hscroll.vscrollbar_policy = PolicyType.NEVER;
            hscroll.propagate_natural_height = true;
            hscroll.child = strips;
            group.add_row (hscroll);
            var auto = new SwitchRow (_("Write Automation"), _("Fader moves during playback write keyframes"), false);
            auto.switch_btn.notify["active"].connect (() => automation = auto.active);
            group.add_row (auto);
            append (group);
            var loud = new PreferencesGroup ();
            loud.title = _("Loudness");
            loudness_row = new ActionRow (_("Measured"), _("Play the sequence to measure its loudness"));
            loud.add_row (loudness_row);
            double[] targets = { -14, -16, -23, -24 };
            int target_index = 0;
            for (int i = 0; i < 4; i++) if (targets[i] == ctl.seq.loudness_target) target_index = i;
            loud.add_row (Rows.choice (_("Export Target"), null, { _("Web and Social, -14 LUFS"), _("Podcast, -16 LUFS"), _("Broadcast EBU R128, -23 LUFS"), _("Broadcast ATSC A/85, -24 LUFS") }, target_index, (i) => {
                ctl.project.checkpoint (_("Loudness Target"));
                ctl.seq.loudness_target = targets[i];
                ctl.project.commit ();
            }));
            loud.add_row (Rows.action (_("Match Clip Loudness"), _("Bring the selected audio clips to the export target"), () => w.activate_action ("win.normalize", null)));
            append (loud);
            var tools = new PreferencesGroup ();
            tools.title = _("Sound");
            tools.add_row (Rows.action (_("Duck Music"), _("Lower music clips while dialogue plays"), () => w.activate_action ("win.auto-duck", null)));
            tools.add_row (Rows.action (_("Record Voiceover"), _("Record from the microphone at the playhead"), () => w.activate_action ("win.record", null)));
            tools.add_row (Rows.action (_("Edit Sound in Wave"), _("Mix the sequence in Wave and bring it back"), () => w.activate_action ("win.sound-in-wave", null)));
            append (tools);
            append (details);
            ctl.project.changed.connect (() => {
                if (get_mapped ()) rebuild ();
            });
            map.connect (() => {
                rebuild ();
                timer = Timeout.add (50, update_meters);
            });
            unmap.connect (() => {
                if (timer != 0) Source.remove (timer);
                timer = 0;
            });
        }

        bool update_meters () {
            var mixer = ctl.program.live_mixer;
            if (mixer != null && ctl.program.playing) {
                foreach (var e in meters.entries) {
                    float? p = mixer.track_peaks[e.key];
                    e.value.push (p != null ? p : 0);
                }
                master_left.push (mixer.peak_left);
                master_right.push (mixer.peak_right);
                if (mixer.meter != null) loudness_row.subtitle = _("Momentary %.1f, short term %.1f, integrated %.1f LUFS").printf (mixer.meter.momentary, mixer.meter.short_term, mixer.meter.integrated);
            } else {
                foreach (var m in meters.values) m.push (0);
                master_left.push (0);
                master_right.push (0);
            }
            return Source.CONTINUE;
        }

        Widget strip (string id, string name, Singularity.Keyframes.AnimatedValue volume, Singularity.Keyframes.AnimatedValue pan, Track? track, Bus? bus) {
            var cs = new ChannelStrip (name, id == selected);
            cs.picked.connect (() => {
                if (selected == id) return;
                selected = id;
                Idle.add (() => {
                    rebuild ();
                    return Source.REMOVE;
                });
            });
            if (id != "master") {
                var pan_scale = cs.add_pan (pan.at (ctl.playhead));
                pan_scale.value_changed.connect (() => {
                    ctl.project.checkpoint_once (id + "pan", _("Pan"));
                    write (pan, pan_scale.get_value ());
                    ctl.project.commit ();
                });
            } else {
                cs.add_pan_placeholder ();
            }
            Widget[] meter_widgets;
            if (track != null) {
                var m = new Meter ();
                meters[track.id] = m;
                meter_widgets = { m };
            } else if (bus == null) {
                if (master_left.get_parent () != null) ((Box) master_left.get_parent ()).remove (master_left);
                if (master_right.get_parent () != null) ((Box) master_right.get_parent ()).remove (master_right);
                meter_widgets = { master_left, master_right };
            } else {
                meter_widgets = {};
            }
            var fader = cs.add_fader (volume.at (ctl.playhead), meter_widgets);
            fader.value_changed.connect (() => {
                ctl.project.checkpoint_once (id + "vol", _("Volume"));
                write (volume, fader.get_value ());
                ctl.project.commit ();
            });
            var toggles = cs.add_toggle_row ();
            if (track != null) {
                var mute = ChannelStrip.toggle (toggles, "M", _("Mute"), "mute", track.muted);
                mute.toggled.connect (() => {
                    ctl.project.checkpoint (_("Mute"));
                    track.muted = mute.active;
                    ctl.project.commit ();
                });
                var solo = ChannelStrip.toggle (toggles, "S", _("Solo"), "solo", track.solo);
                solo.toggled.connect (() => {
                    ctl.project.checkpoint (_("Solo"));
                    track.solo = solo.active;
                    ctl.project.commit ();
                });
                var routes = new Gee.ArrayList<string> ();
                var route_ids = new Gee.ArrayList<string> ();
                routes.add (_("Master"));
                route_ids.add ("master");
                foreach (var b in ctl.seq.buses) {
                    routes.add (b.name);
                    route_ids.add (b.id);
                }
                cs.add_menu (routes.to_array (), int.max (0, route_ids.index_of (track.bus)), _("Output"), (i) => {
                    if (track.bus == route_ids[i]) return;
                    ctl.project.checkpoint (_("Route"));
                    track.bus = route_ids[i];
                    ctl.project.commit ();
                });
                string[] roles = { "", "dialogue", "music", "effects" };
                int role_index = 0;
                for (int i = 0; i < 4; i++) if (roles[i] == track.role) role_index = i;
                cs.add_menu ({ _("No Role"), _("Dialogue"), _("Music"), _("Effects") }, role_index, _("Role for automatic ducking"), (i) => {
                    if (track.role == roles[i]) return;
                    ctl.project.checkpoint (_("Track Role"));
                    track.role = roles[i];
                    ctl.project.commit ();
                });
            }
            return cs;
        }

        void write (Singularity.Keyframes.AnimatedValue v, double value) {
            if (automation && ctl.program.playing) v.set_key (ctl.program.position, value);
            else v.set_at (ctl.program.position, value);
        }

        void clear (Box b) {
            Widget? x;
            while ((x = b.get_first_child ()) != null) b.remove (x);
        }

        public void rebuild () {
            if (ctl.program.playing && automation) return;
            clear (strips);
            meters.clear ();
            foreach (var t in ctl.seq.tracks_of (TrackKind.AUDIO)) strips.append (strip ("track:" + t.id, t.name, t.volume, t.pan, t, null));
            foreach (var b in ctl.seq.buses) strips.append (strip ("bus:" + b.id, b.name, b.volume, b.pan, null, b));
            var dummy_pan = new Singularity.Keyframes.AnimatedValue (0);
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            strips.append (spacer);
            var master = strip ("master", _("Master"), ctl.seq.master_volume, dummy_pan, null, null);
            master.add_css_class ("master");
            strips.append (master);
            clear (details);
            Gee.List<Effect>? effects = null;
            string title = "";
            if (selected.has_prefix ("track:")) {
                var t = ctl.seq.track (selected.substring (6));
                if (t != null) {
                    effects = t.effects;
                    title = t.name;
                }
            } else if (selected.has_prefix ("bus:")) {
                var b = ctl.seq.bus (selected.substring (4));
                if (b != null) {
                    effects = b.effects;
                    title = b.name;
                }
            } else if (selected == "master") {
                effects = ctl.seq.master_effects;
                title = _("Master");
            }
            if (effects == null) return;
            var group = new PreferencesGroup ();
            group.title = _("%s Effects").printf (title);
            foreach (var item in effects) {
                var e = item;
                var info = Catalog.find (e.type);
                if (info == null) continue;
                var exp = new ExpanderRow (info.label, null);
                foreach (var spec in info.params) {
                    var sp = spec;
                    exp.add_row (new ParamRow (ctl, e.id + sp.name, sp.label, sp, () => e.params.ensure (sp.name, sp.fallback), () => ctl.program.position));
                }
                if (e.type == "audio.eq") {
                    var curve = new DrawingArea ();
                    curve.set_size_request (-1, 90);
                    curve.set_draw_func ((a, cr, cw, ch) => draw_eq (cr, cw, ch, e));
                    exp.add_row (curve);
                }
                exp.add_row (Rows.remove (_("Remove Effect"), () => {
                    ctl.project.checkpoint (_("Remove Effect"));
                    effects.remove (e);
                    ctl.project.commit ();
                }));
                group.add_row (exp);
            }
            var add = new MenuButton ();
            add.label = _("Add Effect");
            add.valign = Align.CENTER;
            var pop = new Popover ();
            var list = new Box (Orientation.VERTICAL, 2);
            list.margin_top = list.margin_bottom = list.margin_start = list.margin_end = 6;
            foreach (var info in Catalog.all ()) {
                if (!info.audio) continue;
                var item = info;
                var b = new Button.with_label (info.label);
                b.add_css_class ("flat");
                b.clicked.connect (() => {
                    pop.popdown ();
                    ctl.project.checkpoint (_("Add Effect"));
                    effects.add (item.create ());
                    ctl.project.commit ();
                });
                list.append (b);
            }
            pop.child = list;
            add.popover = pop;
            group.add_header_suffix (add);
            if (effects.size == 0) group.description = _("No effects on this channel.");
            details.append (group);
        }

        void draw_eq (Cairo.Context cr, int w, int h, Effect e) {
            cr.set_source_rgb (0.08, 0.08, 0.09);
            cr.paint ();
            var proc = new Singularity.Audio.Equalizer (48000, 2);
            var p = e.params;
            int64 k = ctl.program.position;
            double hp = p.get_value ("highpass", k, 0), lp = p.get_value ("lowpass", k, 0);
            if (hp > 0) proc.bands.add (new Singularity.Audio.EqBand (Singularity.Audio.FilterType.HIGH_PASS, hp));
            proc.bands.add (new Singularity.Audio.EqBand (Singularity.Audio.FilterType.LOW_SHELF, p.get_value ("low-freq", k, 120), p.get_value ("low-gain", k, 0)));
            proc.bands.add (new Singularity.Audio.EqBand (Singularity.Audio.FilterType.PEAK, p.get_value ("mid-freq", k, 1000), p.get_value ("mid-gain", k, 0), p.get_value ("mid-q", k, 1)));
            proc.bands.add (new Singularity.Audio.EqBand (Singularity.Audio.FilterType.HIGH_SHELF, p.get_value ("high-freq", k, 8000), p.get_value ("high-gain", k, 0)));
            if (lp > 0) proc.bands.add (new Singularity.Audio.EqBand (Singularity.Audio.FilterType.LOW_PASS, lp));
            proc.update ();
            cr.set_source_rgba (1, 1, 1, 0.15);
            cr.move_to (0, h / 2.0);
            cr.line_to (w, h / 2.0);
            cr.stroke ();
            cr.set_source_rgb (1, 0.8, 0.3);
            cr.set_line_width (2);
            for (int x = 0; x <= w; x++) {
                double f = 20 * Math.pow (1000, (double) x / w);
                double db = proc.response_db (f).clamp (-24, 24);
                double y = h / 2.0 - db / 24 * h / 2;
                if (x == 0) cr.move_to (x, y);
                else cr.line_to (x, y);
            }
            cr.stroke ();
        }
    }
}
