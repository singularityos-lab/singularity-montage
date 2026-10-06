using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Montage {
    namespace Recent {
        public void add (File file) {
            try {
                var info = file.query_info ("standard::content-type", FileQueryInfoFlags.NONE);
                Gtk.RecentManager.get_default ().add_full (file.get_uri (), Gtk.RecentData () {
                    display_name = file.get_basename (),
                    mime_type = info.get_content_type () ?? "application/octet-stream",
                    app_name = "Montage",
                    app_exec = "singularity-montage %u"
                });
            } catch (Error e) {
            }
        }
    }

    namespace FileOps {
        public FileFilter filter (string name, string[] patterns) {
            var f = new FileFilter ();
            f.name = name;
            foreach (var p in patterns) f.add_suffix (p);
            return f;
        }

        public GLib.ListStore filters (FileFilter[] list) {
            var store = new GLib.ListStore (typeof (FileFilter));
            foreach (var f in list) store.append (f);
            return store;
        }

        public async bool save (MontageWindow w, bool choose) {
            File? file = w.session.origin;
            if (file == null || choose || !(file.get_basename () ?? "").has_suffix (".montage")) {
                var dialog = new FileDialog ();
                dialog.initial_name = file != null ? (file.get_basename () ?? "").replace (".otio", "") + (file.get_basename ().has_suffix (".montage") ? "" : ".montage") : _("Untitled") + ".montage";
                dialog.filters = filters ({ filter (_("Montage Projects"), { "montage" }) });
                try {
                    file = yield dialog.save (w, null);
                } catch (Error e) {
                    return false;
                }
                if (!(file.get_basename () ?? "").has_suffix (".montage")) file = file.get_parent ().get_child (file.get_basename () + ".montage");
            }
            try {
                if (SharedProject.shared (file)) {
                    int merged = SharedProject.merge_from_disk (w.project, file);
                    if (merged > 0) w.say (ngettext ("Merged %d change made by others.", "Merged %d changes made by others.", merged).printf (merged));
                    SharedProject.refresh_locks (w.project, file);
                }
                w.session.save (file);
                w.update_title ();
                Recent.add (file);
                w.say (_("Saved %s.").printf (file.get_basename ()));
                return true;
            } catch (Error e) {
                w.say (_("Could not save: %s").printf (e.message));
                return false;
            }
        }

        public async File? save_dialog (MontageWindow w, string name, FileFilter[] list) {
            var dialog = new FileDialog ();
            dialog.initial_name = name;
            if (list.length > 0) dialog.filters = filters (list);
            try {
                return yield dialog.save (w, null);
            } catch (Error e) {
                return null;
            }
        }

        public async File? open_dialog (MontageWindow w, FileFilter[] list) {
            var dialog = new FileDialog ();
            if (list.length > 0) dialog.filters = filters (list);
            try {
                return yield dialog.open (w, null);
            } catch (Error e) {
                return null;
            }
        }
    }

    namespace Importing {
        public async void import_files (MontageWindow w, Gee.List<File> files, string? bin = null) {
            var ctl = w.ctl;
            int done = 0;
            var errors = new Gee.ArrayList<string> ();
            var added = new Gee.ArrayList<MediaItem> ();
            var app = (MontageApp) w.application;
            int threshold = app.get_int ("proxy-threshold", 1080);
            bool auto_proxy = app.get_bool ("auto-proxies", true);
            foreach (var f in files) {
                if (ctl.project.media_by_uri (f.get_uri ()) != null) continue;
                w.say (_("Reading %s (%d of %d)").printf (f.get_basename (), done + 1, files.size));
                MediaItem? m = null;
                string? err = null;
                string uri = f.get_uri ();
                new Thread<void*> ("montage-probe", () => {
                    try {
                        m = Probe.probe (uri);
                    } catch (Error e) {
                        err = e.message;
                    }
                    Idle.add (import_files.callback);
                    return null;
                });
                yield;
                done++;
                if (m == null) {
                    errors.add (err ?? f.get_basename ());
                    continue;
                }
                if (bin != null) m.bin = bin;
                added.add (m);
            }
            if (added.size > 0) {
                ctl.project.checkpoint (_("Import"));
                foreach (var m in added) ctl.project.media.add (m);
                ctl.project.media_changed ();
                ctl.project.commit ();
                if (auto_proxy) foreach (var m in added) if (ctl.proxies.needs_proxy (m, threshold)) ctl.proxies.request (m);
                ctl.show_source (added[0]);
                w.inspector.show_media (added[0]);
                w.media_panel.selected_media = added[0].id;
                w.media_panel.rebuild_items ();
                if (ctl.seq.clips.size == 0 && app.get_bool ("auto-sequence", true)) {
                    foreach (var m in added) append_to_timeline (w, m);
                    var first = added[0];
                    if (first.has_video && !first.still && ctl.seq.clips.size > 0) match_sequence (ctl, first);
                    w.timeline.zoom_fit ();
                }
            }
            if (errors.size > 0) w.say (_("Some files could not be imported: %s").printf (string.joinv ("; ", errors.to_array ())));
            else if (added.size > 0) w.say (ngettext ("Imported %d file.", "Imported %d files.", added.size).printf (added.size));
        }

        public void match_sequence (Controller ctl, MediaItem m) {
            var s = ctl.seq;
            if (s.width == m.width && s.height == m.height && s.fps_n == m.fps_n && s.fps_d == m.fps_d) return;
            ctl.project.checkpoint (_("Match Sequence to Media"));
            s.width = m.width & ~1;
            s.height = m.height & ~1;
            s.fps_n = m.fps_n;
            s.fps_d = m.fps_d;
            if (m.transfer == "pq") s.color_space = "rec2020-pq";
            else if (m.transfer == "hlg") s.color_space = "rec2020-hlg";
            ctl.project.commit ();
        }

        public void append_to_timeline (MontageWindow w, MediaItem m) {
            var ctl = w.ctl;
            int64 at = 0;
            string? v = m.has_video ? ctl.target_track (TrackKind.VIDEO) : null;
            string? a = m.has_audio ? ctl.target_track (TrackKind.AUDIO) : null;
            foreach (var c in ctl.seq.clips) if (c.track == v || c.track == a) at = int64.max (at, c.end);
            int64 in_p = m.mark_in >= 0 ? m.mark_in : 0;
            int64 out_p = m.mark_out > in_p ? m.mark_out : (m.still ? in_p + 5 * Tc.SECOND : m.duration);
            var clips = ctl.edits.make_media_clips (m, in_p, out_p, v, a);
            try {
                ctl.edits.place (clips, at, false);
            } catch (Error e) {
                w.say (e.message);
            }
        }
    }

    namespace TrimPreview {
        uint pending;
        int64 want_left;
        int64 want_right;

        public void show (MontageWindow w, int64 left, int64 right) {
            want_left = left;
            want_right = right;
            if (pending != 0) return;
            pending = Timeout.add (60, () => {
                pending = 0;
                var snap = w.ctl.project.clone ();
                var r = new Renderer (snap, snap.sequence, 0.25, snap.use_proxies);
                var a = r.render (int64.max (0, want_left));
                var b = r.render (int64.max (0, want_right));
                r.close ();
                w.program_view.compare_mode = "side";
                w.program_view.label_left = _("Out %s").printf (Tc.format (want_left, snap.sequence.fps_n, snap.sequence.fps_d));
                w.program_view.label_right = _("In %s").printf (Tc.format (want_right, snap.sequence.fps_n, snap.sequence.fps_d));
                w.program_view.show_compare (texture (a));
                w.program_view.show_texture (texture (b));
                return Source.REMOVE;
            });
        }

        public Gdk.Texture texture (Singularity.Imaging.FloatImage img) {
            var bytes = new Bytes.take (ColorPipeline.encode_rgba8 (img, true));
            return new Gdk.MemoryTexture (img.width, img.height, Gdk.MemoryFormat.R8G8B8A8, bytes, img.width * 4);
        }
    }

    namespace SimpleMode {
        public void apply_edits (MontageWindow w, string spec) {
            var ctl = w.ctl;
            var seq = ctl.seq;
            if (seq.clips.size == 0) return;
            var keep_starts = new Gee.ArrayList<int64?> ();
            var keep_ends = new Gee.ArrayList<int64?> ();
            foreach (var pair in spec.split (",")) {
                var p = pair.split ("-");
                if (p.length != 2) continue;
                keep_starts.add ((int64) (double.parse (p[0]) * Tc.SECOND));
                keep_ends.add ((int64) (double.parse (p[1]) * Tc.SECOND));
            }
            if (keep_starts.size == 0) return;
            int64 total = seq.duration;
            var rs = new Gee.ArrayList<int64?> ();
            var re = new Gee.ArrayList<int64?> ();
            int64 cursor = 0;
            for (int i = 0; i < keep_starts.size; i++) {
                if (keep_starts[i] > cursor) {
                    rs.add (cursor);
                    re.add (keep_starts[i]);
                }
                cursor = int64.max (cursor, keep_ends[i]);
            }
            if (cursor < total) {
                rs.add (cursor);
                re.add (total);
            }
            try {
                ctl.edits.remove_ranges (rs, re, _("Cuts from Videos"));
                w.timeline.zoom_fit ();
                w.say (_("Opened with the cuts made in Videos. Use the panels for more."));
            } catch (Error e) {
                w.say (e.message);
            }
        }
    }
}
