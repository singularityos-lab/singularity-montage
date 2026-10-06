namespace Singularity.Apps.Montage {
    public class Controller : Object {
        public Project project;
        public Edits edits;
        public Gee.HashSet<string> selection = new Gee.HashSet<string> ();
        public string selected_track = "";
        public string tool = "select";
        public bool snapping = true;
        public bool linked = true;
        public Playback program;
        public Playback source;
        public MediaItem? source_media;
        public MediaCache media_cache = new MediaCache ();
        public FrameCache cache;
        public ExportQueue queue = new ExportQueue ();
        public ProxyManager proxies;
        public Prerender prerender;
        public signal void selection_changed ();
        public signal void status (string message);
        public signal void source_changed ();

        public Controller (Project project) {
            this.project = project;
            edits = new Edits (project);
            cache = new FrameCache (FrameCache.default_dir ());
            program = new Playback (project);
            program.cache = cache;
            source = new Playback (project);
            proxies = new ProxyManager (project);
            prerender = new Prerender (project, cache);
            project.changed.connect (() => {
                var gone = new Gee.ArrayList<string> ();
                foreach (var id in selection) if (project.sequence.clip (id) == null) gone.add (id);
                foreach (var id in gone) selection.remove (id);
                program.proxies = project.use_proxies;
                program.invalidate ();
                prerender.schedule ();
                if (gone.size > 0) selection_changed ();
            });
        }

        public void shutdown () {
            program.shutdown ();
            source.shutdown ();
            prerender.stop ();
            proxies.stop ();
        }

        public Sequence seq {
            owned get { return project.sequence; }
        }

        public Clip? primary {
            owned get {
                Clip? best = null;
                foreach (var id in selection) {
                    var c = seq.clip (id);
                    if (c == null) continue;
                    var t = seq.track (c.track);
                    if (best == null || (t != null && t.kind == TrackKind.VIDEO && seq.track (best.track).kind != TrackKind.VIDEO)) best = c;
                }
                return best;
            }
        }

        public Gee.ArrayList<Clip> selected_clips () {
            var r = new Gee.ArrayList<Clip> ();
            foreach (var id in selection) {
                var c = seq.clip (id);
                if (c != null) r.add (c);
            }
            return r;
        }

        public void select (Clip? c, bool add = false) {
            if (!add) selection.clear ();
            if (c != null) {
                if (linked) foreach (var l in seq.linked (c)) selection.add (l.id);
                else selection.add (c.id);
                selected_track = c.track;
            }
            selection_changed ();
        }

        public void select_ids (Gee.Collection<string> ids) {
            selection.clear ();
            selection.add_all (ids);
            selection_changed ();
        }

        public int64 playhead {
            get { return program.position; }
        }

        public void seek (int64 t) {
            seq.playhead = t;
            program.seek (t);
        }

        public void show_source (MediaItem? m) {
            source_media = m;
            if (m == null) {
                source.custom = null;
                source_changed ();
                return;
            }
            var s = new Sequence (m.name);
            s.width = m.width > 0 ? m.width : seq.width;
            s.height = m.height > 0 ? m.height : seq.height;
            s.fps_n = m.fps_n;
            s.fps_d = m.fps_d;
            var v = new Track ("V1", TrackKind.VIDEO);
            var a = new Track ("A1", TrackKind.AUDIO);
            s.tracks.add (v);
            s.tracks.add (a);
            var e = new Edits (project);
            int64 length = m.still ? 5 * Tc.SECOND : m.duration;
            foreach (var c in e.make_media_clips (m, 0, length, v.id, a.id)) {
                c.link = "";
                s.clips.add (c);
            }
            source.custom = s;
            source.seek (0);
            source_changed ();
        }

        public string? target_track (TrackKind kind) {
            if (selected_track != "") {
                var t = seq.track (selected_track);
                if (t != null && t.kind == kind && !t.locked) return t.id;
            }
            foreach (var t in seq.tracks) if (t.kind == kind && !t.locked && t.target) return t.id;
            foreach (var t in seq.tracks) if (t.kind == kind && !t.locked) return t.id;
            return null;
        }

        public void say (string message) {
            status (message);
        }
    }
}
