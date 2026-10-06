namespace Singularity.Apps.Montage {
    public class Frame : Object {
        public int64 pts;
        public int64 duration;
        public int width;
        public int height;
        public bool wide;
        public uint8[] bytes;
        public uint16[] words;
    }

    public class VideoReader : Object {
        public string uri { get; private set; }
        public int width { get; private set; }
        public int height { get; private set; }
        public bool wide { get; private set; }
        public int64 media_duration = -1;
        public string? overrides;
        Gst.Pipeline? pipeline;
        Gst.App.Sink? sink;
        Frame? current;
        Frame? upcoming;
        bool eos;
        bool broken;
        public string? failure;
        int64 frame_length = 33333333;
        public static int open_count;

        public VideoReader (string uri, int width, int height, bool wide = false) {
            this.uri = uri;
            this.width = int.max (2, width & ~1);
            this.height = int.max (2, height & ~1);
            this.wide = wide;
        }

        void open () throws Error {
            pipeline = new Gst.Pipeline (null);
            var decoder = Gst.ElementFactory.make ("uridecodebin", null);
            if (decoder == null) throw new IOError.NOT_SUPPORTED (_("GStreamer is missing uridecodebin."));
            decoder.set ("uri", uri);
            if (overrides != null && overrides != "") {
                string value = overrides;
                ((Gst.Bin) decoder).deep_element_added.connect ((bin, element) => {
                    var f = element.get_factory ();
                    if (f != null && f.get_name () == "keyframedec") element.set ("overrides", value);
                });
            }
            string caps = "video/x-raw,format=%s,width=%d,height=%d,pixel-aspect-ratio=1/1".printf (wide ? "RGBA64_LE" : "RGBA", width, height);
            var bin = (Gst.Bin) Gst.parse_bin_from_description ("videoconvert n-threads=%u ! videoscale n-threads=%u add-borders=false ! %s ! appsink name=sink sync=false max-buffers=3 enable-last-sample=false"
                .printf (uint.min (4, get_num_processors ()), uint.min (4, get_num_processors ()), caps), true);
            sink = (Gst.App.Sink) bin.get_by_name ("sink");
            pipeline.add_many (decoder, bin);
            var head = bin;
            decoder.pad_added.connect ((pad) => {
                var c = pad.get_current_caps () ?? pad.query_caps (null);
                string type = c != null && c.get_size () > 0 ? c.get_structure (0).get_name () : "";
                var target = head.get_static_pad ("sink");
                if (type.has_prefix ("video/") && !target.is_linked ()) {
                    pad.link (target);
                } else {
                    var fake = Gst.ElementFactory.make ("fakesink", null);
                    fake.set ("sync", false, "async", false);
                    pipeline.add (fake);
                    fake.sync_state_with_parent ();
                    pad.link (fake.get_static_pad ("sink"));
                }
            });
            open_count++;
            if (pipeline.set_state (Gst.State.PAUSED) == Gst.StateChangeReturn.FAILURE) throw new IOError.FAILED (_("The video decoder could not start."));
            wait_async ();
            int64 d = 0;
            if (pipeline.query_duration (Gst.Format.TIME, out d)) media_duration = d;
            pipeline.set_state (Gst.State.PLAYING);
        }

        void wait_async () throws Error {
            var bus = pipeline.get_bus ();
            int64 deadline = get_monotonic_time () + 20 * 1000000;
            while (get_monotonic_time () < deadline) {
                var msg = bus.timed_pop_filtered (100 * Gst.MSECOND, Gst.MessageType.ASYNC_DONE | Gst.MessageType.ERROR);
                if (msg == null) continue;
                if (msg.type == Gst.MessageType.ERROR) {
                    Error e;
                    string debug;
                    msg.parse_error (out e, out debug);
                    throw e;
                }
                return;
            }
            throw new IOError.TIMED_OUT (_("The video decoder did not answer in time."));
        }

        void check_bus () throws Error {
            var bus = pipeline.get_bus ();
            Gst.Message? msg;
            while ((msg = bus.pop_filtered (Gst.MessageType.ERROR)) != null) {
                Error e;
                string debug;
                msg.parse_error (out e, out debug);
                throw e;
            }
        }

        Frame? pull () throws Error {
            if (eos) return null;
            var sample = sink.try_pull_sample (10 * Gst.SECOND);
            if (sample == null) {
                check_bus ();
                eos = true;
                return null;
            }
            unowned Gst.Buffer buffer = sample.get_buffer ();
            unowned Gst.Segment segment = sample.get_segment ();
            var f = new Frame ();
            f.width = width;
            f.height = height;
            f.wide = wide;
            int64 pts = (int64) buffer.pts;
            int64 stream = (int64) segment.to_stream_time (Gst.Format.TIME, pts);
            f.pts = stream >= 0 ? stream : pts;
            unowned Gst.Caps? caps = sample.get_caps ();
            if (caps != null && caps.get_size () > 0) {
                int fn, fd;
                if (caps.get_structure (0).get_fraction ("framerate", out fn, out fd) && fn > 0 && fd > 0)
                    frame_length = (int64) ((double) Gst.SECOND * fd / fn);
            }
            bool sane = buffer.duration != Gst.CLOCK_TIME_NONE && buffer.duration > 0 && buffer.duration <= frame_length * 2;
            f.duration = sane ? (int64) buffer.duration : frame_length;
            Gst.MapInfo map;
            if (!buffer.map (out map, Gst.MapFlags.READ)) throw new IOError.FAILED (_("A video frame could not be read."));
            size_t row = (size_t) width * (wide ? 8 : 4);
            int stride = (int) row;
            unowned Gst.Video.Meta? meta = Gst.Video.buffer_get_video_meta (buffer);
            if (meta != null) stride = (int) meta.stride[0];
            else stride = (int) (map.size / height);
            if (wide) {
                f.words = new uint16[width * height * 4];
                for (int y = 0; y < height; y++) Memory.copy ((uint8*) f.words + y * row, (uint8*) map.data + y * stride, row);
            } else {
                f.bytes = new uint8[width * height * 4];
                for (int y = 0; y < height; y++) Memory.copy ((uint8*) f.bytes + y * row, (uint8*) map.data + y * stride, row);
            }
            buffer.unmap (map);
            return f;
        }

        void seek (int64 t) throws Error {
            eos = false;
            current = null;
            upcoming = null;
            if (!pipeline.seek_simple (Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.KEY_UNIT | Gst.SeekFlags.SNAP_BEFORE, int64.max (0, t)))
                throw new IOError.FAILED (_("The video could not be positioned."));
        }

        public Frame? frame_at (int64 t) throws Error {
            if (broken) throw new IOError.FAILED (failure ?? _("The video could not be decoded."));
            try {
                if (pipeline == null) open ();
                if (current != null && t >= current.pts && t < current.pts + current.duration) return current;
                if (current == null || t < current.pts || t > current.pts + 2 * Gst.SECOND) {
                    if (current != null || t > 0) seek (t);
                    current = upcoming ?? pull ();
                    upcoming = null;
                    if (current == null) return null;
                }
                while (true) {
                    if (t < current.pts + current.duration) return current;
                    if (upcoming == null) upcoming = pull ();
                    if (upcoming == null) return current;
                    current = upcoming;
                    upcoming = null;
                }
            } catch (Error e) {
                broken = true;
                failure = e.message;
                throw e;
            }
        }

        public Frame? next_after (Frame f) throws Error {
            if (upcoming == null) upcoming = pull ();
            return upcoming;
        }

        public void close () {
            if (pipeline != null) {
                pipeline.set_state (Gst.State.NULL);
                pipeline = null;
                open_count--;
            }
            sink = null;
            current = null;
            upcoming = null;
        }

        ~VideoReader () {
            close ();
        }
    }

    public class AudioReader : Object {
        public string uri { get; private set; }
        public int rate { get; private set; }
        Gst.Pipeline? pipeline;
        Gst.App.Sink? sink;
        float[] buffer = new float[0];
        int buffered;
        int64 buffer_start;
        int64 next_frame = -1;
        bool eos;
        bool silent;

        public AudioReader (string uri, int rate) {
            this.uri = uri;
            this.rate = rate;
        }

        void open () throws Error {
            pipeline = new Gst.Pipeline (null);
            var decoder = Gst.ElementFactory.make ("uridecodebin", null);
            decoder.set ("uri", uri);
            var bin = (Gst.Bin) Gst.parse_bin_from_description (
                "audioconvert ! audioresample ! audio/x-raw,format=F32LE,layout=interleaved,rate=%d,channels=2 ! appsink name=sink sync=false max-buffers=8 enable-last-sample=false".printf (rate), true);
            sink = (Gst.App.Sink) bin.get_by_name ("sink");
            pipeline.add_many (decoder, bin);
            bool linked = false;
            decoder.pad_added.connect ((pad) => {
                var c = pad.get_current_caps () ?? pad.query_caps (null);
                string type = c != null && c.get_size () > 0 ? c.get_structure (0).get_name () : "";
                var target = bin.get_static_pad ("sink");
                if (type.has_prefix ("audio/") && !target.is_linked ()) {
                    pad.link (target);
                    linked = true;
                } else {
                    var fake = Gst.ElementFactory.make ("fakesink", null);
                    fake.set ("sync", false, "async", false);
                    pipeline.add (fake);
                    fake.sync_state_with_parent ();
                    pad.link (fake.get_static_pad ("sink"));
                }
            });
            if (pipeline.set_state (Gst.State.PAUSED) == Gst.StateChangeReturn.FAILURE) throw new IOError.FAILED (_("The audio decoder could not start."));
            var bus = pipeline.get_bus ();
            int64 deadline = get_monotonic_time () + 20 * 1000000;
            while (get_monotonic_time () < deadline) {
                var msg = bus.timed_pop_filtered (100 * Gst.MSECOND, Gst.MessageType.ASYNC_DONE | Gst.MessageType.ERROR);
                if (msg == null) continue;
                if (msg.type == Gst.MessageType.ERROR) {
                    Error e;
                    string debug;
                    msg.parse_error (out e, out debug);
                    throw e;
                }
                break;
            }
            if (!linked) silent = true;
            pipeline.set_state (Gst.State.PLAYING);
        }

        void seek (int64 frame) throws Error {
            eos = false;
            buffered = 0;
            buffer_start = frame;
            next_frame = frame;
            int64 t = (int64) ((double) frame * Gst.SECOND / rate);
            if (!pipeline.seek_simple (Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.ACCURATE, t))
                throw new IOError.FAILED (_("The audio could not be positioned."));
            first_after_seek = true;
        }

        bool first_after_seek;

        bool fill () throws Error {
            if (eos) return false;
            var sample = sink.try_pull_sample (10 * Gst.SECOND);
            if (sample == null) {
                eos = true;
                return false;
            }
            unowned Gst.Buffer b = sample.get_buffer ();
            unowned Gst.Segment seg = sample.get_segment ();
            Gst.MapInfo map;
            if (!b.map (out map, Gst.MapFlags.READ)) return true;
            int frames = (int) (map.size / 8);
            int64 pts_frame = buffer_start + buffered;
            if (b.pts != Gst.CLOCK_TIME_NONE) {
                int64 stream = (int64) seg.to_stream_time (Gst.Format.TIME, b.pts);
                if (stream >= 0) pts_frame = (int64) Math.round ((double) stream * rate / Gst.SECOND);
            }
            if (first_after_seek) {
                buffer_start = pts_frame;
                buffered = 0;
                first_after_seek = false;
            }
            int64 expected = buffer_start + buffered;
            int skip = 0;
            if (pts_frame > expected + 2) {
                int gap = (int) int64.min (pts_frame - expected, rate * 10);
                grow (buffered + gap);
                for (int i = 0; i < gap * 2; i++) buffer[buffered * 2 + i] = 0;
                buffered += gap;
            } else if (pts_frame < expected - 2) {
                skip = (int) int64.min (expected - pts_frame, frames);
            }
            int use = frames - skip;
            if (use > 0) {
                grow (buffered + use);
                Memory.copy ((uint8*) buffer + buffered * 8, (uint8*) map.data + skip * 8, use * 8);
                buffered += use;
            }
            b.unmap (map);
            return true;
        }

        void grow (int frames) {
            if (buffer.length >= frames * 2) return;
            var bigger = new float[int.max (frames * 2, buffer.length * 2)];
            if (buffered > 0) Memory.copy (bigger, buffer, buffered * 8);
            buffer = bigger;
        }

        void drop_before (int64 frame) {
            int drop = (int) int64.min (buffered, int64.max (0, frame - buffer_start));
            if (drop <= 0) return;
            if (drop < buffered) Memory.move (buffer, (uint8*) buffer + drop * 8, (buffered - drop) * 8);
            buffered -= drop;
            buffer_start += drop;
        }

        public bool at_end {
            get { return eos || silent; }
        }

        public void read (int64 start_frame, int frames, float[] output) throws Error {
            for (int i = 0; i < frames * 2; i++) output[i] = 0;
            if (silent) return;
            if (start_frame < 0) {
                int skip = (int) int64.min (frames, -start_frame);
                if (skip >= frames) return;
                var rest = new float[(frames - skip) * 2];
                read (0, frames - skip, rest);
                Memory.copy ((uint8*) output + skip * 8, rest, rest.length * 4);
                return;
            }
            if (pipeline == null) {
                open ();
                if (silent) return;
                seek (start_frame);
            } else if (start_frame < buffer_start || start_frame > buffer_start + buffered + rate) {
                seek (start_frame);
            }
            drop_before (start_frame);
            while (buffer_start + buffered < start_frame + frames && fill ()) {
                if (buffer_start + buffered > start_frame + frames + rate * 4) break;
                if (start_frame > buffer_start + buffered + rate * 2) drop_before (buffer_start + buffered);
                drop_before (start_frame);
            }
            int64 offset = start_frame - buffer_start;
            for (int i = 0; i < frames; i++) {
                int64 k = offset + i;
                if (k < 0 || k >= buffered) continue;
                output[i * 2] = buffer[k * 2];
                output[i * 2 + 1] = buffer[k * 2 + 1];
            }
            next_frame = start_frame + frames;
        }

        public void close () {
            if (pipeline != null) pipeline.set_state (Gst.State.NULL);
            pipeline = null;
            sink = null;
        }

        ~AudioReader () {
            close ();
        }
    }
}
