using Singularity.Imaging;

namespace Singularity.Apps.Montage {
    public class RenderedFrame : Object {
        public int64 time;
        public Gdk.Texture texture;
        public FloatImage? image;
    }

    public class AudioOut : Object {
        Gst.Pipeline? pipeline;
        Gst.App.Src? src;
        public int rate = 48000;
        public bool available { get; private set; }

        public AudioOut () {
            string desc = Environment.get_variable ("MONTAGE_AUDIO_SINK") ?? "autoaudiosink";
            try {
                pipeline = (Gst.Pipeline) Gst.parse_launch ("appsrc name=src format=time block=true ! audioconvert ! audioresample ! volume name=vol ! %s".printf (desc));
                src = (Gst.App.Src) pipeline.get_by_name ("src");
                src.caps = Gst.Caps.from_string ("audio/x-raw,format=F32LE,layout=interleaved,rate=%d,channels=2,channel-mask=(bitmask)0x3".printf (rate));
                src.max_bytes = rate * 8 / 5;
                available = true;
            } catch (Error e) {
                warning ("audio output: %s", e.message);
            }
        }

        public bool start () {
            if (!available) return false;
            pipeline.set_state (Gst.State.NULL);
            if (pipeline.set_state (Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE) {
                available = false;
                return false;
            }
            return true;
        }

        public bool push (float[] data, int frames, int64 pts) {
            if (src == null) return false;
            uint8[] bytes = new uint8[frames * 8];
            Memory.copy (bytes, data, bytes.length);
            var buf = new Gst.Buffer.wrapped ((owned) bytes);
            buf.pts = pts;
            buf.duration = (int64) frames * Gst.SECOND / rate;
            return src.push_buffer (buf) == Gst.FlowReturn.OK;
        }

        public int64 position () {
            int64 p = 0;
            if (pipeline != null && pipeline.query_position (Gst.Format.TIME, out p)) return p;
            return -1;
        }

        public void stop () {
            if (pipeline != null) pipeline.set_state (Gst.State.NULL);
        }

        public void set_volume (double v) {
            if (pipeline == null) return;
            pipeline.get_by_name ("vol").set ("volume", v);
        }
    }

    public class Playback : Object {
        public signal void frame (RenderedFrame f);
        public signal void position_changed (int64 time);
        public signal void state_changed ();
        public signal void trim_preview (Gdk.Texture? left, Gdk.Texture? right);
        public Project project;
        public Sequence? custom;
        public double preview_scale = 0.5;
        public FrameCache? cache;
        public int64 position { get; private set; }
        public double rate { get; private set; }
        public bool proxies = true;
        public bool keep_images;
        public int64 loop_end = -1;
        Mutex mutex;
        Cond cond;
        int generation;
        int64 request_time = -1;
        double request_rate;
        Project? snapshot;
        Sequence? snapshot_seq;
        int snapshot_revision = -1;
        bool quit;
        Gee.ArrayQueue<RenderedFrame> queue = new Gee.ArrayQueue<RenderedFrame> ();
        int64 play_origin;
        int64 clock_origin;
        uint tick_id;
        AudioOut audio;
        Thread<void*>? worker;
        Thread<void*>? audio_worker;
        int audio_generation;
        public AudioMixer? live_mixer;
        public int64 rendered_frames;
        public int64 dropped_frames;

        public Playback (Project project) {
            this.project = project;
            audio = new AudioOut ();
            worker = new Thread<void*> ("montage-playback", run_worker);
        }

        public bool playing {
            get { return rate != 0; }
        }

        public Sequence sequence {
            owned get { return custom ?? project.sequence; }
        }

        public void shutdown () {
            mutex.lock ();
            quit = true;
            generation++;
            cond.broadcast ();
            mutex.unlock ();
            stop_audio ();
            if (tick_id != 0) Source.remove (tick_id);
            tick_id = 0;
            if (worker != null) worker.join ();
            worker = null;
        }

        Project take_snapshot () {
            if (custom != null) {
                var p = project.clone ();
                p.sequences.add (custom.copy ());
                p.active = custom.id;
                return p;
            }
            if (snapshot == null || snapshot_revision != project.revision || snapshot.active != project.active) {
                snapshot = project.clone ();
                snapshot_revision = project.revision;
            }
            return snapshot;
        }

        public void invalidate () {
            snapshot_revision = -1;
            if (!playing) seek (position);
            else play (rate);
        }

        public void seek (int64 t) {
            var seq = sequence;
            t = t.clamp (0, int64.max (0, seq.duration));
            position = t;
            position_changed (t);
            if (playing) {
                play (rate);
                return;
            }
            var snap = take_snapshot ();
            mutex.lock ();
            generation++;
            request_time = t;
            request_rate = 0;
            snapshot_seq = snap.sequence;
            snapshot = snap;
            queue.clear ();
            cond.broadcast ();
            mutex.unlock ();
        }

        public void play (double new_rate) {
            if (new_rate == 0) {
                pause ();
                return;
            }
            var seq = sequence;
            if (new_rate > 0 && position >= seq.duration - seq.frame) position = 0;
            var snap = take_snapshot ();
            stop_audio ();
            mutex.lock ();
            generation++;
            request_time = position;
            request_rate = new_rate;
            snapshot = snap;
            snapshot_seq = snap.sequence;
            queue.clear ();
            cond.broadcast ();
            mutex.unlock ();
            rate = new_rate;
            play_origin = position;
            clock_origin = get_monotonic_time ();
            if (new_rate == 1 && audio.available) start_audio (snap, position);
            if (tick_id == 0) tick_id = Timeout.add (8, tick);
            state_changed ();
        }

        public void pause () {
            if (!playing) return;
            rate = 0;
            stop_audio ();
            if (tick_id != 0) Source.remove (tick_id);
            tick_id = 0;
            mutex.lock ();
            generation++;
            request_time = position;
            request_rate = 0;
            queue.clear ();
            cond.broadcast ();
            mutex.unlock ();
            state_changed ();
        }

        public void toggle () {
            if (playing) pause ();
            else play (1);
        }

        int64 clock_now () {
            if (rate == 1 && audio_generation > 0) {
                int64 p = audio.position ();
                if (p >= 0) return play_origin + p;
            }
            return play_origin + (int64) ((get_monotonic_time () - clock_origin) * 1000 * rate);
        }

        bool tick () {
            if (!playing) {
                tick_id = 0;
                return Source.REMOVE;
            }
            int64 now = clock_now ();
            var seq = sequence;
            int64 end = loop_end > 0 ? loop_end : seq.duration;
            if ((rate > 0 && now >= end) || (rate < 0 && now <= 0)) {
                position = rate > 0 ? int64.max (0, end - seq.frame) : 0;
                pause ();
                seek (position);
                return Source.REMOVE;
            }
            RenderedFrame? show = null;
            mutex.lock ();
            while (queue.size > 0) {
                var head = queue.peek_head ();
                bool due = rate > 0 ? head.time <= now : head.time >= now;
                if (!due) break;
                if (show != null) dropped_frames++;
                show = queue.poll_head ();
            }
            cond.broadcast ();
            mutex.unlock ();
            position = now.clamp (0, seq.duration);
            if (show != null) frame (show);
            position_changed (position);
            return Source.CONTINUE;
        }

        void start_audio (Project snap, int64 from) {
            if (!audio.start ()) return;
            audio_generation++;
            int my = audio_generation;
            var seq = snap.sequence;
            var mixer = new AudioMixer (snap, seq, audio.rate, proxies);
            mixer.meter = new Singularity.Audio.LoudnessMeter (audio.rate, 2);
            live_mixer = mixer;
            int64 sample = mixer.to_sample (from);
            int64 end = mixer.to_sample (seq.duration);
            audio_worker = new Thread<void*> ("montage-audio", () => {
                int block = 2048;
                var buf = new float[block * 2];
                int64 first = sample;
                while (AtomicInt.get (ref audio_generation) == my && sample < end) {
                    mixer.render (sample, block, buf);
                    if (!audio.push (buf, block, mixer.to_time (sample - first))) break;
                    sample += block;
                }
                mixer.close ();
                return null;
            });
        }

        void stop_audio () {
            if (audio_worker == null) return;
            AtomicInt.inc (ref audio_generation);
            audio.stop ();
            audio_worker.join ();
            audio_worker = null;
        }

        public void set_volume (double v) {
            audio.set_volume (v);
        }

        void* run_worker () {
            Renderer? renderer = null;
            Project? renderer_project = null;
            while (true) {
                mutex.lock ();
                while (!quit && request_time < 0) cond.wait (mutex);
                if (quit) {
                    mutex.unlock ();
                    break;
                }
                int gen = generation;
                int64 t = request_time;
                double r = request_rate;
                var snap = snapshot;
                request_time = -1;
                mutex.unlock ();
                if (snap == null) continue;
                if (renderer == null || renderer_project != snap) {
                    if (renderer != null) renderer.close ();
                    renderer = new Renderer (snap, snap.sequence, preview_scale, proxies);
                    renderer.cache = cache;
                    renderer_project = snap;
                }
                var seq = snap.sequence;
                if (r == 0) {
                    var f = render (renderer, t);
                    mutex.lock ();
                    bool current = gen == generation;
                    mutex.unlock ();
                    if (current) Idle.add (() => {
                        frame (f);
                        return Source.REMOVE;
                    });
                    continue;
                }
                int64 step = (int64) (seq.frame * r.abs ());
                if (r.abs () > 1) step = (int64) (seq.frame * Math.ceil (r.abs ()));
                int64 frame_t = seq.snap (t);
                while (true) {
                    mutex.lock ();
                    while (!quit && gen == generation && queue.size >= 6) cond.wait_until (mutex, get_monotonic_time () + 50000);
                    bool stale = quit || gen != generation;
                    mutex.unlock ();
                    if (stale) break;
                    if (frame_t < 0 || frame_t > seq.duration) break;
                    var f = render (renderer, frame_t);
                    mutex.lock ();
                    if (gen == generation) queue.offer_tail (f);
                    mutex.unlock ();
                    frame_t += r > 0 ? step : -step;
                }
            }
            if (renderer != null) renderer.close ();
            return null;
        }

        RenderedFrame render (Renderer renderer, int64 t) {
            var img = renderer.render (t);
            var bytes = new Bytes.take (ColorPipeline.encode_rgba8 (img, true));
            var f = new RenderedFrame ();
            f.time = t;
            f.texture = new Gdk.MemoryTexture (img.width, img.height, Gdk.MemoryFormat.R8G8B8A8, bytes, img.width * 4);
            if (keep_images) f.image = img;
            AtomicInt.inc (ref rendered_count);
            return f;
        }

        int rendered_count;

        public int frames_rendered {
            get { return AtomicInt.get (ref rendered_count); }
        }
    }
}
