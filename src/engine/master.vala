namespace Singularity.Apps.Montage.Master {

    string? encoders_cache = null;

    public string? ffmpeg_path () {
        string? forced = Environment.get_variable ("MONTAGE_FFMPEG");
        if (forced != null && forced != "") return FileUtils.test (forced, FileTest.IS_EXECUTABLE) ? forced : null;
        return Environment.find_program_in_path ("ffmpeg");
    }

    string forced_backend () {
        return Environment.get_variable ("MONTAGE_MASTER_BACKEND") ?? "";
    }

    public string gst_element (string codec) {
        switch (codec) {
            case "dnxhr": return "avenc_dnxhd";
            case "ffv1": return "avenc_ffv1";
            default: return "avenc_prores_ks";
        }
    }

    public string ffmpeg_encoder (string codec) {
        switch (codec) {
            case "dnxhr": return "dnxhd";
            case "ffv1": return "ffv1";
            default: return "prores_ks";
        }
    }

    string muxer (string codec) {
        return codec == "ffv1" ? "matroskamux" : "qtmux";
    }

    bool gst_ready (string codec) {
        var enc = Gst.ElementFactory.find (gst_element (codec));
        var mux = Gst.ElementFactory.find (muxer (codec));
        if (enc == null || mux == null || Gst.ElementFactory.find ("audioconvert") == null) return false;
        foreach (var t in enc.get_static_pad_templates ()) {
            if (t.direction == Gst.PadDirection.SRC && !mux.can_sink_any_caps (t.get_caps ())) return false;
        }
        return true;
    }

    bool ffmpeg_ready (string codec) {
        string? ff = ffmpeg_path ();
        if (ff == null) return false;
        if (encoders_cache == null) {
            string listing = "";
            try {
                string[] argv = { ff, "-hide_banner", "-encoders" };
                Process.spawn_sync (null, argv, null, SpawnFlags.STDERR_TO_DEV_NULL, null, out listing, null, null);
            } catch (Error e) {
                listing = "";
            }
            encoders_cache = listing;
        }
        return encoders_cache.contains (" " + ffmpeg_encoder (codec) + " ");
    }

    public void reset () {
        encoders_cache = null;
    }

    public string backend (string codec) {
        string forced = forced_backend ();
        if (forced == "none") return "";
        if (forced != "gstreamer" && forced != "ffmpeg") forced = "";
        if (forced != "ffmpeg" && gst_ready (codec)) return "gstreamer";
        if (forced != "gstreamer" && ffmpeg_ready (codec)) return "ffmpeg";
        return "";
    }

    public bool audio_first (string codec) {
        return backend (codec) == "ffmpeg";
    }

    public bool available (string codec) {
        return backend (codec) != "";
    }

    public string describe (string codec) {
        switch (backend (codec)) {
            case "gstreamer": return "GStreamer " + gst_element (codec);
            case "ffmpeg": return "FFmpeg " + ffmpeg_encoder (codec);
            default: return "";
        }
    }

    public string install_hint () {
        return _("ProRes, DNxHR and FFV1 masters need the GStreamer libav plugins or the ffmpeg program.");
    }

    int layout_for (string codec) {
        if (codec == "prores4444") return 2;
        if (codec == "ffv1") return 1;
        return 0;
    }

    public abstract class Writer : Object {
        public string encoder = "";
        protected int width;
        protected int height;
        protected int fps_n;
        protected int fps_d;
        protected int rate;
        protected int layout;

        public abstract void video (uint16[] rgba) throws Error;
        public abstract void audio (float[] samples, int frames) throws Error;
        public abstract void finish () throws Error;
        public abstract void abort ();
    }

    public Writer open (string path, string codec, int width, int height, int fps_n, int fps_d, int rate, string? audio_file = null) throws Error {
        switch (backend (codec)) {
            case "gstreamer": return new GstWriter (path, codec, width, height, fps_n, fps_d, rate);
            case "ffmpeg": return new FfmpegWriter (path, codec, width, height, fps_n, fps_d, rate, audio_file);
            default: throw new IOError.NOT_SUPPORTED (install_hint ());
        }
    }

    class GstWriter : Writer {
        Gst.Pipeline pipeline;
        Gst.App.Src vsrc;
        Gst.App.Src? asrc;
        Gst.Video.Info info;
        int64 frame_index;
        int64 sample_index;

        public GstWriter (string path, string codec, int width, int height, int fps_n, int fps_d, int rate) throws Error {
            this.width = width;
            this.height = height;
            this.fps_n = fps_n;
            this.fps_d = fps_d;
            this.rate = rate;
            layout = layout_for (codec);
            string element = gst_element (codec);
            encoder = "GStreamer " + element;
            var format = layout == 2 ? Gst.Video.Format.A444_10LE : (layout == 1 ? Gst.Video.Format.Y444_10LE : Gst.Video.Format.I422_10LE);
            info = new Gst.Video.Info ();
            info.set_format (format, width, height);
            string fmt_name = format.to_string ();
            var desc = new StringBuilder ();
            desc.append ("appsrc name=vsrc format=time block=true max-bytes=%u caps=\"video/x-raw,format=%s,width=%d,height=%d,framerate=%d/%d,pixel-aspect-ratio=1/1,interlace-mode=progressive,colorimetry=bt709\" ! %s name=venc ! queue max-size-time=0 max-size-buffers=0 max-size-bytes=0 ! mux.video_%%u "
                .printf ((uint) (info.size * 4), fmt_name, width, height, fps_n, fps_d, element));
            if (rate > 0) {
                desc.append ("appsrc name=asrc format=time block=true caps=\"audio/x-raw,format=F32LE,layout=interleaved,rate=%d,channels=2,channel-mask=(bitmask)0x3\" ! audioconvert ! audio/x-raw,format=S24LE ! queue max-size-time=0 max-size-buffers=0 max-size-bytes=0 ! mux.audio_%%u "
                    .printf (rate));
            }
            desc.append ("%s name=mux ! filesink name=output".printf (muxer (codec)));
            pipeline = (Gst.Pipeline) Gst.parse_launch (desc.str);
            pipeline.get_by_name ("output").set ("location", path);
            vsrc = (Gst.App.Src) pipeline.get_by_name ("vsrc");
            asrc = rate > 0 ? (Gst.App.Src) pipeline.get_by_name ("asrc") : null;
            var venc = pipeline.get_by_name ("venc");
            switch (codec) {
                case "prores": option (venc, "profile", "hq"); break;
                case "prores4444": option (venc, "profile", "4444"); break;
                case "dnxhr": option (venc, "profile", "dnxhr_hqx"); break;
                case "ffv1":
                    option (venc, "level", "3");
                    option (venc, "slicecrc", "1");
                    break;
            }
            if (pipeline.set_state (Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE) {
                pipeline.set_state (Gst.State.NULL);
                throw new IOError.FAILED (_("The master encoder could not start."));
            }
        }

        static void option (Gst.Element e, string name, string value) {
            if (e.get_class ().find_property (name) != null) Gst.Util.set_object_arg (e, name, value);
        }

        void check_bus () throws Error {
            var msg = pipeline.get_bus ().pop_filtered (Gst.MessageType.ERROR);
            if (msg == null) return;
            Error err;
            string debug;
            msg.parse_error (out err, out debug);
            throw new IOError.FAILED (err.message);
        }

        public override void video (uint16[] rgba) throws Error {
            check_bus ();
            var data = new uint8[info.size];
            size_t[] offsets = { info.offset[0], info.offset[1], info.offset[2], info.offset[3] };
            int[] strides = { info.stride[0], info.stride[1], info.stride[2], info.stride[3] };
            MasterPack.pack (rgba, width, height, layout, data, offsets, strides);
            var buf = new Gst.Buffer.wrapped ((owned) data);
            uint64 unit = (uint64) Gst.SECOND * fps_d;
            buf.pts = Gst.Util.uint64_scale ((uint64) frame_index, unit, fps_n);
            buf.duration = Gst.Util.uint64_scale ((uint64) frame_index + 1, unit, fps_n) - buf.pts;
            frame_index++;
            if (vsrc.push_buffer (buf) != Gst.FlowReturn.OK) check_bus ();
        }

        public override void audio (float[] samples, int frames) throws Error {
            if (asrc == null || frames <= 0) return;
            uint8[] bytes = new uint8[frames * 8];
            Memory.copy (bytes, samples, bytes.length);
            var buf = new Gst.Buffer.wrapped ((owned) bytes);
            buf.pts = Gst.Util.uint64_scale ((uint64) sample_index, Gst.SECOND, rate);
            buf.duration = Gst.Util.uint64_scale ((uint64) (sample_index + frames), Gst.SECOND, rate) - buf.pts;
            sample_index += frames;
            if (asrc.push_buffer (buf) != Gst.FlowReturn.OK) check_bus ();
        }

        public override void finish () throws Error {
            vsrc.end_of_stream ();
            if (asrc != null) asrc.end_of_stream ();
            var msg = pipeline.get_bus ().timed_pop_filtered (Gst.CLOCK_TIME_NONE, Gst.MessageType.EOS | Gst.MessageType.ERROR);
            string? failure = null;
            if (msg != null && msg.type == Gst.MessageType.ERROR) {
                Error err;
                string debug;
                msg.parse_error (out err, out debug);
                failure = err.message;
            }
            pipeline.set_state (Gst.State.NULL);
            if (failure != null) throw new IOError.FAILED (failure);
        }

        public override void abort () {
            pipeline.set_state (Gst.State.NULL);
        }
    }

    class FfmpegWriter : Writer {
        Subprocess proc;
        OutputStream input;
        size_t[] offsets;
        int[] strides;
        size_t frame_size;

        public FfmpegWriter (string path, string codec, int width, int height, int fps_n, int fps_d, int rate, string? audio_file) throws Error {
            this.width = width;
            this.height = height;
            this.fps_n = fps_n;
            this.fps_d = fps_d;
            this.rate = rate;
            layout = layout_for (codec);
            string ff = ffmpeg_path ();
            encoder = "FFmpeg " + ffmpeg_encoder (codec);
            string pix = layout == 2 ? "yuva444p10le" : (layout == 1 ? "yuv444p10le" : "yuv422p10le");
            int cw = layout == 0 ? (width + 1) / 2 : width;
            size_t luma = (size_t) width * height * 2, chroma = (size_t) cw * height * 2;
            offsets = { 0, luma, luma + chroma, luma + chroma * 2 };
            strides = { width * 2, cw * 2, cw * 2, width * 2 };
            frame_size = luma + chroma * 2 + (layout == 2 ? luma : 0);
            string[] colour = { "-color_range", "tv", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709" };
            string[] args = { ff, "-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", pix,
                "-s", "%dx%d".printf (width, height), "-framerate", "%d/%d".printf (fps_n, fps_d) };
            foreach (var a in colour) args += a;
            foreach (var a in new string[] { "-i", "pipe:0" }) args += a;
            if (audio_file != null && rate > 0) {
                foreach (var a in new string[] { "-f", "f32le", "-ar", rate.to_string (), "-ac", "2", "-i", audio_file, "-map", "0:v", "-map", "1:a", "-c:a", "pcm_s24le" }) args += a;
            }
            args += "-c:v";
            args += ffmpeg_encoder (codec);
            switch (codec) {
                case "prores":
                    foreach (var a in new string[] { "-profile:v", "3", "-vendor", "apl0" }) args += a;
                    break;
                case "prores4444":
                    foreach (var a in new string[] { "-profile:v", "4", "-vendor", "apl0" }) args += a;
                    break;
                case "dnxhr":
                    foreach (var a in new string[] { "-profile:v", "dnxhr_hqx" }) args += a;
                    break;
                case "ffv1":
                    foreach (var a in new string[] { "-level", "3", "-slicecrc", "1" }) args += a;
                    break;
            }
            args += "-pix_fmt";
            args += pix;
            foreach (var a in colour) args += a;
            args += "-f";
            args += codec == "ffv1" ? "matroska" : "mov";
            args += path;
            Posix.signal (Posix.Signal.PIPE, Posix.SIG_IGN);
            proc = new Subprocess.newv (args, SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
            input = proc.get_stdin_pipe ();
        }

        public override void video (uint16[] rgba) throws Error {
            var data = new uint8[frame_size];
            MasterPack.pack (rgba, width, height, layout, data, offsets, strides);
            try {
                size_t written;
                input.write_all (data, out written);
            } catch (Error e) {
                string? text = null;
                try {
                    proc.communicate_utf8 (null, null, null, out text);
                } catch (Error ignored) {
                    proc.force_exit ();
                }
                text = (text ?? "").strip ();
                throw new IOError.FAILED (_("FFmpeg failed: %s").printf (text != "" ? text : e.message));
            }
        }

        public override void audio (float[] samples, int frames) throws Error {
        }

        public override void finish () throws Error {
            string? err_text;
            proc.communicate_utf8 (null, null, null, out err_text);
            if (!proc.get_successful ()) throw new IOError.FAILED (_("FFmpeg failed: %s").printf ((err_text ?? "").strip ()));
        }

        public override void abort () {
            proc.force_exit ();
            try {
                input.close ();
                proc.wait ();
            } catch (Error e) {
            }
        }
    }
}
