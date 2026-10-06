using Singularity.Imaging;

namespace Singularity.Apps.Montage {
    public class ExportPreset : Object {
        public string id;
        public string name;
        public string category;
        public string container = "mp4";
        public string vcodec = "h264";
        public string acodec = "aac";
        public int width;
        public int height;
        public int fps_n;
        public int fps_d = 1;
        public int vbitrate;
        public int quality = 70;
        public int abitrate = 192;
        public int depth = 8;
        public string transfer = "sdr";
        public int max_size_mb;
        public string reframe = "fit";

        public ExportPreset (string id, string name, string category) {
            this.id = id;
            this.name = name;
            this.category = category;
        }

        public ExportPreset copy () {
            var p = new ExportPreset (id, name, category);
            p.container = container; p.vcodec = vcodec; p.acodec = acodec; p.width = width; p.height = height;
            p.fps_n = fps_n; p.fps_d = fps_d; p.vbitrate = vbitrate; p.quality = quality; p.abitrate = abitrate;
            p.depth = depth; p.transfer = transfer; p.max_size_mb = max_size_mb; p.reframe = reframe;
            return p;
        }

        public string extension {
            owned get {
                switch (container) {
                    case "matroska": return "mkv";
                    case "webm": return "webm";
                    case "mov": return "mov";
                    case "png-seq": return "png";
                    case "tiff-seq": return "tif";
                    case "exr-seq": return "exr";
                    case "wav": return "wav";
                    case "flac": return "flac";
                    case "mp3": return "mp3";
                    case "ogg": return "opus";
                    default: return "mp4";
                }
            }
        }

        public bool image_sequence {
            get { return container.has_suffix ("-seq"); }
        }

        public bool audio_only {
            get { return vcodec == "none"; }
        }

        public bool master {
            get { return vcodec == "prores" || vcodec == "prores4444" || vcodec == "dnxhr" || vcodec == "ffv1"; }
        }

        public void write (Json.Builder b) {
            b.begin_object ();
            Js.s (b, "id", id); Js.s (b, "name", name); Js.s (b, "category", category); Js.s (b, "container", container);
            Js.s (b, "vcodec", vcodec); Js.s (b, "acodec", acodec); Js.i (b, "width", width); Js.i (b, "height", height);
            Js.i (b, "fps-n", fps_n); Js.i (b, "fps-d", fps_d); Js.i (b, "vbitrate", vbitrate); Js.i (b, "quality", quality);
            Js.i (b, "abitrate", abitrate); Js.i (b, "depth", depth); Js.s (b, "transfer", transfer);
            Js.i (b, "max-size", max_size_mb); Js.s (b, "reframe", reframe);
            b.end_object ();
        }

        public static ExportPreset read (Json.Object o) {
            var p = new ExportPreset (Js.str (o, "id", new_id ()), Js.str (o, "name", _("Custom")), Js.str (o, "category", _("Custom")));
            p.container = Js.str (o, "container", "mp4"); p.vcodec = Js.str (o, "vcodec", "h264"); p.acodec = Js.str (o, "acodec", "aac");
            p.width = (int) Js.integer (o, "width"); p.height = (int) Js.integer (o, "height");
            p.fps_n = (int) Js.integer (o, "fps-n"); p.fps_d = (int) Js.integer (o, "fps-d", 1);
            p.vbitrate = (int) Js.integer (o, "vbitrate"); p.quality = (int) Js.integer (o, "quality", 70);
            p.abitrate = (int) Js.integer (o, "abitrate", 192); p.depth = (int) Js.integer (o, "depth", 8);
            p.transfer = Js.str (o, "transfer", "sdr"); p.max_size_mb = (int) Js.integer (o, "max-size"); p.reframe = Js.str (o, "reframe", "fit");
            return p;
        }
    }

    namespace Presets {
        ExportPreset make (string id, string name, string category, string container, string vcodec, string acodec, int w, int h, int vbitrate = 0) {
            var p = new ExportPreset (id, name, category);
            p.container = container;
            p.vcodec = vcodec;
            p.acodec = acodec;
            p.width = w;
            p.height = h;
            p.vbitrate = vbitrate;
            return p;
        }

        public Gee.ArrayList<ExportPreset> all () {
            var r = new Gee.ArrayList<ExportPreset> ();
            string web = _("Web"), social = _("Social"), archive = _("Archive"), master = _("Master"), images = _("Image Sequence"), audio = _("Audio");
            r.add (make ("web-1080", _("Web 1080p (H.264)"), web, "mp4", "h264", "aac", 1920, 1080, 12000));
            r.add (make ("web-720", _("Web 720p (H.264)"), web, "mp4", "h264", "aac", 1280, 720, 6000));
            r.add (make ("web-4k", _("Web 4K (H.265)"), web, "mp4", "h265", "aac", 3840, 2160, 35000));
            r.add (make ("webm-1080", _("WebM 1080p (VP9 and Opus)"), web, "webm", "vp9", "opus", 1920, 1080, 8000));
            r.add (make ("web-sequence", _("Match Sequence (H.264)"), web, "mp4", "h264", "aac", 0, 0, 0));
            var hlg = make ("youtube-hdr", _("4K HDR HLG (H.265 10 bit)"), web, "mp4", "h265", "aac", 3840, 2160, 45000);
            hlg.depth = 10;
            hlg.transfer = "hlg";
            r.add (hlg);
            var pq = make ("hdr10", _("4K HDR10 PQ (H.265 10 bit)"), web, "mp4", "h265", "aac", 3840, 2160, 45000);
            pq.depth = 10;
            pq.transfer = "pq";
            r.add (pq);
            var reels = make ("vertical-1080", _("Vertical 9:16 for Reels, Shorts and TikTok"), social, "mp4", "h264", "aac", 1080, 1920, 10000);
            reels.reframe = "fill";
            r.add (reels);
            var square = make ("square-1080", _("Square 1:1 for Feeds"), social, "mp4", "h264", "aac", 1080, 1080, 8000);
            square.reframe = "fill";
            r.add (square);
            var portrait = make ("portrait-1080", _("Portrait 4:5 for Feeds"), social, "mp4", "h264", "aac", 1080, 1350, 8000);
            portrait.reframe = "fill";
            r.add (portrait);
            var small = make ("social-small", _("Small Upload (under 50 MB)"), social, "mp4", "h264", "aac", 1280, 720, 0);
            small.max_size_mb = 50;
            r.add (small);
            var av1 = make ("archive-av1", _("Archive AV1 (MKV)"), archive, "matroska", "av1", "opus", 0, 0, 0);
            av1.quality = 85;
            r.add (av1);
            var lossless = make ("archive-h264-lossless", _("Archive Lossless H.264 (MKV and FLAC)"), archive, "matroska", "h264-lossless", "flac", 0, 0, 0);
            r.add (lossless);
            var prores = make ("master-prores", _("ProRes 422 HQ (MOV)"), master, "mov", "prores", "pcm", 0, 0, 0);
            prores.depth = 10;
            r.add (prores);
            var prores4 = make ("master-prores4444", _("ProRes 4444 with Alpha (MOV)"), master, "mov", "prores4444", "pcm", 0, 0, 0);
            prores4.depth = 10;
            r.add (prores4);
            var dnx = make ("master-dnxhr", _("DNxHR HQX (MOV)"), master, "mov", "dnxhr", "pcm", 0, 0, 0);
            dnx.depth = 10;
            r.add (dnx);
            var ffv1 = make ("master-ffv1", _("FFV1 Lossless (MKV)"), master, "matroska", "ffv1", "pcm", 0, 0, 0);
            ffv1.depth = 10;
            r.add (ffv1);
            r.add (make ("seq-png", _("PNG Sequence 16 bit"), images, "png-seq", "png", "none", 0, 0, 0));
            r.add (make ("seq-tiff", _("TIFF Sequence 16 bit"), images, "tiff-seq", "tiff", "none", 0, 0, 0));
            r.add (make ("seq-exr", _("OpenEXR Sequence (half float, linear)"), images, "exr-seq", "exr", "none", 0, 0, 0));
            r.add (make ("audio-wav", _("WAV 24 bit"), audio, "wav", "none", "pcm", 0, 0, 0));
            r.add (make ("audio-flac", _("FLAC"), audio, "flac", "none", "flac", 0, 0, 0));
            r.add (make ("audio-mp3", _("MP3 for Podcasts"), audio, "mp3", "none", "mp3", 0, 0, 0));
            r.add (make ("audio-opus", _("Opus"), audio, "ogg", "none", "opus", 0, 0, 0));
            r.add_all (user ());
            return r;
        }

        public Gee.ArrayList<ExportPreset> usable () {
            var r = new Gee.ArrayList<ExportPreset> ();
            foreach (var p in all ()) if (!p.master || Master.available (p.vcodec)) r.add (p);
            return r;
        }

        public ExportPreset? find (string id) {
            foreach (var p in all ()) if (p.id == id) return p;
            return null;
        }

        public string user_file () {
            return Path.build_filename (Environment.get_user_config_dir (), "singularity-montage", "presets.json");
        }

        public Gee.ArrayList<ExportPreset> user () {
            var r = new Gee.ArrayList<ExportPreset> ();
            try {
                string text;
                FileUtils.get_contents (user_file (), out text);
                var parser = new Json.Parser ();
                parser.load_from_data (text);
                foreach (var n in parser.get_root ().get_array ().get_elements ()) r.add (ExportPreset.read (n.get_object ()));
            } catch (Error e) {
            }
            return r;
        }

        public void save_user (ExportPreset preset) throws Error {
            var list = user ();
            preset.category = _("My Presets");
            if (!preset.id.has_prefix ("user-")) preset.id = "user-" + new_id ();
            list.add (preset);
            var b = new Json.Builder ();
            b.begin_array ();
            foreach (var p in list) p.write (b);
            b.end_array ();
            DirUtils.create_with_parents (Path.get_dirname (user_file ()), 0700);
            FileUtils.set_contents (user_file (), Js.write (b.get_root (), true));
        }
    }

    namespace Encoders {
        public bool hardware_disabled () {
            return Environment.get_variable ("MONTAGE_DISABLE_HARDWARE") == "1";
        }

        public void set_hardware_decoding (bool enabled) {
            var registry = Gst.Registry.get ();
            foreach (var feature in registry.get_feature_list (typeof (Gst.ElementFactory))) {
                var f = (Gst.ElementFactory) feature;
                string klass = f.get_metadata (Gst.ELEMENT_METADATA_KLASS) ?? "";
                if (!klass.contains ("Decoder") || !klass.contains ("Video")) continue;
                if (!is_hardware (f.get_name ())) continue;
                if (!enabled) f.set_rank (Gst.Rank.NONE);
                else if (f.get_rank () == Gst.Rank.NONE) f.set_rank (Gst.Rank.PRIMARY + 1);
            }
        }

        public bool exists (string name) {
            var f = Gst.ElementFactory.find (name);
            return f != null;
        }

        public string[] candidates (string codec, bool hardware) {
            string[] hw = {};
            string[] sw = {};
            switch (codec) {
                case "h264":
                    hw = { "vah264enc", "vah264lpenc", "vaapih264enc", "vulkanh264enc", "nvh264enc", "qsvh264enc" };
                    sw = { "x264enc", "openh264enc", "avenc_h264_vaapi" };
                    break;
                case "h264-lossless":
                    sw = { "x264enc" };
                    break;
                case "h265":
                    hw = { "vah265enc", "vah265lpenc", "vaapih265enc", "vulkanh265enc", "nvh265enc", "qsvh265enc" };
                    sw = { "x265enc", "svthevcenc" };
                    break;
                case "av1":
                    hw = { "vaav1enc", "vulkanav1enc", "nvav1enc", "qsvav1enc" };
                    sw = { "svtav1enc", "av1enc", "rav1enc" };
                    break;
                case "vp9":
                    hw = { "vavp9enc", "vaapivp9enc", "qsvvp9enc" };
                    sw = { "vp9enc" };
                    break;
                case "vp8":
                    sw = { "vp8enc" };
                    break;
                case "prores":
                case "prores4444":
                    sw = { "avenc_prores_ks" };
                    break;
                case "dnxhr":
                    sw = { "avenc_dnxhd" };
                    break;
                case "ffv1":
                    sw = { "avenc_ffv1" };
                    break;
            }
            string[] all = {};
            if (hardware && !hardware_disabled ()) foreach (var n in hw) all += n;
            foreach (var n in sw) all += n;
            return all;
        }

        public bool is_hardware (string name) {
            return name.has_prefix ("va") || name.has_prefix ("vulkan") || name.has_prefix ("nv") || name.has_prefix ("qsv") || name.has_prefix ("v4l2") || name.has_prefix ("msdk");
        }

        public string? pick (string codec, bool hardware) {
            string? forced = Environment.get_variable ("MONTAGE_FORCE_ENCODER");
            if (forced != null && forced != "" && exists (forced)) return forced;
            foreach (var n in candidates (codec, hardware)) if (exists (n)) return n;
            return null;
        }

        public string? audio (string codec) {
            switch (codec) {
                case "aac":
                    foreach (var n in new string[] { "fdkaacenc", "avenc_aac", "voaacenc", "faac" }) if (exists (n)) return n;
                    return null;
                case "opus": return exists ("opusenc") ? "opusenc" : null;
                case "flac": return exists ("flacenc") ? "flacenc" : null;
                case "mp3": return exists ("lamemp3enc") ? "lamemp3enc" : null;
                case "vorbis": return exists ("vorbisenc") ? "vorbisenc" : null;
                default: return null;
            }
        }

        public void configure (Gst.Element enc, string codec, ExportPreset p, int kbps) {
            string name = enc.get_factory ().get_name ();
            bool quality_mode = kbps <= 0;
            switch (name) {
                case "x264enc":
                    enc.set ("speed-preset", 4, "key-int-max", 120u);
                    if (codec == "h264-lossless") enc.set ("pass", 4, "quantizer", 0u);
                    else if (quality_mode) enc.set ("pass", 4, "quantizer", (uint) (51 - p.quality * 0.4).clamp (0, 51));
                    else enc.set ("bitrate", (uint) kbps);
                    break;
                case "x265enc":
                    enc.set ("speed-preset", 4);
                    if (!quality_mode) enc.set ("bitrate", (uint) kbps);
                    else enc.set ("qp", (int) (51 - p.quality * 0.4).clamp (0, 51));
                    break;
                case "openh264enc":
                    enc.set ("bitrate", (uint) (int.max (kbps, 2000) * 1000));
                    break;
                case "vp9enc":
                case "vp8enc":
                    enc.set ("deadline", (int64) 1, "cpu-used", 4, "threads", (int) uint.min (8, get_num_processors ()));
                    if (!quality_mode) enc.set ("target-bitrate", kbps * 1000);
                    else enc.set ("end-usage", 2, "cq-level", (int) (63 - p.quality * 0.55).clamp (0, 63));
                    break;
                case "svtav1enc":
                    enc.set ("preset", 10u);
                    if (!quality_mode) enc.set ("target-bitrate", (uint) kbps);
                    else enc.set ("crf", (uint) (63 - p.quality * 0.5).clamp (1, 63));
                    break;
                case "av1enc":
                    enc.set ("cpu-used", 8, "threads", uint.min (8, get_num_processors ()));
                    if (!quality_mode) enc.set ("target-bitrate", (uint) kbps);
                    break;
                default:
                    var spec = enc.get_class ().find_property ("bitrate");
                    if (spec != null && !quality_mode) {
                        var v = Value (spec.value_type);
                        if (spec.value_type == typeof (uint)) v.set_uint ((uint) kbps);
                        else if (spec.value_type == typeof (int)) v.set_int (kbps);
                        else break;
                        enc.set_property ("bitrate", v);
                    }
                    break;
            }
        }

        public string parser_for (string codec) {
            switch (codec) {
                case "h264":
                case "h264-lossless": return "h264parse";
                case "h265": return "h265parse";
                case "av1": return "av1parse";
                default: return "";
            }
        }

        public string report () {
            var sb = new StringBuilder ();
            foreach (var codec in new string[] { "h264", "h265", "av1", "vp9", "prores", "dnxhr", "ffv1" }) {
                var hw = pick (codec, true);
                var sw = pick (codec, false);
                sb.append ("%s: %s%s\n".printf (codec, hw ?? "-", hw != null && is_hardware (hw) ? " (hardware)" : ""));
                if (sw != null && sw != hw) sb.append ("  software: %s\n".printf (sw));
            }
            return sb.str;
        }
    }

    public class ExportSettings : Object {
        public ExportPreset preset;
        public File output;
        public int64 start;
        public int64 end = -1;
        public bool hardware = true;
        public string subtitles = "none";
        public bool chapters = true;
        public bool normalize;
        public double loudness_target = -14;
        public double true_peak = -1;
        public string? sequence_id;
    }

    public class ExportJob : Object {
        public string id = new_id ();
        public ExportSettings settings;
        public Project project;
        public Sequence seq;
        public string state = "queued";
        public double fraction;
        public string message = "";
        public string encoder_used = "";
        public int64 started;
        public int64 elapsed;
        int cancelled;
        public signal void progress (double fraction);
        public signal void finished (bool ok, string? error);

        public ExportJob (Project snapshot, ExportSettings settings) {
            this.project = snapshot;
            this.settings = settings;
            seq = settings.sequence_id != null ? (snapshot.find_sequence (settings.sequence_id) ?? snapshot.sequence) : snapshot.sequence;
        }

        public string title {
            owned get { return settings.output.get_basename () ?? _("Export"); }
        }

        public void cancel () {
            AtomicInt.set (ref cancelled, 1);
        }

        public bool is_cancelled {
            get { return AtomicInt.get (ref cancelled) != 0; }
        }

        void report (double f) {
            fraction = f;
            Idle.add (() => {
                progress (fraction);
                return Source.REMOVE;
            });
        }

        public void run_sync () throws Error {
            started = get_monotonic_time ();
            state = "running";
            try {
                execute ();
                state = "done";
            } catch (Error e) {
                state = is_cancelled ? "cancelled" : "failed";
                message = e.message;
                throw e;
            } finally {
                elapsed = get_monotonic_time () - started;
            }
        }

        public async void run () {
            string? failure = null;
            new Thread<void*> ("montage-export", () => {
                try {
                    run_sync ();
                } catch (Error e) {
                    failure = e.message;
                }
                Idle.add (run.callback);
                return null;
            });
            yield;
            finished (failure == null, failure);
        }

        int64 range_start () {
            return seq.snap (int64.max (0, settings.start));
        }

        int64 range_end () {
            int64 e = settings.end > 0 ? settings.end : seq.duration;
            return int64.max (range_start () + seq.frame, seq.snap (e));
        }

        void output_size (out int w, out int h) {
            w = settings.preset.width > 0 ? settings.preset.width : seq.width;
            h = settings.preset.height > 0 ? settings.preset.height : seq.height;
            w &= ~1;
            h &= ~1;
        }

        int fps_n () {
            return settings.preset.fps_n > 0 ? settings.preset.fps_n : seq.fps_n;
        }

        int fps_d () {
            return settings.preset.fps_n > 0 ? settings.preset.fps_d : seq.fps_d;
        }

        Renderer make_renderer (int w, int h) {
            double sx = (double) w / seq.width, sy = (double) h / seq.height;
            double scale = settings.preset.reframe == "fill" ? double.max (sx, sy) : double.min (sx, sy);
            var r = new Renderer (project, seq, scale, false);
            r.burn_subtitles = settings.subtitles == "burn";
            if (settings.preset.transfer != "sdr") r.working = "rec2020";
            return r;
        }

        FloatImage frame (Renderer r, int64 t, int w, int h) {
            var img = r.render (t);
            if (img.width == w && img.height == h) return img;
            var canvas = new FloatImage (w, h);
            Placement p = Placement ();
            p.scale_x = p.scale_y = 1;
            p.opacity = 1;
            Compose.place (canvas, img, p, BlendMode.NORMAL);
            return canvas;
        }

        double measure_loudness (out double peak) {
            var mixer = new AudioMixer (project, seq, seq.sample_rate);
            mixer.meter = new Singularity.Audio.LoudnessMeter (seq.sample_rate, 2);
            int64 s0 = mixer.to_sample (range_start ()), s1 = mixer.to_sample (range_end ());
            int block = 4096;
            var buf = new float[block * 2];
            for (int64 s = s0; s < s1 && !is_cancelled; s += block) {
                int n = (int) int64.min (block, s1 - s);
                mixer.render (s, n, buf);
                report (0.15 * (s - s0) / double.max (1, s1 - s0));
            }
            mixer.close ();
            peak = mixer.meter.true_peak_db;
            return mixer.meter.integrated;
        }

        double gain_for_target () {
            if (!settings.normalize || settings.preset.vcodec != "none" && settings.preset.acodec == "none") return 0;
            double peak;
            double measured = measure_loudness (out peak);
            if (measured < -100) return 0;
            double gain = settings.loudness_target - measured;
            if (peak + gain > settings.true_peak) gain = settings.true_peak - peak;
            message = _("Measured %.1f LUFS, applied %+.1f dB").printf (measured, gain);
            return gain;
        }

        void execute () throws Error {
            var p = settings.preset;
            var parent = settings.output.get_parent ();
            if (parent != null && !parent.query_exists ()) throw new IOError.NOT_FOUND (_("The destination folder does not exist."));
            foreach (var m in project.media) if (m.kind == "file" && settings.output.equal (File.new_for_uri (m.uri)))
                throw new IOError.INVALID_ARGUMENT (_("The output cannot replace a source file."));
            double gain = gain_for_target ();
            if (p.image_sequence) {
                export_images ();
            } else if (p.master) {
                export_master (gain);
            } else {
                export_gst (gain);
            }
            if (is_cancelled) throw new IOError.CANCELLED (_("Export cancelled."));
            if (settings.subtitles == "srt" || settings.subtitles == "vtt") write_sidecar ();
            if (settings.chapters && (p.container == "mp4" || p.container == "mov")) Mp4Chapters.inject (settings.output, chapters ());
        }

        public Gee.ArrayList<Marker> chapters () {
            var r = new Gee.ArrayList<Marker> ();
            int64 s = range_start (), e = range_end ();
            foreach (var m in seq.markers) if (m.kind == "chapter" && m.time >= s && m.time < e) {
                var c = m.copy ();
                c.time -= s;
                r.add (c);
            }
            return r;
        }

        void write_sidecar () throws Error {
            var cues = new Gee.ArrayList<Cue> ();
            int64 s = range_start (), e = range_end ();
            foreach (var c in Subtitles.all (seq)) {
                if (c.end <= s || c.start >= e) continue;
                cues.add (new Cue (int64.max (0, c.start - s), int64.min (e, c.end) - s, c.text));
            }
            string base_path = settings.output.get_path ();
            int dot = base_path.last_index_of (".");
            if (dot > 0) base_path = base_path.substring (0, dot);
            if (settings.subtitles == "srt") FileUtils.set_contents (base_path + ".srt", Subtitles.to_srt (cues));
            else FileUtils.set_contents (base_path + ".vtt", Subtitles.to_vtt (cues));
        }

        void export_images () throws Error {
            int w, h;
            output_size (out w, out h);
            var r = make_renderer (w, h);
            int64 s = range_start (), e = range_end ();
            int n_p = fps_n (), n_d = fps_d ();
            int64 frames = Tc.to_frames (e - s + Tc.frame_duration (n_p, n_d) / 2, n_p, n_d);
            string path = settings.output.get_path ();
            int dot = path.last_index_of (".");
            string stem = dot > 0 ? path.substring (0, dot) : path;
            string ext = settings.preset.extension;
            for (int64 i = 0; i < frames && !is_cancelled; i++) {
                int64 t = s + Tc.from_frames (i, n_p, n_d);
                var img = frame (r, t, w, h);
                string file = "%s_%06lld.%s".printf (stem, i, ext);
                switch (settings.preset.container) {
                    case "tiff-seq": ImageWriters.tiff (img, file, settings.preset.transfer); break;
                    case "exr-seq": ImageWriters.exr (img, file, r.working); break;
                    default: ImageWriters.png (img, file, true, settings.preset.transfer); break;
                }
                report (0.15 + 0.85 * (i + 1) / frames);
            }
            r.close ();
            encoder_used = settings.preset.container;
        }

        void export_master (double gain) throws Error {
            int w, h;
            output_size (out w, out h);
            var tmp = staging ();
            int64 s = range_start (), e = range_end ();
            int64 frames = Tc.to_frames (e - s + seq.frame / 2, fps_n (), fps_d ());
            string? audio_file = null;
            if (Master.audio_first (settings.preset.vcodec)) {
                audio_file = settings.output.get_parent ().get_child (".montage-%s.f32".printf (new_id ())).get_path ();
                try {
                    render_audio_file (audio_file, gain, s, frames);
                } catch (Error err) {
                    FileUtils.unlink (audio_file);
                    throw err;
                }
            }
            Master.Writer writer;
            try {
                writer = Master.open (tmp.get_path (), settings.preset.vcodec, w, h, fps_n (), fps_d (), seq.sample_rate, audio_file);
            } catch (Error err) {
                if (audio_file != null) FileUtils.unlink (audio_file);
                throw err;
            }
            encoder_used = writer.encoder;
            var r = make_renderer (w, h);
            var mixer = new AudioMixer (project, seq, seq.sample_rate);
            mixer.master_gain_db = gain;
            int64 sample = mixer.to_sample (s);
            try {
                for (int64 i = 0; i < frames && !is_cancelled; i++) {
                    int64 t = s + Tc.from_frames (i, fps_n (), fps_d ());
                    var img = frame (r, t, w, h);
                    var words = ColorPipeline.encode_rgba16 (img, "sdr");
                    if (settings.preset.vcodec == "prores4444") {
                        for (int k = 0; k < w * h; k++) words[k * 4 + 3] = (uint16) (img.data[k * 4 + 3].clamp (0, 1) * 65535);
                    }
                    writer.video (words);
                    if (audio_file != null) {
                        report (0.15 + 0.85 * (i + 1) / frames);
                        continue;
                    }
                    int64 next = mixer.to_sample (s + Tc.from_frames (i + 1, fps_n (), fps_d ()));
                    int count = (int) (next - sample);
                    var audio = new float[count * 2];
                    mixer.render (sample, count, audio);
                    sample = next;
                    writer.audio (audio, count);
                    report (0.15 + 0.85 * (i + 1) / frames);
                }
            } catch (Error err) {
                writer.abort ();
                FileUtils.unlink (tmp.get_path ());
                if (audio_file != null) FileUtils.unlink (audio_file);
                throw err;
            } finally {
                r.close ();
                mixer.close ();
            }
            try {
                writer.finish ();
            } finally {
                if (audio_file != null) FileUtils.unlink (audio_file);
            }
            if (is_cancelled) {
                tmp.delete ();
                return;
            }
            tmp.move (settings.output, FileCopyFlags.OVERWRITE);
        }

        void render_audio_file (string path, double gain, int64 s, int64 frames) throws Error {
            var mixer = new AudioMixer (project, seq, seq.sample_rate);
            mixer.master_gain_db = gain;
            var stream = new BufferedOutputStream.sized (File.new_for_path (path).replace (null, false, FileCreateFlags.PRIVATE), 1 << 20);
            int64 sample = mixer.to_sample (s);
            try {
                for (int64 i = 0; i < frames && !is_cancelled; i++) {
                    int64 next = mixer.to_sample (s + Tc.from_frames (i + 1, fps_n (), fps_d ()));
                    int count = (int) (next - sample);
                    if (count <= 0) continue;
                    var audio = new float[count * 2];
                    mixer.render (sample, count, audio);
                    sample = next;
                    uint8[] bytes = new uint8[count * 8];
                    Memory.copy (bytes, audio, bytes.length);
                    size_t written;
                    stream.write_all (bytes, out written);
                    report (0.15 * (i + 1) / frames);
                }
                stream.close ();
            } finally {
                mixer.close ();
            }
        }

        File staging () {
            var parent = settings.output.get_parent ();
            return parent.get_child (".montage-%s.%s".printf (new_id (), settings.preset.extension));
        }

        string mux_for (string container) {
            switch (container) {
                case "matroska": return "matroskamux";
                case "webm": return "webmmux";
                case "mov": return "qtmux";
                case "wav": return "wavenc";
                case "flac": return "";
                case "mp3": return "";
                case "ogg": return "oggmux";
                default: return "mp4mux";
            }
        }

        void export_gst (double gain) throws Error {
            var p = settings.preset;
            int w, h;
            output_size (out w, out h);
            bool video = !p.audio_only;
            bool audio = p.acodec != "none";
            int64 s = range_start (), e = range_end ();
            int kbps = p.vbitrate;
            if (p.max_size_mb > 0) {
                double seconds = (double) (e - s) / Tc.SECOND;
                kbps = (int) (p.max_size_mb * 8192.0 * 0.95 / double.max (1, seconds)) - (audio ? p.abitrate : 0);
                kbps = int.max (300, kbps);
            }
            var desc = new StringBuilder ();
            string mux = mux_for (p.container);
            string venc_name = "";
            if (video) {
                var name = Encoders.pick (p.vcodec, settings.hardware);
                if (name == null) throw new IOError.NOT_SUPPORTED (_("No encoder for %s is installed. Install the GStreamer plugin for it or choose a free format such as WebM.").printf (p.vcodec.up ()));
                venc_name = name;
                bool wide = p.depth > 8;
                string format = wide ? (p.vcodec.has_prefix ("h26") ? "I420_10LE" : "I420_10LE") : "I420";
                if (name.has_prefix ("x264") && p.vcodec == "h264-lossless") format = "Y444";
                if (name.has_prefix ("va") || name.has_prefix ("vulkan") || name.has_prefix ("nv") || name.has_prefix ("qsv")) format = wide ? "P010_10LE" : "NV12";
                string colorimetry = p.transfer == "pq" ? ",colorimetry=bt2100-pq" : (p.transfer == "hlg" ? ",colorimetry=bt2100-hlg" : ",colorimetry=bt709");
                desc.append ("appsrc name=vsrc format=time block=true max-bytes=%u ! videoconvert ! video/x-raw,format=%s%s ! %s name=venc ! "
                    .printf ((uint) (w * h * 16), format, colorimetry, name));
                string parser = Encoders.parser_for (p.vcodec);
                if (parser != "") desc.append (parser + " ! ");
                desc.append ("queue max-size-time=0 max-size-buffers=0 max-size-bytes=0 ! mux.video_%u ");
            }
            if (audio) {
                var aname = p.acodec == "pcm" ? null : Encoders.audio (p.acodec);
                if (p.acodec != "pcm" && aname == null) throw new IOError.NOT_SUPPORTED (_("No %s audio encoder is installed.").printf (p.acodec.up ()));
                desc.append ("appsrc name=asrc format=time block=true ! audioconvert ! audioresample ! ");
                if (p.acodec == "pcm") desc.append ("audio/x-raw,format=S24LE ! ");
                else desc.append ("%s name=aenc ! ".printf (aname));
                if (p.acodec == "mp3") desc.append ("mpegaudioparse ! ");
                if (p.acodec == "aac") desc.append ("aacparse ! ");
                if (p.acodec == "flac") desc.append ("flacparse ! ");
                desc.append (mux == "" ? "queue ! output. " : (mux == "wavenc" || mux == "oggmux" ? "queue ! mux. " : "queue max-size-time=0 max-size-buffers=0 max-size-bytes=0 ! mux.audio_%u "));
            }
            bool embed = settings.subtitles == "embed" && video && (mux == "matroskamux" || mux == "mp4mux" || mux == "qtmux");
            if (settings.subtitles == "embed" && !embed) settings.subtitles = "vtt";
            if (embed) desc.append ("appsrc name=tsrc format=time block=false caps=text/x-raw,format=utf8 ! queue ! mux.subtitle_%u ");
            if (mux != "") desc.append ("%s name=mux ! filesink name=output".printf (mux == "mp4mux" || mux == "qtmux" ? mux + " faststart=false" : mux));
            else desc.append ("filesink name=output");
            var pipeline = (Gst.Pipeline) Gst.parse_launch (desc.str);
            var tmp = staging ();
            pipeline.get_by_name ("output").set ("location", tmp.get_path ());
            encoder_used = venc_name != "" ? venc_name : (p.acodec);
            Gst.App.Src? vsrc = null, asrc = null, tsrc = null;
            int n_p = fps_n (), n_d = fps_d ();
            if (video) {
                vsrc = (Gst.App.Src) pipeline.get_by_name ("vsrc");
                vsrc.caps = Gst.Caps.from_string ("video/x-raw,format=%s,width=%d,height=%d,framerate=%d/%d,pixel-aspect-ratio=1/1%s"
                    .printf (p.depth > 8 ? "RGBA64_LE" : "RGBA", w, h, n_p, n_d,
                        p.transfer == "pq" ? ",colorimetry=bt2100-pq" : (p.transfer == "hlg" ? ",colorimetry=bt2100-hlg" : ",colorimetry=sRGB")));
                var venc = pipeline.get_by_name ("venc");
                Encoders.configure (venc, p.vcodec, p, kbps);
            }
            if (audio) {
                asrc = (Gst.App.Src) pipeline.get_by_name ("asrc");
                asrc.caps = Gst.Caps.from_string ("audio/x-raw,format=F32LE,layout=interleaved,rate=%d,channels=2,channel-mask=(bitmask)0x3".printf (seq.sample_rate));
                var aenc = pipeline.get_by_name ("aenc");
                if (aenc != null) {
                    var spec = aenc.get_class ().find_property ("bitrate");
                    if (spec != null && p.acodec != "flac") {
                        int bps = p.acodec == "mp3" ? p.abitrate : p.abitrate * 1000;
                        if (spec.value_type == typeof (int)) aenc.set ("bitrate", bps);
                        else if (spec.value_type == typeof (uint)) aenc.set ("bitrate", (uint) bps);
                    }
                }
            }
            if (embed) tsrc = (Gst.App.Src) pipeline.get_by_name ("tsrc");
            var mux_element = pipeline.get_by_name ("mux");
            if (settings.chapters && mux_element is Gst.TocSetter) {
                var marks = chapters ();
                if (marks.size > 0) {
                    var toc = new Gst.Toc (Gst.TocScope.GLOBAL);
                    var edition = new Gst.TocEntry (Gst.TocEntryType.EDITION, "edition");
                    for (int i = 0; i < marks.size; i++) {
                        var chapter = new Gst.TocEntry (Gst.TocEntryType.CHAPTER, "chapter%d".printf (i + 1));
                        int64 cend = i + 1 < marks.size ? marks[i + 1].time : e - s;
                        chapter.set_start_stop_times (marks[i].time, cend);
                        var tags = new Gst.TagList.empty ();
                        tags.add (Gst.TagMergeMode.APPEND, Gst.Tags.TITLE, marks[i].name != "" ? marks[i].name : _("Chapter %d").printf (i + 1));
                        chapter.set_tags ((owned) tags);
                        edition.append_sub_entry ((owned) chapter);
                    }
                    toc.append_entry ((owned) edition);
                    ((Gst.TocSetter) mux_element).set_toc (toc);
                }
            }
            if (mux_element is Gst.TagSetter) {
                var tags = new Gst.TagList.empty ();
                tags.add (Gst.TagMergeMode.REPLACE, Gst.Tags.TITLE, seq.name);
                tags.add (Gst.TagMergeMode.REPLACE, Gst.Tags.ENCODER, "Montage");
                ((Gst.TagSetter) mux_element).merge_tags (tags, Gst.TagMergeMode.REPLACE);
            }
            if (pipeline.set_state (Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE) {
                pipeline.set_state (Gst.State.NULL);
                throw new IOError.FAILED (_("The encoder pipeline could not start."));
            }
            var bus = pipeline.get_bus ();
            Renderer? r = video ? make_renderer (w, h) : null;
            var mixer = new AudioMixer (project, seq, seq.sample_rate);
            mixer.master_gain_db = gain;
            int64 frames = video ? Tc.to_frames (e - s + Tc.frame_duration (n_p, n_d) / 2, n_p, n_d) : 0;
            int64 sample = mixer.to_sample (s);
            int64 last_sample = mixer.to_sample (e);
            string? failure = null;
            bool cancelled_now = false;
            try {
                if (tsrc != null) {
                    foreach (var c in Subtitles.all (seq)) {
                        if (c.end <= s || c.start >= e) continue;
                        var buf = new Gst.Buffer.wrapped (c.text.data);
                        buf.pts = int64.max (0, c.start - s);
                        buf.duration = int64.min (e, c.end) - int64.max (s, c.start);
                        tsrc.push_buffer (buf);
                    }
                    tsrc.end_of_stream ();
                }
                int64 i = 0;
                while (!is_cancelled) {
                    var msg = bus.pop_filtered (Gst.MessageType.ERROR);
                    if (msg != null) {
                        Error err;
                        string debug;
                        msg.parse_error (out err, out debug);
                        failure = err.message;
                        break;
                    }
                    bool more_video = video && i < frames;
                    bool more_audio = audio && sample < last_sample;
                    if (!more_video && !more_audio) break;
                    int64 t = s + Tc.from_frames (i, n_p, n_d);
                    if (more_video) {
                        var img = frame (r, t, w, h);
                        Gst.Buffer buf;
                        if (p.depth > 8) {
                            var words = ColorPipeline.encode_rgba16 (img, p.transfer);
                            uint8[] bytes = new uint8[words.length * 2];
                            Memory.copy (bytes, words, bytes.length);
                            buf = new Gst.Buffer.wrapped ((owned) bytes);
                        } else {
                            buf = new Gst.Buffer.wrapped (ColorPipeline.encode_rgba8 (img, true));
                        }
                        buf.pts = t - s;
                        buf.duration = Tc.from_frames (i + 1, n_p, n_d) - Tc.from_frames (i, n_p, n_d);
                        if (vsrc.push_buffer (buf) != Gst.FlowReturn.OK) break;
                    }
                    if (more_audio) {
                        int64 next = video ? mixer.to_sample (s + Tc.from_frames (i + 1, n_p, n_d)) : sample + 4096;
                        next = int64.min (next, last_sample);
                        int count = (int) (next - sample);
                        if (count > 0) {
                            var data = new float[count * 2];
                            mixer.render (sample, count, data);
                            uint8[] bytes = new uint8[count * 8];
                            Memory.copy (bytes, data, bytes.length);
                            var buf = new Gst.Buffer.wrapped ((owned) bytes);
                            buf.pts = mixer.to_time (sample) - s;
                            buf.duration = mixer.to_time (next) - mixer.to_time (sample);
                            if (asrc.push_buffer (buf) != Gst.FlowReturn.OK) break;
                        }
                        sample = next;
                    }
                    i++;
                    double done = video ? (double) i / frames : (double) (sample - mixer.to_sample (s)) / double.max (1, last_sample - mixer.to_sample (s));
                    report (0.15 + 0.85 * done.clamp (0, 1));
                }
                cancelled_now = is_cancelled;
                if (failure == null && !cancelled_now) {
                    if (vsrc != null) vsrc.end_of_stream ();
                    if (asrc != null) asrc.end_of_stream ();
                    var msg = bus.timed_pop_filtered (300 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR);
                    if (msg == null) failure = _("The encoder did not finish in time.");
                    else if (msg.type == Gst.MessageType.ERROR) {
                        Error err;
                        string debug;
                        msg.parse_error (out err, out debug);
                        failure = err.message;
                    }
                }
            } finally {
                pipeline.set_state (Gst.State.NULL);
                if (r != null) r.close ();
                mixer.close ();
            }
            if (failure != null || cancelled_now) {
                try { tmp.delete (); } catch (Error err) { }
                if (cancelled_now) throw new IOError.CANCELLED (_("Export cancelled."));
                throw new IOError.FAILED (failure);
            }
            tmp.move (settings.output, FileCopyFlags.OVERWRITE);
        }
    }

    public class ExportQueue : Object {
        public Gee.ArrayList<ExportJob> jobs = new Gee.ArrayList<ExportJob> ();
        public ExportJob? current { get; private set; }
        public bool paused;
        public signal void changed ();
        public signal void job_finished (ExportJob job, bool ok, string? error);

        public void add (ExportJob job) {
            jobs.add (job);
            changed ();
            next ();
        }

        public void remove (ExportJob job) {
            if (job == current) {
                job.cancel ();
                return;
            }
            jobs.remove (job);
            changed ();
        }

        public void clear_finished () {
            var keep = new Gee.ArrayList<ExportJob> ();
            foreach (var j in jobs) if (j.state == "queued" || j.state == "running") keep.add (j);
            jobs = keep;
            changed ();
        }

        public void set_paused (bool value) {
            paused = value;
            changed ();
            if (!value) next ();
        }

        public int pending {
            get {
                int n = 0;
                foreach (var j in jobs) if (j.state == "queued" || j.state == "running") n++;
                return n;
            }
        }

        void next () {
            if (current != null || paused) return;
            foreach (var j in jobs) {
                if (j.state != "queued") continue;
                current = j;
                j.progress.connect (() => changed ());
                j.finished.connect ((ok, err) => {
                    current = null;
                    job_finished (j, ok, err);
                    changed ();
                    next ();
                });
                j.run.begin ();
                changed ();
                return;
            }
        }

        public void cancel_all () {
            foreach (var j in jobs) if (j.state == "queued") j.state = "cancelled";
            if (current != null) current.cancel ();
            changed ();
        }
    }
}
