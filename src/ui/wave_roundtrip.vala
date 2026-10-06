namespace Singularity.Apps.Montage {
    namespace WaveRoundTrip {
        Gee.HashMap<string, FileMonitor>? monitors;

        public File exchange_file (MontageWindow w) {
            var dir = w.session.origin != null ? w.session.origin.get_parent () : File.new_for_path (Path.build_filename (Environment.get_user_special_dir (UserDirectory.VIDEOS) ?? Environment.get_home_dir (), "Montage"));
            string name = (w.session.origin != null ? (w.session.origin.get_basename () ?? "Project").replace (".montage", "") : w.ctl.seq.name) + " Sound.montage";
            return dir.get_child (name.replace ("/", "-"));
        }

        public void send (MontageWindow w) {
            var seq = w.ctl.seq;
            bool any = false;
            foreach (var c in seq.clips) if (c.kind == ClipKind.MEDIA) any = true;
            if (!any) {
                w.say (_("Add clips with sound to the timeline first."));
                return;
            }
            FileOps.save.begin (w, false, (o, r) => {
                if (!FileOps.save.end (r)) return;
                try {
                    var file = exchange_file (w);
                    var parent = file.get_parent ();
                    if (!parent.query_exists ()) parent.make_directory_with_parents ();
                    FileUtils.set_contents (file.get_path (), LegacyFormat.write (w.project, seq));
                    watch (w, file, seq.id);
                    string? exe = Environment.find_program_in_path ("singularity-wave");
                    if (exe == null) {
                        w.say (_("Wave is not installed. Install it to edit the sound of this sequence."));
                        return;
                    }
                    Process.spawn_async (null, { exe, "--montage", file.get_path () }, null, SpawnFlags.SEARCH_PATH, null, null);
                    w.say (_("Opened the sound of %s in Wave. Send it back from Wave and the mix appears here.").printf (seq.name));
                } catch (Error e) {
                    w.say (e.message);
                }
            });
        }

        void watch (MontageWindow w, File file, string seq_id) {
            if (monitors == null) monitors = new Gee.HashMap<string, FileMonitor> ();
            if (monitors.has_key (file.get_uri ())) return;
            try {
                var monitor = file.monitor_file (FileMonitorFlags.WATCH_MOVES);
                monitor.changed.connect ((f, other, event) => {
                    if (event != FileMonitorEvent.CHANGES_DONE_HINT && event != FileMonitorEvent.MOVED_IN && event != FileMonitorEvent.RENAMED && event != FileMonitorEvent.CREATED) return;
                    Timeout.add (300, () => {
                        apply (w, file, seq_id);
                        return Source.REMOVE;
                    });
                });
                monitors[file.get_uri ()] = monitor;
            } catch (Error e) {
                warning ("wave watch: %s", e.message);
            }
        }

        public bool apply (MontageWindow w, File file, string seq_id) {
            try {
                uint8[] data;
                file.load_contents (null, out data, null);
                var root = Js.parse ((string) data);
                Json.Object? mix = null;
                foreach (var c in Js.objects (root, "clips")) if (Js.str (c, "track") == "wave-mix") mix = c;
                if (mix == null) return false;
                var seq = w.project.find_sequence (seq_id);
                if (seq == null) return false;
                string uri = Js.str (mix, "uri");
                var media = Probe.probe (uri);
                Track? track = null;
                foreach (var t in seq.tracks) if (t.kind == TrackKind.AUDIO && t.role == "wave-mix") track = t;
                w.project.checkpoint (_("Mix from Wave"));
                var existing = w.project.media_by_uri (uri);
                if (existing != null) {
                    existing.duration = media.duration;
                    media = existing;
                } else {
                    media.name = _("Wave Mix");
                    w.project.media.add (media);
                }
                if (track == null) {
                    track = new Track (_("Wave Mix"), TrackKind.AUDIO);
                    track.role = "wave-mix";
                    seq.tracks.add (track);
                }
                var old = new Gee.ArrayList<Clip> ();
                foreach (var c in seq.clips) if (c.track == track.id) old.add (c);
                foreach (var c in old) seq.clips.remove (c);
                foreach (var t in seq.tracks) if (t.kind == TrackKind.AUDIO && t != track) t.muted = true;
                var clip = new Clip ();
                clip.media = media.id;
                clip.track = track.id;
                clip.position = Js.integer (mix, "position");
                clip.in_point = Js.integer (mix, "start");
                clip.duration = int64.max (seq.frame, Js.integer (mix, "end") - clip.in_point);
                seq.clips.add (clip);
                w.project.media_changed ();
                w.project.commit ();
                w.ctl.media_cache.ready ();
                w.say (_("The Wave mix is in the timeline. The original sound tracks are muted."));
                return true;
            } catch (Error e) {
                w.say (_("Could not read the mix from Wave: %s").printf (e.message));
                return false;
            }
        }
    }
}
