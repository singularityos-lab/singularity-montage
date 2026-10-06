namespace Singularity.Apps.Montage {
    public class ProxyManager : Object {
        public Project project;
        public signal void progress (string media_id, double fraction);
        public signal void finished (string media_id, bool ok, string? error);
        Gee.ArrayQueue<string> waiting = new Gee.ArrayQueue<string> ();
        bool running;
        int stop_flag;
        public int max_height = 540;

        public ProxyManager (Project project) {
            this.project = project;
        }

        public static string proxy_dir () {
            return Path.build_filename (Environment.get_user_cache_dir (), "singularity-montage", "proxies");
        }

        public bool needs_proxy (MediaItem m, int threshold) {
            if (m.kind != "file" || !m.has_video || m.still) return false;
            return m.height > threshold || m.variable_rate || m.depth > 8;
        }

        public void request (MediaItem m) {
            if (m.kind != "file" || !m.has_video || m.still) return;
            if (m.proxy_state == "ready" && m.proxy_uri != "" && File.new_for_uri (m.proxy_uri).query_exists ()) return;
            if (waiting.contains (m.id)) return;
            m.proxy_state = "queued";
            waiting.offer_tail (m.id);
            project.media_changed ();
            next ();
        }

        public void stop () {
            AtomicInt.set (ref stop_flag, 1);
        }

        void next () {
            if (running || waiting.size == 0) return;
            var id = waiting.poll_head ();
            var m = project.find_media (id);
            if (m == null) {
                next ();
                return;
            }
            running = true;
            m.proxy_state = "running";
            project.media_changed ();
            string uri = m.uri;
            int fps_n = m.fps_n, fps_d = m.fps_d;
            int h = int.min (max_height, m.height) & ~1;
            int w = ((int) Math.round ((double) m.width * h / int.max (1, m.height))) & ~1;
            bool audio = m.has_audio;
            int64 duration = m.duration;
            string out_path = Path.build_filename (proxy_dir (), "%s-%dp.mkv".printf (Checksum.compute_for_string (ChecksumType.SHA1, uri), h));
            new Thread<void*> ("montage-proxy", () => {
                string? error = null;
                try {
                    generate (uri, out_path, w, h, fps_n, fps_d, audio, duration, id);
                } catch (Error e) {
                    error = e.message;
                }
                Idle.add (() => {
                    running = false;
                    var item = project.find_media (id);
                    if (item != null) {
                        item.proxy_state = error == null ? "ready" : "failed";
                        if (error == null) item.proxy_uri = File.new_for_path (out_path).get_uri ();
                        project.media_changed ();
                        project.commit ();
                    }
                    finished (id, error == null, error);
                    next ();
                    return Source.REMOVE;
                });
                return null;
            });
        }

        public void generate (string uri, string out_path, int w, int h, int fps_n, int fps_d, bool audio, int64 duration, string id) throws Error {
            DirUtils.create_with_parents (Path.get_dirname (out_path), 0700);
            string tmp = out_path + ".part";
            var desc = new StringBuilder ();
            desc.append ("uridecodebin name=d uri=\"%s\" ".printf (uri.replace ("\"", "%22")));
            desc.append ("d. ! queue ! videoconvert ! videoscale ! videorate ! video/x-raw,format=RGB,width=%d,height=%d,pixel-aspect-ratio=1/1,framerate=%d/%d ! jpegenc quality=85 ! queue ! mux.video_%%u "
                .printf (w, h, fps_n, fps_d));
            if (audio) desc.append ("d. ! queue ! audioconvert ! audioresample ! audio/x-raw,format=S16LE,rate=48000,channels=2 ! queue ! mux.audio_%u ");
            desc.append ("matroskamux name=mux ! filesink location=\"%s\"".printf (tmp));
            var pipeline = (Gst.Pipeline) Gst.parse_launch (desc.str);
            pipeline.set_state (Gst.State.PLAYING);
            var bus = pipeline.get_bus ();
            string? failure = null;
            while (true) {
                if (AtomicInt.get (ref stop_flag) != 0) {
                    failure = _("Proxy generation stopped.");
                    break;
                }
                var msg = bus.timed_pop_filtered (200 * Gst.MSECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR);
                int64 pos = 0;
                if (duration > 0 && pipeline.query_position (Gst.Format.TIME, out pos)) {
                    double f = (double) pos / duration;
                    Idle.add (() => {
                        progress (id, f.clamp (0, 1));
                        return Source.REMOVE;
                    });
                }
                if (msg == null) continue;
                if (msg.type == Gst.MessageType.ERROR) {
                    Error e;
                    string debug;
                    msg.parse_error (out e, out debug);
                    failure = e.message;
                }
                break;
            }
            pipeline.set_state (Gst.State.NULL);
            if (failure != null) {
                FileUtils.remove (tmp);
                throw new IOError.FAILED (failure);
            }
            if (FileUtils.rename (tmp, out_path) != 0) throw new IOError.FAILED (_("The proxy file could not be stored."));
        }
    }

    public class Prerender : Object {
        public Project project;
        public FrameCache cache;
        public double scale = 0.5;
        public bool enabled = true;
        public signal void updated ();
        public Gee.ArrayList<int64?> heavy_starts = new Gee.ArrayList<int64?> ();
        public Gee.ArrayList<int64?> heavy_ends = new Gee.ArrayList<int64?> ();
        public Gee.HashSet<int64?> done = new Gee.HashSet<int64?> ((v) => (uint) (v ^ (v >> 32)), (a, b) => a == b);
        uint timer;
        int generation;
        Thread<void*>? worker;
        Mutex mutex;

        public Prerender (Project project, FrameCache cache) {
            this.project = project;
            this.cache = cache;
        }

        public static bool heavy (Project p, Sequence s, int64 t) {
            int layers = 0;
            foreach (var tr in s.transitions) {
                var a = s.clip (tr.from_clip);
                var b = s.clip (tr.to_clip);
                int64 cut = a != null ? a.end : (b != null ? b.position : -1);
                if (cut < 0) continue;
                int64 start = tr.start_at (cut);
                if (t >= start && t < start + tr.duration) return true;
            }
            foreach (var c in s.clips) {
                var track = s.track (c.track);
                if (track == null || track.kind != TrackKind.VIDEO || !track.visible || !c.enabled) continue;
                if (t < c.position || t >= c.end) continue;
                layers++;
                if (c.effects.size > 0 || c.kind != ClipKind.MEDIA || c.speed_changed || c.params.animated ()) return true;
            }
            return layers > 1;
        }

        public void schedule () {
            if (!enabled) return;
            AtomicInt.inc (ref generation);
            if (timer != 0) Source.remove (timer);
            timer = Timeout.add (1500, () => {
                timer = 0;
                start ();
                return Source.REMOVE;
            });
        }

        public void stop () {
            AtomicInt.inc (ref generation);
            if (timer != 0) Source.remove (timer);
            timer = 0;
            if (worker != null) {
                worker.join ();
                worker = null;
            }
        }

        public bool is_done (int64 frame_time) {
            mutex.lock ();
            bool r = done.contains (frame_time);
            mutex.unlock ();
            return r;
        }

        void start () {
            if (worker != null) {
                worker.join ();
                worker = null;
            }
            var snap = project.clone ();
            var seq = snap.sequence;
            int gen = AtomicInt.get (ref generation);
            var starts = new Gee.ArrayList<int64?> ();
            var ends = new Gee.ArrayList<int64?> ();
            int64 frame = seq.frame;
            int64 run_start = -1;
            for (int64 t = 0; t < seq.duration; t += frame) {
                bool h = heavy (snap, seq, t);
                if (h && run_start < 0) run_start = t;
                if (!h && run_start >= 0) {
                    starts.add (run_start);
                    ends.add (t);
                    run_start = -1;
                }
            }
            if (run_start >= 0) {
                starts.add (run_start);
                ends.add (seq.duration);
            }
            heavy_starts = starts;
            heavy_ends = ends;
            mutex.lock ();
            done.clear ();
            mutex.unlock ();
            updated ();
            if (starts.size == 0) return;
            bool proxies = snap.use_proxies;
            worker = new Thread<void*> ("montage-prerender", () => {
                var r = new Renderer (snap, seq, scale, proxies);
                r.cache = null;
                int count = 0;
                for (int i = 0; i < starts.size; i++) {
                    for (int64 t = starts[i]; t < ends[i]; t += frame) {
                        if (AtomicInt.get (ref generation) != gen) {
                            r.close ();
                            return null;
                        }
                        string key = r.signature (t);
                        if (!cache.contains (key)) {
                            var img = r.render_uncached (t);
                            cache.store (key, img, true);
                        }
                        mutex.lock ();
                        done.add (t);
                        mutex.unlock ();
                        if (++count % 10 == 0) Idle.add (() => {
                            updated ();
                            return Source.REMOVE;
                        });
                    }
                }
                r.close ();
                Idle.add (() => {
                    updated ();
                    return Source.REMOVE;
                });
                return null;
            });
        }
    }
}
