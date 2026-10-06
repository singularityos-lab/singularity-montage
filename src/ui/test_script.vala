using Gtk;

namespace Singularity.Apps.Montage {
    public class TestScript : Object {
        static bool started;
        MontageWindow win;
        string[] lines;
        int index;

        public static void maybe_run (MontageWindow win) {
            string? path = Environment.get_variable ("SINGULARITY_MONTAGE_TEST_SCRIPT");
            if (path == null || started) return;
            started = true;
            string text;
            try {
                FileUtils.get_contents (path, out text);
            } catch (Error e) {
                printerr ("script: %s\n", e.message);
                return;
            }
            var s = new TestScript ();
            s.win = win;
            s.lines = text.split ("\n");
            s.ref ();
            Timeout.add (1200, () => {
                s.step ();
                return Source.REMOVE;
            });
        }

        void step () {
            while (index < lines.length) {
                string line = lines[index++].strip ();
                if (line == "" || line.has_prefix ("#")) continue;
                uint wait = 300;
                try {
                    wait = run (line);
                    printerr ("script: ok %s\n", line);
                } catch (Error e) {
                    printerr ("script: FAILED %s: %s\n", line, e.message);
                }
                Timeout.add (wait, () => {
                    step ();
                    return Source.REMOVE;
                });
                return;
            }
            printerr ("script: finished\n");
            unref ();
        }

        static Gtk.Button? find_button (Gtk.Widget w, string label) {
            if (w is Gtk.Button && w.is_visible ()) {
                var b = (Gtk.Button) w;
                if (b.label == label || face_text (b.child) == label) return b;
            }
            for (var c = w.get_first_child (); c != null; c = c.get_next_sibling ()) {
                var r = find_button (c, label);
                if (r != null) return r;
            }
            return null;
        }

        static string? face_text (Gtk.Widget? w) {
            if (w == null) return null;
            if (w is Gtk.Label) return ((Gtk.Label) w).label;
            for (var c = w.get_first_child (); c != null; c = c.get_next_sibling ()) {
                var t = face_text (c);
                if (t != null && t != "") return t;
            }
            return null;
        }

        Clip? clip_by (string spec) {
            if (spec == "sel") return win.ctl.primary;
            var seq = win.ctl.seq;
            var list = new Gee.ArrayList<Clip> ();
            list.add_all (seq.clips);
            list.sort ((a, b) => {
                int ta = seq.track_index (a.track), tb = seq.track_index (b.track);
                if (ta != tb) return ta - tb;
                return a.position < b.position ? -1 : (a.position > b.position ? 1 : 0);
            });
            int i = int.parse (spec);
            return i >= 0 && i < list.size ? list[i] : null;
        }

        public void shot (string name) throws Error {
            string dir = Environment.get_variable ("MONTAGE_SHOTS") ?? Environment.get_tmp_dir ();
            var paintable = new WidgetPaintable (win);
            int w = win.get_width (), h = win.get_height ();
            var snapshot = new Gtk.Snapshot ();
            paintable.snapshot (snapshot, w, h);
            var node = snapshot.free_to_node ();
            if (node == null) {
                Process.spawn_command_line_sync ("grim %s".printf (GLib.Shell.quote (Path.build_filename (dir, name + ".png"))));
                return;
            }
            var renderer = win.get_native ().get_renderer ();
            var texture = renderer.render_texture (node, Graphene.Rect ().init (0, 0, w, h));
            texture.save_to_png (Path.build_filename (dir, name + ".png"));
        }

        uint run (string line) throws Error {
            string[] p = line.split (" ", 2);
            string cmd = p[0];
            string arg = p.length > 1 ? p[1].strip () : "";
            var ctl = win.ctl;
            switch (cmd) {
                case "wait":
                    return (uint) int.parse (arg);
                case "action": {
                    var parts = arg.split (" ", 2);
                    var group = win.lookup_action (parts[0]);
                    if (group == null) throw new IOError.NOT_FOUND ("no action %s".printf (parts[0]));
                    group.activate (parts.length > 1 ? new Variant.string (parts[1]) : null);
                    return 500;
                }
                case "new":
                    win.new_project ();
                    return 400;
                case "import": {
                    var files = new Gee.ArrayList<File> ();
                    foreach (var f in arg.split ("|")) if (f.strip () != "") files.add (File.new_for_path (f.strip ()));
                    if (win.pages.visible_child_name != "workspace") win.new_project ();
                    Importing.import_files.begin (win, files);
                    return 2500;
                }
                case "open":
                    win.open_file (File.new_for_path (arg));
                    return 1500;
                case "save":
                    win.session.save (File.new_for_path (arg));
                    win.update_title ();
                    return 500;
                case "select":
                    ctl.select (clip_by (arg));
                    return 400;
                case "place": {
                    var parts = arg.split ("|");
                    MediaItem? m = null;
                    foreach (var item in ctl.project.media) if (item.name == parts[0]) m = item;
                    if (m == null) throw new IOError.NOT_FOUND ("no media");
                    var tracks = ctl.seq.tracks_of (TrackKind.VIDEO);
                    int ti = int.parse (parts[1]);
                    while (tracks.size <= ti) tracks = (ctl.edits.add_track (TrackKind.VIDEO) != null) ? ctl.seq.tracks_of (TrackKind.VIDEO) : tracks;
                    var clips = ctl.edits.make_media_clips (m, 0, (int64) (double.parse (parts[3]) * Tc.SECOND), tracks[ti].id, null);
                    ctl.edits.place (clips, (int64) (double.parse (parts[2]) * Tc.SECOND), false);
                    ctl.select (clips[0]);
                    return 500;
                }
                case "select-clip-of": {
                    foreach (var c in ctl.seq.clips) {
                        var m = ctl.project.find_media (c.media);
                        if (m != null && m.name == arg) {
                            ctl.select (c);
                            break;
                        }
                    }
                    return 500;
                }
                case "click-label": {
                    foreach (var t in Gtk.Window.list_toplevels ()) {
                        var b = find_button (t, arg);
                        if (b != null) {
                            b.clicked ();
                            return 500;
                        }
                    }
                    throw new IOError.NOT_FOUND ("no button %s".printf (arg));
                }
                case "trim-preview": {
                    var parts = arg.split (" ");
                    TrimPreview.show (win, (int64) (double.parse (parts[0]) * Tc.SECOND), (int64) (double.parse (parts[1]) * Tc.SECOND));
                    return 1500;
                }
                case "angle": {
                    var c = ctl.primary;
                    if (c == null || c.kind != ClipKind.MULTICAM) throw new IOError.NOT_FOUND ("no multicam");
                    MulticamOps.cut (ctl, c, ctl.playhead, int.parse (arg));
                    return 400;
                }
                case "media-label": {
                    var parts = arg.split ("|");
                    foreach (var m in ctl.project.media) if (m.name == parts[0]) {
                        ctl.project.checkpoint ("label");
                        m.label = int.parse (parts[1]);
                        ctl.project.commit ();
                    }
                    return 400;
                }
                case "new-bin":
                    ctl.project.checkpoint ("bin");
                    ctl.project.bins.add (new Bin (arg));
                    ctl.project.commit ();
                    return 400;
                case "maximize":
                    win.maximize ();
                    return 1500;
                case "present":
                    win.present ();
                    return 800;
                case "select-add":
                    ctl.select (clip_by (arg), true);
                    return 300;
                case "select-media":
                    foreach (var m in ctl.project.media) if (m.name == arg) {
                        ctl.show_source (m);
                        win.inspector.show_media (m);
                    }
                    return 600;
                case "seek":
                    ctl.seek ((int64) (double.parse (arg) * Tc.SECOND));
                    return 700;
                case "play":
                    ctl.program.play (1);
                    return (uint) (double.parse (arg) * 1000);
                case "pause":
                    ctl.program.pause ();
                    return 400;
                case "tool":
                    win.lookup_action ("tool").activate (new Variant.string (arg));
                    return 200;
                case "workspace":
                    win.lookup_action ("workspace").activate (new Variant.string (arg));
                    return 800;
                case "zoom-fit":
                    win.timeline.zoom_fit ();
                    return 300;
                case "trim": {
                    var parts = arg.split (" ");
                    var c = clip_by (parts[0]);
                    if (c == null) throw new IOError.NOT_FOUND ("no clip");
                    TrimMode mode = TrimMode.NORMAL;
                    switch (parts[2]) {
                        case "ripple": mode = TrimMode.RIPPLE; break;
                        case "roll": mode = TrimMode.ROLL; break;
                        case "slip": mode = TrimMode.SLIP; break;
                        case "slide": mode = TrimMode.SLIDE; break;
                    }
                    ctl.edits.trim (c.id, parts[1] == "head", (int64) (double.parse (parts[3]) * Tc.SECOND), mode, true);
                    return 500;
                }
                case "param": {
                    var parts = arg.split (" ");
                    var c = clip_by (parts[0]);
                    ctl.project.checkpoint ("param");
                    c.params.ensure (parts[1], 0).value = double.parse (parts[2]);
                    ctl.project.commit ();
                    return 500;
                }
                case "key": {
                    var parts = arg.split (" ");
                    var c = clip_by (parts[0]);
                    ctl.project.checkpoint ("key");
                    c.params.ensure (parts[1], 0).set_key ((int64) (double.parse (parts[2]) * Tc.SECOND) + c.in_point, double.parse (parts[3]));
                    ctl.project.commit ();
                    return 400;
                }
                case "effect": {
                    var parts = arg.split (" ");
                    var c = clip_by (parts[0]);
                    ctl.project.checkpoint ("effect");
                    var e = Catalog.find (parts[1]).create ();
                    for (int i = 2; i + 1 < parts.length; i += 2) {
                        if (e.params.values.has_key (parts[i])) e.params.values[parts[i]].value = double.parse (parts[i + 1]);
                        else e.params.texts[parts[i]] = parts[i + 1];
                    }
                    c.effects.add (e);
                    ctl.project.commit ();
                    ctl.select (c);
                    return 600;
                }
                case "transition": {
                    var parts = arg.split (" ");
                    var c = clip_by (parts[0]);
                    ctl.edits.add_transition (c.id, parts[1] == "end", parts[2], (int64) (double.parse (parts[3]) * Tc.SECOND), 0);
                    return 500;
                }
                case "role": {
                    var parts = arg.split (" ");
                    var c = clip_by (parts[0]);
                    ctl.project.checkpoint ("role");
                    c.role = parts[1];
                    ctl.project.commit ();
                    return 200;
                }
                case "title-field": {
                    var parts = arg.split (" ", 3);
                    var c = clip_by (parts[0]);
                    ctl.project.checkpoint ("title");
                    c.title.fields[parts[1]] = parts[2];
                    ctl.project.commit ();
                    ctl.select (c);
                    return 500;
                }
                case "template": {
                    var parts = arg.split (" ");
                    var c = clip_by (parts[0]);
                    foreach (var t in Titles.builtin ()) if (t.id == parts[1]) {
                        ctl.project.checkpoint ("template");
                        c.title = t.data.copy ();
                        c.title.template_id = t.id;
                        ctl.project.commit ();
                    }
                    ctl.select (c);
                    return 500;
                }
                case "export": {
                    var parts = arg.split (" ");
                    var settings = new ExportSettings ();
                    settings.preset = Presets.find (parts[0]).copy ();
                    settings.output = File.new_for_path (parts[1]);
                    settings.hardware = false;
                    for (int i = 2; i + 1 < parts.length; i += 2) {
                        if (parts[i] == "subtitles") settings.subtitles = parts[i + 1];
                        if (parts[i] == "normalize") settings.normalize = parts[i + 1] == "true";
                        if (parts[i] == "width") settings.preset.width = int.parse (parts[i + 1]);
                        if (parts[i] == "height") settings.preset.height = int.parse (parts[i + 1]);
                        if (parts[i] == "start") settings.start = (int64) (double.parse (parts[i + 1]) * Tc.SECOND);
                        if (parts[i] == "end") settings.end = (int64) (double.parse (parts[i + 1]) * Tc.SECOND);
                    }
                    settings.sequence_id = ctl.seq.id;
                    ctl.queue.add (new ExportJob (ctl.project.clone (), settings));
                    return 500;
                }
                case "wait-queue": {
                    int64 deadline = get_monotonic_time () + (int64) int.parse (arg != "" ? arg : "120") * 1000000;
                    while (ctl.queue.pending > 0 && get_monotonic_time () < deadline) MainContext.default ().iteration (true);
                    foreach (var j in ctl.queue.jobs) printerr ("script: job %s %s %s %s\n", j.title, j.state, j.encoder_used, j.message);
                    return 300;
                }
                case "shot":
                    shot (arg);
                    return 200;
                case "dialog-shot": {
                    foreach (var t in Gtk.Window.list_toplevels ()) {
                        if (t == win || !t.visible) continue;
                        var paintable = new WidgetPaintable (t);
                        var snap = new Gtk.Snapshot ();
                        paintable.snapshot (snap, t.get_width (), t.get_height ());
                        var node = snap.free_to_node ();
                        if (node == null) continue;
                        var tex = t.get_native ().get_renderer ().render_texture (node, Graphene.Rect ().init (0, 0, t.get_width (), t.get_height ()));
                        tex.save_to_png (Path.build_filename (Environment.get_variable ("MONTAGE_SHOTS") ?? Environment.get_tmp_dir (), arg + ".png"));
                    }
                    return 200;
                }
                case "close-dialogs":
                    foreach (var t in Gtk.Window.list_toplevels ()) if (t != win && t.visible && t is Singularity.Widgets.AppDialog) ((Singularity.Widgets.AppDialog) t).close_dialog ();
                    return 500;
                case "wave-exchange":
                    printerr ("script: wave exchange %s\n", WaveRoundTrip.exchange_file (win).get_path ());
                    return 50;
                case "wave-apply":
                    printerr ("script: wave applied %s\n", WaveRoundTrip.apply (win, WaveRoundTrip.exchange_file (win), ctl.seq.id).to_string ());
                    return 800;
                case "status":
                    printerr ("script: status %s\n", win.status.label);
                    return 50;
                case "dump":
                    printerr ("script: dump clips=%d tracks=%d duration=%s sequences=%d media=%d\n", ctl.seq.clips.size, ctl.seq.tracks.size,
                        Tc.format (ctl.seq.duration, ctl.seq.fps_n, ctl.seq.fps_d), ctl.project.sequences.size, ctl.project.media.size);
                    return 50;
                case "undo":
                    ctl.project.undo ();
                    return 400;
                case "quit":
                    win.session.discard_recovery ();
                    win.application.quit ();
                    return 100;
                default:
                    throw new IOError.INVALID_ARGUMENT ("unknown command");
            }
        }
    }
}
