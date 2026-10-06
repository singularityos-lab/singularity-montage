namespace Singularity.Apps.Montage {
    namespace Probe {
        public const string[] MEDIA_EXTENSIONS = {
            "mp4", "m4v", "mov", "mkv", "webm", "avi", "mts", "m2ts", "mxf", "mpg", "mpeg", "ts", "ogv", "3gp", "dv", "y4m",
            "wav", "bwf", "flac", "mp3", "m4a", "aac", "ogg", "oga", "opus", "aif", "aiff",
            "keyframe", "png", "jpg", "jpeg", "tif", "tiff", "webp", "bmp", "gif", "exr", "dpx", "svg"
        };

        public bool is_media_name (string name) {
            string lower = name.down ();
            int dot = lower.last_index_of (".");
            if (dot < 0 || name.has_prefix (".")) return false;
            string ext = lower.substring (dot + 1);
            foreach (var e in MEDIA_EXTENSIONS) if (e == ext) return true;
            return false;
        }

        void ensure_gst () {
            if (!Gst.is_initialized ()) {
                unowned string[]? args = null;
                Gst.init (ref args);
            }
        }

        public MediaItem probe (string uri) throws Error {
            ensure_gst ();
            var file = File.new_for_uri (uri);
            if (!file.query_exists ()) throw new IOError.NOT_FOUND (_("The file %s does not exist.").printf (file.get_basename () ?? uri));
            var discoverer = new Gst.PbUtils.Discoverer (20 * Gst.SECOND);
            var info = discoverer.discover_uri (uri);
            var result = info.get_result ();
            if (result != Gst.PbUtils.DiscovererResult.OK) {
                string reason = result == Gst.PbUtils.DiscovererResult.MISSING_PLUGINS
                    ? _("A decoder for this format is not installed.")
                    : _("The file could not be read as audio or video.");
                throw new IOError.INVALID_DATA ("%s: %s".printf (file.get_basename () ?? uri, reason));
            }
            var m = new MediaItem ();
            m.uri = uri;
            m.name = file.get_basename () ?? uri;
            m.imported = new DateTime.now_utc ().to_unix ();
            m.duration = (int64) info.get_duration ();
            var videos = info.get_video_streams ();
            if (videos != null && videos.length () > 0) {
                var v = (Gst.PbUtils.DiscovererVideoInfo) videos.nth_data (0);
                m.has_video = true;
                m.width = (int) v.get_width ();
                m.height = (int) v.get_height ();
                int par_n = (int) v.get_par_num (), par_d = (int) v.get_par_denom ();
                if (par_n > 0 && par_d > 0 && par_n != par_d) m.width = (int) Math.round ((double) m.width * par_n / par_d);
                m.fps_n = (int) v.get_framerate_num ();
                m.fps_d = (int) v.get_framerate_denom ();
                m.still = v.is_image ();
                m.depth = 8;
                if (m.fps_n <= 0 || m.fps_d <= 0) {
                    m.variable_rate = !m.still;
                    m.fps_n = 30;
                    m.fps_d = 1;
                }
                var caps = v.get_caps ();
                if (caps != null && caps.get_size () > 0) {
                    unowned Gst.Structure st = caps.get_structure (0);
                    string? colorimetry = st.get_string ("colorimetry");
                    if (colorimetry != null) m.colorimetry = colorimetry;
                    string? format = st.get_string ("format");
                    if (format != null && (format.contains ("10") || format.contains ("12") || format.contains ("16"))) m.depth = 10;
                    int bit_depth;
                    if (st.get_int ("bit-depth-luma", out bit_depth) && bit_depth > 8) m.depth = bit_depth;
                }
                m.transfer = transfer_of (m.colorimetry);
            }
            var audios = info.get_audio_streams ();
            if (audios != null && audios.length () > 0) {
                var a = (Gst.PbUtils.DiscovererAudioInfo) audios.nth_data (0);
                m.has_audio = true;
                m.channels = (int) a.get_channels ();
                m.sample_rate = (int) a.get_sample_rate ();
            }
            if (!m.has_video && !m.has_audio) throw new IOError.INVALID_DATA (_("%s has no audio or video.").printf (m.name));
            if (m.still) m.duration = 0;
            else if (m.duration <= 0) throw new IOError.INVALID_DATA (_("%s has no readable duration.").printf (m.name));
            var tags = info.get_tags ();
            if (tags != null) read_tags (m, tags);
            try {
                var finfo = file.query_info ("standard::size,time::modified", FileQueryInfoFlags.NONE);
                m.metadata["size"] = format_size (finfo.get_size ());
                var mod = finfo.get_modification_date_time ();
                if (mod != null) m.metadata["modified"] = mod.to_local ().format ("%Y-%m-%d %H:%M");
            } catch (Error e) {
            }
            if (m.has_video && !m.still) m.metadata["format"] = "%dx%d %.3g fps".printf (m.width, m.height, (double) m.fps_n / m.fps_d);
            return m;
        }

        public string transfer_of (string colorimetry) {
            if (colorimetry.contains ("smpte2084")) return "pq";
            if (colorimetry.contains ("arib-std-b67")) return "hlg";
            if (colorimetry.has_prefix ("bt2100-pq")) return "pq";
            if (colorimetry.has_prefix ("bt2100-hlg")) return "hlg";
            return "sdr";
        }

        void read_tags (MediaItem m, Gst.TagList tags) {
            string? s;
            if (tags.get_string (Gst.Tags.TITLE, out s) && s != null) m.metadata["title"] = s;
            if (tags.get_string (Gst.Tags.ARTIST, out s) && s != null) m.metadata["artist"] = s;
            if (tags.get_string (Gst.Tags.COMMENT, out s) && s != null) m.metadata["comment"] = s;
            if (tags.get_string (Gst.Tags.DEVICE_MODEL, out s) && s != null) m.metadata["camera"] = s;
            if (tags.get_string (Gst.Tags.DEVICE_MANUFACTURER, out s) && s != null) m.metadata["maker"] = s;
            if (tags.get_string (Gst.Tags.VIDEO_CODEC, out s) && s != null) m.metadata["video codec"] = s;
            if (tags.get_string (Gst.Tags.AUDIO_CODEC, out s) && s != null) m.metadata["audio codec"] = s;
            if (tags.get_string (Gst.Tags.CONTAINER_FORMAT, out s) && s != null) m.metadata["container"] = s;
            Gst.DateTime? dt;
            if (tags.get_date_time (Gst.Tags.DATE_TIME, out dt) && dt != null) m.metadata["recorded"] = dt.to_iso8601_string ();
        }

        public Gee.ArrayList<File> scan_folder (File folder, int depth = 6) {
            var result = new Gee.ArrayList<File> ();
            scan_into (folder, depth, result);
            result.sort ((a, b) => strcmp (a.get_path () ?? a.get_uri (), b.get_path () ?? b.get_uri ()));
            return result;
        }

        void scan_into (File folder, int depth, Gee.ArrayList<File> result) {
            if (depth < 0) return;
            try {
                var e = folder.enumerate_children ("standard::name,standard::type,standard::is-hidden", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                FileInfo? info;
                while ((info = e.next_file ()) != null) {
                    if (info.get_is_hidden ()) continue;
                    var child = folder.get_child (info.get_name ());
                    if (info.get_file_type () == FileType.DIRECTORY) scan_into (child, depth - 1, result);
                    else if (info.get_file_type () == FileType.REGULAR && is_media_name (info.get_name ())) result.add (child);
                }
            } catch (Error e) {
                debug ("scan %s: %s", folder.get_uri (), e.message);
            }
        }

        public Gee.ArrayList<File> camera_folders () {
            var result = new Gee.ArrayList<File> ();
            var monitor = VolumeMonitor.get ();
            foreach (var mount in monitor.get_mounts ()) {
                var root = mount.get_root ();
                foreach (var name in new string[] { "DCIM", "PRIVATE/AVCHD", "PRIVATE/M4ROOT", "AVCHD", "MP_ROOT", "CLIP", "XDROOT", "CONTENTS" }) {
                    var dir = root.resolve_relative_path (name);
                    if (dir.query_exists ()) {
                        result.add (dir);
                        break;
                    }
                }
            }
            return result;
        }
    }
}
