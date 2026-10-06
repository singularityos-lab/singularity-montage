namespace Singularity.Apps.Montage {
    namespace TestKit {
        public int failures = 0;
        public int checks = 0;

        public void check (bool condition, string message) {
            checks++;
            if (!condition) {
                failures++;
                printerr ("FAIL: %s\n", message);
            }
        }

        public void close_to (double a, double b, double tolerance, string message) {
            check ((a - b).abs () <= tolerance, "%s (got %g, expected %g)".printf (message, a, b));
        }

        public string out_dir () {
            string dir = Environment.get_variable ("MONTAGE_TEST_OUT") ?? Path.build_filename (Environment.get_tmp_dir (), "montage-test-out");
            DirUtils.create_with_parents (dir, 0755);
            return dir;
        }

        public string path (string name) {
            return Path.build_filename (out_dir (), name);
        }

        public void init (string[] args) {
            unowned string[] a = args;
            Gst.init (ref a);
            Environment.set_variable ("MONTAGE_DISABLE_HARDWARE", "1", true);
            Encoders.set_hardware_decoding (false);
            Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
        }

        public int finish (string name) {
            if (failures > 0) {
                printerr ("%s: %d of %d checks failed\n", name, failures, checks);
                return 1;
            }
            print ("%s: %d checks passed\n", name, checks);
            return 0;
        }

        public uint8 frame_red (int i) {
            return (uint8) ((i * 9) % 240 + 8);
        }

        public uint8 frame_green (int i) {
            return (uint8) (((i / 26) * 40) % 240 + 8);
        }

        public string make_video (string name, int frames, int fps, int w, int h, bool audio, double tone = 440, string blue_text = "") throws Error {
            string file = path (name);
            if (FileUtils.test (file, FileTest.EXISTS)) return file;
            string desc = "appsrc name=v format=time ! videoconvert ! vp9enc deadline=1 cpu-used=8 end-usage=cq cq-level=4 ! queue ! mux. ";
            if (audio) desc += "appsrc name=a format=time ! audioconvert ! opusenc bitrate=128000 ! queue ! mux. ";
            desc += "webmmux name=mux ! filesink location=\"%s\"".printf (file);
            var pipeline = (Gst.Pipeline) Gst.parse_launch (desc);
            var v = (Gst.App.Src) pipeline.get_by_name ("v");
            v.caps = Gst.Caps.from_string ("video/x-raw,format=RGBA,width=%d,height=%d,framerate=%d/1".printf (w, h, fps));
            Gst.App.Src? a = audio ? (Gst.App.Src) pipeline.get_by_name ("a") : null;
            if (a != null) a.caps = Gst.Caps.from_string ("audio/x-raw,format=F32LE,layout=interleaved,rate=48000,channels=2,channel-mask=(bitmask)0x3");
            pipeline.set_state (Gst.State.PLAYING);
            int64 frame_ns = Gst.SECOND / fps;
            int samples_per_frame = 48000 / fps;
            for (int i = 0; i < frames; i++) {
                var data = new uint8[w * h * 4];
                for (int p = 0; p < w * h; p++) {
                    data[p * 4] = frame_red (i);
                    data[p * 4 + 1] = frame_green (i);
                    data[p * 4 + 2] = (uint8) ((p % w) * 255 / w);
                    data[p * 4 + 3] = 255;
                }
                var buf = new Gst.Buffer.wrapped ((owned) data);
                buf.pts = i * frame_ns;
                buf.duration = frame_ns;
                v.push_buffer (buf);
                if (a != null) {
                    var s = new float[samples_per_frame * 2];
                    for (int k = 0; k < samples_per_frame; k++) {
                        int64 n = (int64) i * samples_per_frame + k;
                        float val = (float) (0.25 * Math.sin (2 * Math.PI * tone * n / 48000.0));
                        s[k * 2] = val;
                        s[k * 2 + 1] = val;
                    }
                    uint8[] bytes = new uint8[s.length * 4];
                    Memory.copy (bytes, s, bytes.length);
                    var ab = new Gst.Buffer.wrapped ((owned) bytes);
                    ab.pts = i * frame_ns;
                    ab.duration = frame_ns;
                    a.push_buffer (ab);
                }
            }
            v.end_of_stream ();
            if (a != null) a.end_of_stream ();
            var msg = pipeline.get_bus ().timed_pop_filtered (60 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR);
            pipeline.set_state (Gst.State.NULL);
            if (msg == null || msg.type == Gst.MessageType.ERROR) throw new IOError.FAILED ("could not create test media");
            return file;
        }

        public string make_wav (string name, double seconds, double tone, double amplitude) throws Error {
            string file = path (name);
            if (FileUtils.test (file, FileTest.EXISTS)) return file;
            var pipeline = (Gst.Pipeline) Gst.parse_launch ("appsrc name=a format=time ! audioconvert ! wavenc ! filesink location=\"%s\"".printf (file));
            var a = (Gst.App.Src) pipeline.get_by_name ("a");
            a.caps = Gst.Caps.from_string ("audio/x-raw,format=F32LE,layout=interleaved,rate=48000,channels=2,channel-mask=(bitmask)0x3");
            pipeline.set_state (Gst.State.PLAYING);
            int total = (int) (seconds * 48000);
            int block = 4800;
            for (int start = 0; start < total; start += block) {
                int n = int.min (block, total - start);
                var s = new float[n * 2];
                for (int k = 0; k < n; k++) {
                    float val = tone > 0 ? (float) (amplitude * Math.sin (2 * Math.PI * tone * (start + k) / 48000.0)) : (float) amplitude;
                    s[k * 2] = val;
                    s[k * 2 + 1] = val;
                }
                uint8[] bytes = new uint8[s.length * 4];
                Memory.copy (bytes, s, bytes.length);
                var b = new Gst.Buffer.wrapped ((owned) bytes);
                b.pts = (int64) start * Gst.SECOND / 48000;
                b.duration = (int64) n * Gst.SECOND / 48000;
                a.push_buffer (b);
            }
            a.end_of_stream ();
            var msg = pipeline.get_bus ().timed_pop_filtered (60 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR);
            pipeline.set_state (Gst.State.NULL);
            if (msg == null || msg.type == Gst.MessageType.ERROR) throw new IOError.FAILED ("could not create test audio");
            return file;
        }

        public void save_png (Singularity.Imaging.FloatImage img, string name) {
            try {
                ImageWriters.png (img, path (name), false);
            } catch (Error e) {
                printerr ("png: %s\n", e.message);
            }
        }
    }
}
