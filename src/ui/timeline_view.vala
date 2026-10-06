using Gtk;

namespace Singularity.Apps.Montage {
    public class TimelineView : Box {
        public const double HEADER = 176;
        public const double RULER = 34;
        Controller ctl;
        DrawingArea area = new DrawingArea ();
        Adjustment hadj = new Adjustment (0, 0, 100, 10, 50, 10);
        public double pixels_per_second = 60;
        public signal void context_menu (double x, double y);
        public signal void trim_preview (int64 left, int64 right, bool active);
        public signal void edit_failed (string message);
        string drag_kind = "";
        string? drag_clip;
        double drag_x0;
        double drag_y0;
        double drag_dx;
        double drag_dy;
        int64 drag_time;
        int drag_key = -1;
        double drag_value0;
        Gdk.RGBA fg;
        Gdk.RGBA accent;
        public string? hover_info;

        static string[] LABELS = { "#5e81ac", "#bf616a", "#d08770", "#ebcb8b", "#a3be8c", "#b48ead", "#88c0d0", "#e5739f" };

        public TimelineView (Controller ctl) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.ctl = ctl;
            area.set_draw_func (draw);
            area.hexpand = true;
            area.focusable = true;
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vscrollbar_policy = PolicyType.AUTOMATIC;
            scroll.vexpand = true;
            scroll.child = area;
            append (scroll);
            var bar = new Scrollbar (Orientation.HORIZONTAL, hadj);
            append (bar);
            hadj.value_changed.connect (() => area.queue_draw ());
            area.resize.connect ((w, h) => update_extent ());
            ctl.project.changed.connect (() => {
                update_extent ();
                area.queue_draw ();
            });
            ctl.selection_changed.connect (() => area.queue_draw ());
            ctl.program.position_changed.connect ((t) => {
                follow (t);
                area.queue_draw ();
            });
            ctl.media_cache.ready.connect (() => area.queue_draw ());
            ctl.prerender.updated.connect (() => area.queue_draw ());
            var click = new GestureClick ();
            click.button = 0;
            click.pressed.connect (on_press);
            area.add_controller (click);
            var drag = new GestureDrag ();
            drag.drag_begin.connect (on_drag_begin);
            drag.drag_update.connect (on_drag_update);
            drag.drag_end.connect (on_drag_end);
            area.add_controller (drag);
            var motion = new EventControllerMotion ();
            motion.motion.connect ((x, y) => update_cursor (x, y));
            area.add_controller (motion);
            var scroll_ctl = new EventControllerScroll (EventControllerScrollFlags.BOTH_AXES);
            scroll_ctl.scroll.connect ((dx, dy) => {
                var state = scroll_ctl.get_current_event_state ();
                if ((state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    zoom (dy < 0 ? 1.25 : 0.8);
                    return true;
                }
                if (dx != 0 || (state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                    hadj.value = (hadj.value + (dx != 0 ? dx : dy) * 40).clamp (0, hadj.upper - hadj.page_size);
                    return true;
                }
                return false;
            });
            area.add_controller (scroll_ctl);
            var drop = new DropTarget (typeof (string), Gdk.DragAction.COPY);
            drop.drop.connect ((value, x, y) => {
                string id = value.get_string ();
                bool insert = (Gdk.ModifierType.SHIFT_MASK & get_modifiers ()) != 0;
                drop_media (id, x, y, insert);
                return true;
            });
            area.add_controller (drop);
            update_property (AccessibleProperty.LABEL, _("Timeline"), -1);
        }

        Gdk.ModifierType get_modifiers () {
            var display = Gdk.Display.get_default ();
            var seat = display.get_default_seat ();
            var kb = seat != null ? seat.get_keyboard () : null;
            return kb != null ? kb.get_modifier_state () : 0;
        }

        public void zoom (double factor) {
            double center_time = time_at (area.get_width () / 2.0);
            pixels_per_second = (pixels_per_second * factor).clamp (2, 2000);
            update_extent ();
            hadj.value = double.max (0, center_time / Tc.SECOND * pixels_per_second - (area.get_width () - HEADER) / 2);
            area.queue_draw ();
        }

        public void zoom_fit () {
            double width = double.max (100, area.get_width () - HEADER - 20);
            double seconds = double.max (1, (double) ctl.seq.duration / Tc.SECOND);
            pixels_per_second = (width / seconds).clamp (2, 2000);
            hadj.value = 0;
            update_extent ();
            area.queue_draw ();
        }

        void follow (int64 t) {
            if (!ctl.program.playing) return;
            double x = (double) t / Tc.SECOND * pixels_per_second - hadj.value;
            double visible = area.get_width () - HEADER;
            if (x > visible * 0.9 || x < 0) hadj.value = double.max (0, (double) t / Tc.SECOND * pixels_per_second - visible * 0.1);
        }

        void update_extent () {
            double seconds = (double) ctl.seq.duration / Tc.SECOND + 30;
            hadj.upper = seconds * pixels_per_second;
            hadj.page_size = double.max (1, area.get_width () - HEADER);
            hadj.step_increment = 20;
            hadj.page_increment = hadj.page_size * 0.8;
            area.content_height = (int) (RULER + total_height () + 20);
        }

        public Gee.ArrayList<Track> display_tracks () {
            var r = new Gee.ArrayList<Track> ();
            var vids = ctl.seq.tracks_of (TrackKind.VIDEO);
            for (int i = vids.size - 1; i >= 0; i--) r.add (vids[i]);
            r.add_all (ctl.seq.tracks_of (TrackKind.AUDIO));
            r.add_all (ctl.seq.tracks_of (TrackKind.SUBTITLE));
            return r;
        }

        double track_height (Track t) {
            return t.kind == TrackKind.VIDEO ? 66 : (t.kind == TrackKind.AUDIO ? 58 : 34);
        }

        double total_height () {
            double h = 0;
            foreach (var t in display_tracks ()) h += track_height (t);
            return h;
        }

        double track_y (Track t) {
            double y = RULER;
            foreach (var o in display_tracks ()) {
                if (o == t) return y;
                y += track_height (o);
            }
            return y;
        }

        Track? track_at (double y) {
            double top = RULER;
            foreach (var t in display_tracks ()) {
                double h = track_height (t);
                if (y >= top && y < top + h) return t;
                top += h;
            }
            return null;
        }

        public double x_of (int64 t) {
            return HEADER + (double) t / Tc.SECOND * pixels_per_second - hadj.value;
        }

        public int64 time_at (double x) {
            return (int64) (((x - HEADER + hadj.value) / pixels_per_second) * Tc.SECOND);
        }

        Clip? clip_at (double x, double y, out string zone) {
            zone = "";
            var t = track_at (y);
            if (t == null || x < HEADER) return null;
            int64 time = time_at (x);
            foreach (var c in ctl.seq.on_track (t.id)) {
                double x0 = x_of (c.position), x1 = x_of (c.end);
                if (x < x0 - 1 || x > x1 + 1) continue;
                double edge = double.min (8, (x1 - x0) / 4);
                if (x - x0 <= edge) zone = "head";
                else if (x1 - x <= edge) zone = "tail";
                else zone = "body";
                if (time < c.position - Tc.SECOND / 10 || time > c.end + Tc.SECOND / 10) continue;
                return c;
            }
            return null;
        }

        void update_cursor (double x, double y) {
            string zone;
            var c = clip_at (x, y, out zone);
            string name = "default";
            if (ctl.tool == "razor" && c != null) name = "crosshair";
            else if (c != null && (zone == "head" || zone == "tail")) name = "col-resize";
            else if (c != null && (ctl.tool == "slip" || ctl.tool == "slide")) name = "ew-resize";
            else if (c != null) name = "grab";
            area.set_cursor_from_name (name);
        }

        int64 snap (int64 t, Gee.Collection<string>? ignore) {
            if (!ctl.snapping) return ctl.seq.snap (t);
            int64 tolerance = (int64) (8 / pixels_per_second * Tc.SECOND);
            return ctl.seq.snap (ctl.edits.snap_point (t, tolerance, ignore));
        }

        void on_press (GestureClick g, int n, double x, double y) {
            area.grab_focus ();
            uint button = g.get_current_button ();
            var state = g.get_current_event_state ();
            if (y < RULER && x >= HEADER) {
                ctl.seek (ctl.seq.snap (int64.max (0, time_at (x))));
                return;
            }
            if (x < HEADER) {
                header_click (x, y);
                return;
            }
            string zone;
            var c = clip_at (x, y, out zone);
            var tr = track_at (y);
            if (tr != null) ctl.selected_track = tr.id;
            if (button == 3) {
                if (c != null && !ctl.selection.contains (c.id)) ctl.select (c);
                context_menu (x, y);
                return;
            }
            if (c == null) {
                if ((state & Gdk.ModifierType.SHIFT_MASK) == 0) ctl.select (null);
                return;
            }
            if (ctl.tool == "razor") {
                var ids = new Gee.ArrayList<string> ();
                ids.add (c.id);
                try {
                    ctl.edits.split (snap (time_at (x), null), ids);
                } catch (Error e) {
                    edit_failed (e.message);
                }
                return;
            }
            bool add = (state & (Gdk.ModifierType.SHIFT_MASK | Gdk.ModifierType.CONTROL_MASK)) != 0;
            if (add && ctl.selection.contains (c.id)) {
                foreach (var l in ctl.seq.linked (c)) ctl.selection.remove (l.id);
                ctl.selection_changed ();
            } else if (!ctl.selection.contains (c.id) || add) {
                bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;
                if (alt) {
                    if (!add) ctl.selection.clear ();
                    ctl.selection.add (c.id);
                    ctl.selected_track = c.track;
                    ctl.selection_changed ();
                } else {
                    ctl.select (c, add);
                }
            }
        }

        void header_click (double x, double y) {
            var t = track_at (y);
            if (t == null) return;
            ctl.selected_track = t.id;
            double top = track_y (t);
            if (y - top > track_height (t) - 30) {
                string icon = "";
                int slot = (int) ((x - 9) / 26);
                if (slot == 0) icon = "lock";
                else if (slot == 1) icon = t.kind == TrackKind.AUDIO ? "mute" : "eye";
                else if (slot == 2 && t.kind == TrackKind.AUDIO) icon = "solo";
                else if (slot == 2 || slot == 3) icon = "sync";
                if (icon == "") return;
                ctl.project.checkpoint (_("Track Setting"));
                switch (icon) {
                    case "lock": t.locked = !t.locked; break;
                    case "mute": t.muted = !t.muted; break;
                    case "eye": t.visible = !t.visible; break;
                    case "solo": t.solo = !t.solo; break;
                    case "sync": t.sync_lock = !t.sync_lock; break;
                }
                ctl.project.commit ();
            }
            area.queue_draw ();
        }

        void on_drag_begin (GestureDrag g, double x, double y) {
            drag_x0 = x;
            drag_y0 = y;
            drag_dx = drag_dy = 0;
            drag_kind = "";
            drag_clip = null;
            if (g.get_current_button () != 1) return;
            if (y < RULER && x >= HEADER) {
                drag_kind = "scrub";
                return;
            }
            if (x < HEADER || ctl.tool == "razor") return;
            string zone;
            var c = clip_at (x, y, out zone);
            if (c == null) return;
            var tr = ctl.seq.track (c.track);
            if (tr != null && tr.kind == TrackKind.AUDIO && zone == "body") {
                double vy = volume_y (c, track_y (tr), track_height (tr), c.key_time (time_at (x)));
                if ((y - vy).abs () < 5) {
                    drag_kind = "volume";
                    drag_clip = c.id;
                    drag_time = c.key_time (time_at (x));
                    var vol = c.params.values["volume"];
                    drag_key = -1;
                    if (vol != null && vol.animated) {
                        int64 tol = (int64) (6 / pixels_per_second * Tc.SECOND);
                        for (int i = 0; i < vol.keys.size; i++) if ((vol.keys[i].time - drag_time).abs () < tol) drag_key = i;
                    }
                    drag_value0 = c.params.get_value ("volume", drag_time, 0);
                    return;
                }
            }
            drag_clip = c.id;
            if (zone == "head" || zone == "tail") drag_kind = zone;
            else if (ctl.tool == "slip") drag_kind = "slip";
            else if (ctl.tool == "slide") drag_kind = "slide";
            else drag_kind = "move";
        }

        void on_drag_update (GestureDrag g, double dx, double dy) {
            drag_dx = dx;
            drag_dy = dy;
            if (drag_kind == "scrub") {
                ctl.seek (ctl.seq.snap (int64.max (0, time_at (drag_x0 + dx))));
                return;
            }
            if (drag_kind == "volume") {
                var c = ctl.seq.clip (drag_clip);
                if (c == null) return;
                var tr = ctl.seq.track (c.track);
                double h = track_height (tr) - 18;
                double db = (drag_value0 - dy / h * 36).clamp (-60, 12);
                var vol = c.params.ensure ("volume", 0);
                if (drag_key >= 0 && drag_key < vol.keys.size) vol.keys[drag_key].value = db;
                else if (!vol.animated) vol.value = db;
                hover_info = "%.1f dB".printf (db);
                area.queue_draw ();
                return;
            }
            if (drag_kind == "head" || drag_kind == "tail" || drag_kind == "slip" || drag_kind == "slide") {
                var c = ctl.seq.clip (drag_clip);
                if (c != null) {
                    int64 delta = (int64) (dx / pixels_per_second * Tc.SECOND);
                    if (drag_kind == "head") trim_preview (c.position + delta - ctl.seq.frame, c.position + delta, true);
                    else if (drag_kind == "tail") trim_preview (c.end + delta - ctl.seq.frame, c.end + delta, true);
                    else trim_preview (c.position + (drag_kind == "slide" ? delta : 0), c.end - ctl.seq.frame + (drag_kind == "slide" ? delta : 0), true);
                    hover_info = (delta >= 0 ? "+" : "-") + Tc.format (delta.abs (), ctl.seq.fps_n, ctl.seq.fps_d);
                }
            }
            area.queue_draw ();
        }

        void on_drag_end (GestureDrag g, double dx, double dy) {
            string kind = drag_kind;
            drag_kind = "";
            hover_info = null;
            trim_preview (0, 0, false);
            if (kind == "" || kind == "scrub") {
                area.queue_draw ();
                return;
            }
            var c = drag_clip != null ? ctl.seq.clip (drag_clip) : null;
            if (c == null) return;
            try {
                if (kind == "volume") {
                    var vol = c.params.values["volume"];
                    double now = drag_key >= 0 && vol != null && drag_key < vol.keys.size ? vol.keys[drag_key].value : (vol != null ? vol.value : 0);
                    if (drag_key >= 0) vol.keys[drag_key].value = drag_value0;
                    else if (vol != null) vol.value = drag_value0;
                    ctl.project.checkpoint (_("Volume"));
                    if (drag_key >= 0) vol.keys[drag_key].value = now;
                    else vol.value = now;
                    ctl.project.commit ();
                    return;
                }
                if (dx.abs () < 2 && dy.abs () < 2) return;
                int64 delta = (int64) (dx / pixels_per_second * Tc.SECOND);
                if (kind == "move") {
                    var ids = ctl.linked ? ctl.selection : new Gee.HashSet<string> ();
                    if (!ctl.linked) ids.add (c.id);
                    if (!ids.contains (c.id)) ids.add (c.id);
                    int64 target = snap (c.position + delta, ids);
                    int64 target_end = snap (c.end + delta, ids);
                    if ((target_end - (c.end + delta)).abs () < (target - (c.position + delta)).abs ()) target = target_end - c.duration;
                    var dest = track_at (drag_y0 + dy);
                    var src = ctl.seq.track (c.track);
                    int offset = 0;
                    if (dest != null && src != null && dest.kind == src.kind) {
                        var same = ctl.seq.tracks_of (src.kind);
                        offset = same.index_of (dest) - same.index_of (src);
                    }
                    bool insert = (get_modifiers () & Gdk.ModifierType.CONTROL_MASK) != 0;
                    var move_ids = new Gee.ArrayList<string> ();
                    foreach (var id in ids) move_ids.add (id);
                    ctl.edits.move (move_ids, target - c.position, offset, insert);
                } else if (kind == "head" || kind == "tail") {
                    TrimMode mode = TrimMode.NORMAL;
                    if (ctl.tool == "ripple") mode = TrimMode.RIPPLE;
                    else if (ctl.tool == "roll") mode = TrimMode.ROLL;
                    int64 edge = kind == "head" ? c.position : c.end;
                    int64 snapped = snap (edge + delta, new Gee.ArrayList<string>.wrap ({ c.id }));
                    ctl.edits.trim (c.id, kind == "head", snapped - edge, mode, ctl.linked);
                } else if (kind == "slip") {
                    ctl.edits.trim (c.id, true, -delta, TrimMode.SLIP, ctl.linked);
                } else if (kind == "slide") {
                    ctl.edits.trim (c.id, true, delta, TrimMode.SLIDE, ctl.linked);
                }
            } catch (Error e) {
                edit_failed (e.message);
            }
            area.queue_draw ();
        }

        void drop_media (string id, double x, double y, bool insert) {
            var m = ctl.project.find_media (id);
            if (m == null) return;
            var tr = track_at (y);
            string? video = null, audio = null;
            if (tr != null && tr.kind == TrackKind.VIDEO) video = tr.id;
            if (tr != null && tr.kind == TrackKind.AUDIO) audio = tr.id;
            if (video == null && m.has_video) video = ctl.target_track (TrackKind.VIDEO);
            if (audio == null && m.has_audio) audio = ctl.target_track (TrackKind.AUDIO);
            int64 in_p = m.mark_in >= 0 ? m.mark_in : 0;
            int64 out_p = m.mark_out > in_p ? m.mark_out : (m.still ? in_p + 5 * Tc.SECOND : m.duration);
            var clips = ctl.edits.make_media_clips (m, in_p, out_p, video, audio);
            try {
                ctl.edits.place (clips, snap (int64.max (0, time_at (x)), null), insert);
                if (clips.size > 0) ctl.select (clips[0]);
            } catch (Error e) {
                edit_failed (e.message);
            }
        }

        double volume_y (Clip c, double top, double h, int64 key) {
            double db = c.params.get_value ("volume", key, 0);
            double inner = h - 18;
            return top + 16 + inner * ((12 - db.clamp (-24, 12)) / 36);
        }

        void color (Cairo.Context cr, string hex, double alpha = 1) {
            var c = Gdk.RGBA ();
            c.parse (hex);
            cr.set_source_rgba (c.red, c.green, c.blue, alpha);
        }

        void draw (DrawingArea a, Cairo.Context cr, int width, int height) {
            fg = a.get_color ();
            if (!a.get_style_context ().lookup_color ("accent_color", out accent)) accent.parse ("#3584e4");
            var seq = ctl.seq;
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.04);
            cr.paint ();
            cr.select_font_face ("sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
            cr.set_font_size (11);
            double y = RULER;
            foreach (var t in display_tracks ()) {
                double h = track_height (t);
                draw_track (cr, t, y, h, width);
                y += h;
            }
            cr.save ();
            cr.rectangle (HEADER, 0, width - HEADER, height);
            cr.clip ();
            foreach (var tr in seq.transitions) draw_transition (cr, tr);
            draw_ruler (cr, width);
            double px = x_of (ctl.program.position);
            cr.set_source_rgba (0.88, 0.19, 0.23, 1);
            cr.set_line_width (1.5);
            cr.move_to (px, 0);
            cr.line_to (px, height);
            cr.stroke ();
            cr.move_to (px - 6, 0);
            cr.line_to (px + 6, 0);
            cr.line_to (px, 9);
            cr.close_path ();
            cr.fill ();
            cr.restore ();
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.06);
            cr.rectangle (0, 0, HEADER, RULER);
            cr.fill ();
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.9);
            cr.set_font_size (13);
            cr.move_to (10, 22);
            cr.show_text (Tc.format (ctl.program.position, seq.fps_n, seq.fps_d));
            if (hover_info != null) {
                cr.set_font_size (12);
                Cairo.TextExtents ext;
                cr.text_extents (hover_info, out ext);
                double hx = drag_x0 + drag_dx + 10, hy = drag_y0 + drag_dy - 14;
                cr.set_source_rgba (0, 0, 0, 0.75);
                cr.rectangle (hx - 4, hy - 13, ext.width + 8, 18);
                cr.fill ();
                cr.set_source_rgba (1, 1, 1, 1);
                cr.move_to (hx, hy);
                cr.show_text (hover_info);
            }
        }

        void draw_ruler (Cairo.Context cr, int width) {
            var seq = ctl.seq;
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.06);
            cr.rectangle (HEADER, 0, width - HEADER, RULER);
            cr.fill ();
            if (seq.in_point >= 0 || seq.out_point >= 0) {
                double x0 = seq.in_point >= 0 ? x_of (seq.in_point) : HEADER;
                double x1 = seq.out_point >= 0 ? x_of (seq.out_point) : width;
                cr.set_source_rgba (accent.red, accent.green, accent.blue, 0.25);
                cr.rectangle (x0, 0, x1 - x0, RULER);
                cr.fill ();
            }
            for (int i = 0; i < ctl.prerender.heavy_starts.size; i++) {
                double x0 = x_of (ctl.prerender.heavy_starts[i]), x1 = x_of (ctl.prerender.heavy_ends[i]);
                cr.set_source_rgba (0.85, 0.3, 0.25, 0.9);
                cr.rectangle (x0, RULER - 4, x1 - x0, 3);
                cr.fill ();
                cr.set_source_rgba (0.3, 0.75, 0.35, 1);
                int64 frame = seq.frame;
                for (int64 t = ctl.prerender.heavy_starts[i]; t < ctl.prerender.heavy_ends[i]; t += frame) {
                    if (!ctl.prerender.is_done (t)) continue;
                    cr.rectangle (x_of (t), RULER - 4, double.max (1, x_of (t + frame) - x_of (t)), 3);
                }
                cr.fill ();
            }
            double step = 1;
            foreach (double s in new double[] { 1.0 / 30, 0.2, 0.5, 1, 2, 5, 10, 30, 60, 120, 300, 600 }) {
                step = s;
                if (s * pixels_per_second >= 70) break;
            }
            double start = Math.floor (hadj.value / pixels_per_second / step) * step;
            cr.set_font_size (10);
            for (double s = start; ; s += step) {
                double x = HEADER + s * pixels_per_second - hadj.value;
                if (x > width) break;
                cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.5);
                cr.set_line_width (1);
                cr.move_to (x + 0.5, RULER - 12);
                cr.line_to (x + 0.5, RULER);
                cr.stroke ();
                cr.move_to (x + 3, 14);
                cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.8);
                cr.show_text (step < 1 ? Tc.format ((int64) (s * Tc.SECOND), seq.fps_n, seq.fps_d) : Tc.format ((int64) (s * Tc.SECOND), seq.fps_n, seq.fps_d).substring (0, 8));
            }
            foreach (var m in seq.markers) {
                double x = x_of (m.time);
                color (cr, m.kind == "chapter" ? "#e5a50a" : LABELS[m.color.clamp (0, 7)]);
                cr.move_to (x, RULER - 14);
                cr.line_to (x + 6, RULER - 20);
                cr.line_to (x + 6, RULER - 28);
                cr.line_to (x - 6, RULER - 28);
                cr.line_to (x - 6, RULER - 20);
                cr.close_path ();
                cr.fill ();
                if (m.duration > 0) {
                    cr.rectangle (x, RULER - 18, x_of (m.time + m.duration) - x, 3);
                    cr.fill ();
                }
            }
            foreach (var c in seq.comments) {
                double x = x_of (c.time);
                color (cr, c.resolved ? "#77767b" : "#26a269");
                cr.arc (x, RULER - 21, 5, 0, 2 * Math.PI);
                cr.fill ();
            }
        }

        static Gee.HashMap<string, Cairo.ImageSurface>? icons;

        Cairo.ImageSurface? icon (string name) {
            if (icons == null) icons = new Gee.HashMap<string, Cairo.ImageSurface> ();
            if (icons.has_key (name)) return icons[name];
            Cairo.ImageSurface? surface = null;
            var theme = Gtk.IconTheme.get_for_display (get_display ());
            string[] fallbacks = name == "changes-prevent-symbolic" ? new string[] { "system-lock-screen-symbolic", "channel-secure-symbolic" } : new string[] {};
            var paintable = theme.lookup_icon (name, fallbacks, 16, 1, Gtk.TextDirection.LTR, 0);
            var file = paintable.get_file ();
            if (file != null && file.get_path () != null) {
                try {
                    var pix = new Gdk.Pixbuf.from_file_at_scale (file.get_path (), 16, 16, true);
                    surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, 16, 16);
                    var c = new Cairo.Context (surface);
                    Gdk.cairo_set_source_pixbuf (c, pix, 0, 0);
                    c.paint ();
                } catch (Error e) {
                }
            }
            icons[name] = surface;
            return surface;
        }

        void draw_track (Cairo.Context cr, Track t, double y, double h, int width) {
            bool selected = t.id == ctl.selected_track;
            cr.set_source_rgba (fg.red, fg.green, fg.blue, selected ? 0.12 : 0.06);
            cr.rectangle (0, y, HEADER - 2, h - 1);
            cr.fill ();
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.95);
            cr.set_font_size (12);
            cr.move_to (10, y + 19);
            cr.show_text (t.name);
            cr.set_font_size (10);
            string[] names = t.kind == TrackKind.AUDIO
                ? new string[] { "changes-prevent-symbolic", "audio-volume-muted-symbolic", "audio-headphones-symbolic", "emblem-synchronizing-symbolic" }
                : new string[] { "changes-prevent-symbolic", t.visible ? "view-reveal-symbolic" : "view-conceal-symbolic", "emblem-synchronizing-symbolic" };
            bool[] on = t.kind == TrackKind.AUDIO ? new bool[] { t.locked, t.muted, t.solo, t.sync_lock } : new bool[] { t.locked, !t.visible, t.sync_lock };
            if (h > 40) {
                double gx = 8, gy = y + h - 29;
                cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.06);
                rounded (cr, gx, gy, names.length * 26 + 2, 24, 7);
                cr.fill ();
                for (int i = 0; i < names.length; i++) {
                    double ix = gx + 1 + i * 26, iy = gy + 1;
                    if (on[i]) {
                        cr.set_source_rgba (accent.red, accent.green, accent.blue, 0.3);
                        rounded (cr, ix, iy, 26, 22, 6);
                        cr.fill ();
                    }
                    var ic = icon (names[i]);
                    if (on[i]) cr.set_source_rgba (fg.red, fg.green, fg.blue, 1);
                    else cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.5);
                    if (ic != null) cr.mask_surface (ic, ix + 5, iy + 3);
                }
            }
            if (t.kind == TrackKind.AUDIO) {
                string db = "%+.0f dB".printf (t.volume.value);
                cr.set_font_size (11);
                Cairo.TextExtents ext;
                cr.text_extents (db, out ext);
                cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.6);
                cr.move_to (HEADER - 12 - ext.x_advance, y + 19);
                cr.show_text (db);
            }
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.08);
            cr.move_to (HEADER, y + h - 0.5);
            cr.line_to (width, y + h - 0.5);
            cr.stroke ();
            cr.save ();
            cr.rectangle (HEADER, y, width - HEADER, h);
            cr.clip ();
            foreach (var c in ctl.seq.on_track (t.id)) draw_clip (cr, c, t, y, h, width);
            if (t.kind == TrackKind.AUDIO && t.volume.animated) {
                cr.set_source_rgba (0.35, 0.75, 1, 0.95);
                cr.set_line_width (1.5);
                for (double px = HEADER; px <= width; px += 3) {
                    double db = t.volume.at (time_at (px)).clamp (-24, 12);
                    double vy = y + 4 + (h - 8) * ((12 - db) / 36);
                    if (px == HEADER) cr.move_to (px, vy);
                    else cr.line_to (px, vy);
                }
                cr.stroke ();
                foreach (var k in t.volume.keys) {
                    double kx = x_of (k.time);
                    double ky = y + 4 + (h - 8) * ((12 - k.value.clamp (-24, 12)) / 36);
                    cr.arc (kx, ky, 3, 0, 2 * Math.PI);
                    cr.fill ();
                }
            }
            if (t.locked) {
                cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.06);
                cr.rectangle (HEADER, y, width - HEADER, h);
                cr.fill ();
            }
            cr.restore ();
        }

        void draw_clip (Cairo.Context cr, Clip c, Track t, double y, double h, int width) {
            double x0 = x_of (c.position), x1 = x_of (c.end);
            bool dragging = drag_clip == c.id || (drag_kind == "move" && ctl.selection.contains (c.id));
            if (dragging && drag_kind == "move") {
                x0 += drag_dx;
                x1 += drag_dx;
            } else if (drag_clip == c.id && drag_kind == "head") {
                x0 += drag_dx;
            } else if (drag_clip == c.id && drag_kind == "tail") {
                x1 += drag_dx;
            } else if (drag_clip == c.id && drag_kind == "slide") {
                x0 += drag_dx;
                x1 += drag_dx;
            }
            if (x1 < HEADER || x0 > width) return;
            double top = y + 3, ch = h - 6;
            if (dragging && drag_kind == "move") top += drag_dy;
            bool sel = ctl.selection.contains (c.id);
            string base_color;
            switch (c.kind) {
                case ClipKind.TITLE: base_color = "#9141ac"; break;
                case ClipKind.COLOR: base_color = c.color.length >= 7 ? c.color.substring (0, 7) : "#444444"; break;
                case ClipKind.ADJUSTMENT: base_color = "#77767b"; break;
                case ClipKind.SUBTITLE: base_color = "#c64600"; break;
                case ClipKind.SEQUENCE: base_color = "#26a269"; break;
                case ClipKind.MULTICAM: base_color = "#1a5fb4"; break;
                case ClipKind.COMPOSITION: base_color = "#a51d2d"; break;
                default: base_color = t.kind == TrackKind.AUDIO ? "#2b7a6b" : "#3d6aa8"; break;
            }
            var m = ctl.project.find_media (c.media);
            int label = c.label > 0 ? c.label : (m != null ? m.label : 0);
            if (label > 0) base_color = LABELS[label.clamp (0, 7)];
            color (cr, base_color, c.enabled ? 0.85 : 0.35);
            rounded (cr, x0, top, x1 - x0, ch, 4);
            cr.fill ();
            if (m != null && t.kind == TrackKind.VIDEO && c.kind == ClipKind.MEDIA && m.has_video && x1 - x0 > 30) {
                double th = ch - 18;
                double tw = th * 16 / 9;
                cr.save ();
                rounded (cr, x0, top, x1 - x0, ch, 4);
                cr.clip ();
                for (double tx = double.max (x0, HEADER - tw); tx < x1 && tx < width; tx += tw + 1) {
                    int64 at = c.source_time (time_at (tx));
                    var pix = ctl.media_cache.get_thumb (m.playback_uri (false), at);
                    if (pix == null) continue;
                    double sc = th / pix.height;
                    cr.save ();
                    cr.translate (tx, top + 16);
                    cr.scale (sc, sc);
                    Gdk.cairo_set_source_pixbuf (cr, pix, 0, 0);
                    cr.paint_with_alpha (c.enabled ? 1 : 0.4);
                    cr.restore ();
                    if (x1 - x0 < tw * 2) break;
                }
                cr.restore ();
            }
            if (m != null && t.kind == TrackKind.AUDIO && (c.kind == ClipKind.MEDIA || c.kind == ClipKind.MULTICAM)) {
                var pk = ctl.media_cache.get_peaks (m.playback_uri (false));
                if (pk != null) {
                    double mid = top + ch / 2 + 6;
                    double amp = (ch - 18) / 2;
                    cr.set_source_rgba (1, 1, 1, 0.55);
                    double gain = Singularity.Audio.db_to_gain (c.params.get_value ("volume", c.in_point, 0));
                    for (double px = double.max (x0, HEADER); px < double.min (x1, width); px += 1) {
                        int64 src = c.source_time (time_at (px));
                        float v = float.min (1, (float) (pk.at ((double) src / Tc.SECOND) * gain));
                        cr.rectangle (px, mid - v * amp, 1, v * amp * 2);
                    }
                    cr.fill ();
                }
                cr.set_source_rgba (1, 0.85, 0.2, 0.95);
                cr.set_line_width (1.5);
                bool first = true;
                for (double px = double.max (x0, HEADER); px <= double.min (x1, width); px += 3) {
                    double vy = volume_y (c, top, ch + 6, c.key_time (time_at (px)));
                    if (first) cr.move_to (px, vy);
                    else cr.line_to (px, vy);
                    first = false;
                }
                cr.stroke ();
                var vol = c.params.values["volume"];
                if (vol != null) foreach (var k in vol.keys) {
                    double kx = x_of (c.position + k.time - c.in_point);
                    double ky = volume_y (c, top, ch + 6, k.time);
                    cr.arc (kx, ky, 3.5, 0, 2 * Math.PI);
                    cr.fill ();
                }
            }
            if (t.kind == TrackKind.VIDEO && c.params.animated ()) {
                cr.set_source_rgba (1, 1, 1, 0.9);
                foreach (var v in c.params.values.values) foreach (var k in v.keys) {
                    double kx = x_of (c.position + k.time - c.in_point);
                    cr.move_to (kx, top + ch - 9);
                    cr.line_to (kx + 4, top + ch - 5);
                    cr.line_to (kx, top + ch - 1);
                    cr.line_to (kx - 4, top + ch - 5);
                    cr.close_path ();
                    cr.fill ();
                }
            }
            if (sel) {
                cr.set_source_rgba (1, 1, 1, 1);
                cr.set_line_width (2);
                rounded (cr, x0 + 1, top + 1, x1 - x0 - 2, ch - 2, 4);
                cr.stroke ();
            }
            cr.save ();
            cr.rectangle (x0 + 4, top, double.max (0, x1 - x0 - 8), ch);
            cr.clip ();
            cr.set_source_rgba (0, 0, 0, 0.35);
            cr.rectangle (x0, top, x1 - x0, 15);
            cr.fill ();
            cr.set_source_rgba (1, 1, 1, 1);
            cr.set_font_size (10.5);
            cr.move_to (double.max (x0, HEADER) + 5, top + 11);
            string name = ctl.project.clip_label (c);
            if (c.speed_changed) name += "  %.0f%%".printf (c.params.get_value ("speed", c.in_point, 100) * (c.reverse ? -1 : 1));
            if (!c.enabled) name = _("(disabled) ") + name;
            if (c.effects.size > 0) name = "fx  " + name;
            int64 sync = ctl.edits.sync_offset (c);
            if (sync != 0) name += "  " + (sync > 0 ? "+" : "-") + Tc.format (sync.abs (), ctl.seq.fps_n, ctl.seq.fps_d);
            cr.show_text (name);
            cr.restore ();
            if (sync != 0) {
                cr.set_source_rgba (0.9, 0.15, 0.15, 1);
                cr.rectangle (x0, top + ch - 3, x1 - x0, 3);
                cr.fill ();
            }
            if (c.kind == ClipKind.MULTICAM && t.kind == TrackKind.VIDEO) {
                cr.set_font_size (10);
                foreach (var cut in c.cuts) {
                    double cx = x_of (c.position + cut.time);
                    if (cx < x0 || cx > x1) continue;
                    cr.set_source_rgba (1, 1, 1, 0.9);
                    cr.rectangle (cx - 1, top + 15, 2, ch - 15);
                    cr.fill ();
                    cr.move_to (cx + 4, top + ch - 6);
                    cr.show_text ("%d".printf (cut.angle + 1));
                }
            }
            foreach (var mk in c.markers) {
                double mx = x_of (c.position + mk.time);
                color (cr, LABELS[mk.color.clamp (0, 7)]);
                cr.rectangle (mx - 1, top + 15, 2, ch - 15);
                cr.fill ();
            }
        }

        void draw_transition (Cairo.Context cr, Transition tr) {
            var t = ctl.seq.track (tr.track);
            if (t == null) return;
            var a = ctl.seq.clip (tr.from_clip);
            var b = ctl.seq.clip (tr.to_clip);
            int64 cut = a != null ? a.end : (b != null ? b.position : -1);
            if (cut < 0) return;
            int64 start = tr.start_at (cut);
            if (a == null) start = int64.max (start, cut);
            int64 end = start + tr.duration;
            if (b == null) end = int64.min (end, cut);
            double y = track_y (t) + 3, h = track_height (t) - 6;
            double x0 = x_of (start), x1 = x_of (end);
            cr.set_source_rgba (0, 0, 0, 0.45);
            rounded (cr, x0, y + h / 2 - 9, x1 - x0, 18, 9);
            cr.fill ();
            cr.set_source_rgba (1, 1, 1, 0.9);
            cr.set_line_width (1);
            cr.move_to (x0 + 3, y + h / 2 + 7);
            cr.line_to (x1 - 3, y + h / 2 - 7);
            cr.stroke ();
        }

        void rounded (Cairo.Context cr, double x, double y, double w, double h, double r) {
            r = double.min (r, double.min (w, h) / 2);
            if (w <= 0 || h <= 0) return;
            cr.new_sub_path ();
            cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
            cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
            cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
            cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
            cr.close_path ();
        }

        public void refresh () {
            update_extent ();
            area.queue_draw ();
        }
    }
}
