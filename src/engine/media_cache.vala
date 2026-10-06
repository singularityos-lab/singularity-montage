using Singularity.Imaging;

namespace Singularity.Apps.Montage {
    public class Peaks : Object {
        public int per_second = 100;
        public float[] values;

        public float at (double seconds) {
            int i = (int) (seconds * per_second);
            if (i < 0 || i >= values.length) return 0;
            return values[i];
        }
    }

    public class MediaCache : Object {
        Gee.HashMap<string, Peaks> peaks = new Gee.HashMap<string, Peaks> ();
        Gee.HashMap<string, Gdk.Pixbuf> thumbs = new Gee.HashMap<string, Gdk.Pixbuf> ();
        Gee.HashSet<string> pending = new Gee.HashSet<string> ();
        public signal void ready ();
        ThreadPool<CacheJob>? pool;

        class CacheJob {
            public string kind;
            public string uri;
            public int64 time;
            public string key;
        }

        public MediaCache () {
            try {
                pool = new ThreadPool<CacheJob>.with_owned_data ((job) => run (job), 2, false);
            } catch (ThreadError e) {
                warning ("media cache: %s", e.message);
            }
        }

        public static string dir (string kind) {
            return Path.build_filename (Environment.get_user_cache_dir (), "singularity-montage", kind);
        }

        static string stamp (string uri) {
            try {
                var info = File.new_for_uri (uri).query_info ("time::modified,standard::size", FileQueryInfoFlags.NONE);
                return Checksum.compute_for_string (ChecksumType.SHA1, "%s|%lld|%lld".printf (uri, (int64) info.get_attribute_uint64 ("time::modified"), info.get_size ()));
            } catch (Error e) {
                return Checksum.compute_for_string (ChecksumType.SHA1, uri);
            }
        }

        public Peaks? get_peaks (string uri) {
            if (peaks.has_key (uri)) return peaks[uri];
            string key = "peaks|" + uri;
            if (pending.add (key)) {
                var job = new CacheJob ();
                job.kind = "peaks";
                job.uri = uri;
                job.key = key;
                try { pool.add (job); } catch (ThreadError e) { }
            }
            return null;
        }

        public Gdk.Pixbuf? get_thumb (string uri, int64 time) {
            int64 bucket = time / 1000000000;
            string key = "%s@%lld".printf (uri, bucket);
            if (thumbs.has_key (key)) return thumbs[key];
            if (pending.add ("thumb|" + key)) {
                var job = new CacheJob ();
                job.kind = "thumb";
                job.uri = uri;
                job.time = bucket * 1000000000;
                job.key = key;
                try { pool.add (job); } catch (ThreadError e) { }
            }
            return null;
        }

        void run (CacheJob job) {
            if (job.kind == "peaks") {
                var p = compute_peaks (job.uri);
                Idle.add (() => {
                    if (p != null) peaks[job.uri] = p;
                    ready ();
                    return Source.REMOVE;
                });
            } else {
                var t = compute_thumb (job.uri, job.time);
                Idle.add (() => {
                    if (t != null) thumbs[job.key] = t;
                    ready ();
                    return Source.REMOVE;
                });
            }
        }

        public static Peaks? compute_peaks (string uri) {
            string file = Path.build_filename (dir ("peaks"), stamp (uri) + ".peaks");
            var p = new Peaks ();
            try {
                uint8[] data;
                if (FileUtils.get_data (file, out data) && data.length % 4 == 0) {
                    p.values = new float[data.length / 4];
                    Memory.copy (p.values, data, data.length);
                    return p;
                }
            } catch (Error e) {
            }
            try {
                var probe = Probe.probe (uri);
                if (!probe.has_audio) return null;
                var reader = new AudioReader (uri, 48000);
                var values = new Gee.ArrayList<float?> ();
                int block = 480 * 50;
                var buf = new float[block * 2];
                int64 start = 0;
                int silent_blocks = 0;
                int64 limit = int64.min (48000L * 60 * 60 * 4, probe.duration * 48000 / Tc.SECOND);
                while (start < limit) {
                    reader.read (start, block, buf);
                    bool any = false;
                    for (int k = 0; k < 50; k++) {
                        float peak = 0;
                        for (int i = k * 480; i < (k + 1) * 480; i++) peak = float.max (peak, float.max (buf[i * 2].abs (), buf[i * 2 + 1].abs ()));
                        values.add (peak);
                        if (peak > 0) any = true;
                    }
                    start += block;
                    silent_blocks = any ? 0 : silent_blocks + 1;
                    if (silent_blocks > 2 && reader_done (reader)) break;
                }
                reader.close ();
                p.values = new float[values.size];
                for (int i = 0; i < values.size; i++) p.values[i] = values[i];
                DirUtils.create_with_parents (dir ("peaks"), 0700);
                uint8[] bytes = new uint8[p.values.length * 4];
                Memory.copy (bytes, p.values, bytes.length);
                FileUtils.set_data (file, bytes);
                return p;
            } catch (Error e) {
                warning ("peaks %s: %s", uri, e.message);
                return null;
            }
        }

        static bool reader_done (AudioReader r) {
            return r.at_end;
        }

        public static Gdk.Pixbuf? compute_thumb (string uri, int64 time) {
            string file = Path.build_filename (dir ("thumbs"), "%s-%lld.png".printf (stamp (uri), time / 1000000000));
            try {
                if (FileUtils.test (file, FileTest.EXISTS)) return new Gdk.Pixbuf.from_file (file);
                var m = Probe.probe (uri);
                if (!m.has_video) return null;
                int h = 72;
                int w = int.max (2, (int) (h * (double) m.width / int.max (1, m.height))) & ~1;
                FloatImage img;
                if (m.still) {
                    return new Gdk.Pixbuf.from_file_at_scale (File.new_for_uri (uri).get_path (), w, h, false);
                }
                var reader = new VideoReader (uri, w, h);
                var f = reader.frame_at (int64.min (time, int64.max (0, m.duration - 50000000)));
                reader.close ();
                if (f == null) return null;
                img = ColorPipeline.to_working (f, "sdr", "rec709", "rec709");
                DirUtils.create_with_parents (dir ("thumbs"), 0700);
                ImageWriters.png (img, file, false);
                return new Gdk.Pixbuf.from_file (file);
            } catch (Error e) {
                warning ("thumb %s: %s", uri, e.message);
                return null;
            }
        }
    }
}
