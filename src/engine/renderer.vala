using Singularity.Imaging;

namespace Singularity.Apps.Montage {
    public class Renderer : Object {
        public Project project;
        public Sequence seq;
        public double scale;
        public int width;
        public int height;
        public bool proxies;
        public bool burn_subtitles = true;
        public bool show_disabled_overlay;
        public string working;
        public FxState fx = new FxState ();
        public FrameCache? cache;
        Gee.HashMap<string, VideoReader> readers = new Gee.HashMap<string, VideoReader> ();
        Gee.HashMap<string, int64?> reader_used = new Gee.HashMap<string, int64?> ();
        Gee.HashMap<string, Renderer> nested = new Gee.HashMap<string, Renderer> ();
        Gee.HashMap<string, Composition> compositions = new Gee.HashMap<string, Composition> ();
        Gee.HashMap<string, string> composition_stamps = new Gee.HashMap<string, string> ();
        Gee.HashMap<string, FloatImage> stills = new Gee.HashMap<string, FloatImage> ();
        int64 counter;
        public int max_readers = 10;
        public Gee.ArrayList<string> errors = new Gee.ArrayList<string> ();

        public Renderer (Project project, Sequence seq, double scale, bool proxies = false) {
            this.project = project;
            this.seq = seq;
            this.scale = scale;
            this.proxies = proxies;
            width = int.max (2, ((int) Math.round (seq.width * scale)) & ~1);
            height = int.max (2, ((int) Math.round (seq.height * scale)) & ~1);
            working = ColorPipeline.working_of (seq.color_space);
        }

        public void close () {
            foreach (var r in readers.values) r.close ();
            readers.clear ();
            foreach (var n in nested.values) n.close ();
            nested.clear ();
        }

        public string signature (int64 t) {
            var b = new Json.Builder ();
            b.begin_array ();
            b.add_int_value (t);
            b.add_double_value (scale);
            b.add_string_value (seq.color_space);
            b.add_boolean_value (proxies);
            b.add_boolean_value (burn_subtitles);
            foreach (var track in seq.tracks) {
                if (track.kind == TrackKind.AUDIO) continue;
                if (!track.visible) continue;
                foreach (var c in seq.clips) {
                    if (c.track != track.id) continue;
                    bool active = t >= c.position && t < c.end;
                    foreach (var tr in seq.transitions) {
                        if (tr.from_clip != c.id && tr.to_clip != c.id) continue;
                        int64 start, end;
                        if (transition_span (tr, out start, out end) && t >= start && t < end) {
                            active = true;
                            tr.write (b);
                        }
                    }
                    if (!active) continue;
                    c.write (b);
                    if (c.kind == ClipKind.MEDIA || c.kind == ClipKind.MULTICAM) {
                        var m = project.find_media (c.media);
                        if (m != null) {
                            m.write (b);
                            if (m.uri.has_suffix (".keyframe")) b.add_string_value (stamp (m.uri));
                        }
                    }
                    if (c.kind == ClipKind.SEQUENCE) {
                        var n = project.find_sequence (c.sequence);
                        if (n != null) b.add_string_value (nested_renderer (n).signature (c.source_time (t)));
                    }
                    if (c.kind == ClipKind.COMPOSITION) b.add_string_value (stamp (c.composition));
                }
            }
            b.end_array ();
            return Checksum.compute_for_string (ChecksumType.SHA1, Js.write (b.get_root ()));
        }

        string stamp (string uri) {
            try {
                var info = File.new_for_uri (uri).query_info ("time::modified,time::modified-usec,standard::size", FileQueryInfoFlags.NONE);
                return "%lld.%u.%lld".printf (info.get_attribute_uint64 ("time::modified"), info.get_attribute_uint32 ("time::modified-usec"), info.get_size ());
            } catch (Error e) {
                return "missing";
            }
        }

        public bool transition_span (Transition tr, out int64 start, out int64 end) {
            start = end = 0;
            var a = tr.from_clip != "" ? seq.clip (tr.from_clip) : null;
            var b = tr.to_clip != "" ? seq.clip (tr.to_clip) : null;
            if (a == null && b == null) return false;
            int64 cut = a != null ? a.end : b.position;
            if (a != null && b != null && a.end != b.position) return false;
            start = tr.start_at (cut);
            end = start + tr.duration;
            if (a == null) start = int64.max (start, cut);
            if (b == null) end = int64.min (end, cut);
            return end > start;
        }

        public FloatImage render (int64 t) {
            if (cache != null) {
                string key = signature (t);
                var hit = cache.lookup (key, width, height);
                if (hit != null) return hit;
                var img = render_uncached (t);
                cache.store (key, img);
                return img;
            }
            return render_uncached (t);
        }

        public FloatImage render_uncached (int64 t) {
            counter++;
            var canvas = new FloatImage (width, height);
            foreach (var track in seq.tracks) {
                if (track.kind != TrackKind.VIDEO || !track.visible) continue;
                render_track (canvas, track, t);
            }
            if (burn_subtitles) {
                foreach (var track in seq.tracks) {
                    if (track.kind != TrackKind.SUBTITLE || !track.visible) continue;
                    var c = seq.clip_at (track.id, t);
                    if (c != null && c.enabled) {
                        var layer = Subtitles.render (c, width, height, scale);
                        Compose.over (canvas, layer, 1);
                    }
                }
            }
            prune_readers ();
            return canvas;
        }

        void render_track (FloatImage canvas, Track track, int64 t) {
            foreach (var tr in seq.transitions) {
                if (tr.track != track.id) continue;
                int64 start, end;
                if (!transition_span (tr, out start, out end) || t < start || t >= end) continue;
                var a = tr.from_clip != "" ? seq.clip (tr.from_clip) : null;
                var b = tr.to_clip != "" ? seq.clip (tr.to_clip) : null;
                float progress = (float) ((double) (t - start) / (end - start));
                if ((a != null && a.kind == ClipKind.ADJUSTMENT) || (b != null && b.kind == ClipKind.ADJUSTMENT)) break;
                var la = a != null && a.enabled ? placed_layer (a, t) : null;
                var lb = b != null && b.enabled ? placed_layer (b, t) : null;
                if (la == null && lb == null) return;
                var mixed = Compose.transition (la, lb, tr, progress);
                Compose.over (canvas, mixed, 1);
                return;
            }
            var c = seq.clip_at (track.id, t);
            if (c == null || !c.enabled) return;
            if (c.kind == ClipKind.ADJUSTMENT) {
                apply_adjustment (canvas, c, t);
                return;
            }
            var layer = clip_layer (c, t);
            if (layer == null) return;
            var p = Compose.placement (c, c.key_time (t), scale);
            Compose.place (canvas, layer, p, BlendMode.from_key (c.blend));
        }

        FloatImage? placed_layer (Clip c, int64 t) {
            var layer = clip_layer (c, t);
            if (layer == null) return null;
            var full = new FloatImage (width, height);
            var p = Compose.placement (c, c.key_time (t), scale);
            Compose.place (full, layer, p, BlendMode.NORMAL);
            return full;
        }

        void apply_adjustment (FloatImage canvas, Clip c, int64 t) {
            var copy = canvas.copy ();
            var ctx = context (c, t);
            foreach (var e in c.effects) VideoFx.apply (e, copy, ctx);
            float opacity = (float) (c.params.get_value ("opacity", c.key_time (t), 100) / 100);
            int n = (int) canvas.pixel_count ();
            Parallel.range (n, (a, b) => {
                for (int p = a; p < b; p++) {
                    size_t i = (size_t) p * 4;
                    float alpha = canvas.data[i + 3];
                    for (int k = 0; k < 3; k++) canvas.data[i + k] += (copy.data[i + k] - canvas.data[i + k]) * opacity;
                    canvas.data[i + 3] = alpha;
                }
            }, 4096);
        }

        FxContext context (Clip c, int64 t) {
            var ctx = new FxContext (fx);
            ctx.key_time = c.key_time (t);
            ctx.source_time = source_time (c, t);
            ctx.scale = scale;
            return ctx;
        }

        public int64 source_time (Clip c, int64 t) {
            if (t >= c.position && t < c.end) return c.source_time (t);
            double speed = c.params.get_value ("speed", c.in_point, 100) / 100;
            if (c.reverse) speed = -speed;
            int64 base_time = t < c.position ? c.source_time (c.position) : c.source_time (c.end - 1);
            int64 off = t < c.position ? t - c.position : t - (c.end - 1);
            int64 src = base_time + (int64) (off * speed);
            int64 len = project.media_length (c);
            return src.clamp (0, int64.max (0, len - 1));
        }

        public void fit_size (int mw, int mh, out int w, out int h) {
            double s = double.min ((double) width / int.max (1, mw), (double) height / int.max (1, mh));
            w = int.max (2, ((int) Math.round (mw * s)) & ~1);
            h = int.max (2, ((int) Math.round (mh * s)) & ~1);
        }

        void layer_size (Clip c, int mw, int mh, out int w, out int h) {
            string fit = c.params.text ("fit", "fit");
            if (fit == "none") {
                w = int.max (2, ((int) Math.round (mw * scale)) & ~1);
                h = int.max (2, ((int) Math.round (mh * scale)) & ~1);
            } else if (fit == "fill") {
                double s = double.max ((double) width / int.max (1, mw), (double) height / int.max (1, mh));
                w = int.max (2, ((int) Math.round (mw * s)) & ~1);
                h = int.max (2, ((int) Math.round (mh * s)) & ~1);
            } else {
                fit_size (mw, mh, out w, out h);
            }
        }

        public FloatImage? clip_layer (Clip c, int64 t) {
            FloatImage? img = null;
            int64 src = source_time (c, t);
            int64 local = t - c.position;
            switch (c.kind) {
                case ClipKind.MEDIA: {
                    var m = project.find_media (c.media);
                    if (m == null || !m.has_video) return null;
                    img = media_frame (c, m, src, "");
                    break;
                }
                case ClipKind.MULTICAM: {
                    var m = project.find_media (c.media);
                    if (m == null || m.angles.size == 0) return null;
                    int angle = c.angle_at (t - c.position).clamp (0, m.angles.size - 1);
                    var a = m.angles[angle];
                    var am = project.find_media (a.media_id);
                    if (am == null || !am.has_video) return null;
                    int64 asrc = src - a.offset;
                    if (asrc < 0 || (!am.still && asrc >= am.duration)) return null;
                    img = media_frame (c, am, asrc, "angle%d".printf (angle));
                    break;
                }
                case ClipKind.TITLE:
                    if (c.title == null) return null;
                    img = Titles.render (c.title, width, height, scale, local, c.duration);
                    break;
                case ClipKind.COLOR: {
                    float r, g, b, a;
                    VideoFx.parse_color (c.color, out r, out g, out b, out a);
                    img = new FloatImage.filled (width, height, Tone.decode (r), Tone.decode (g), Tone.decode (b), a);
                    break;
                }
                case ClipKind.SEQUENCE: {
                    var n = project.find_sequence (c.sequence);
                    if (n == null || n == seq) return null;
                    var r = nested_renderer (n);
                    var inner = r.render (src);
                    int w, h;
                    layer_size (c, n.width, n.height, out w, out h);
                    img = w == inner.width && h == inner.height ? inner.copy () : inner.resized (w, h);
                    break;
                }
                case ClipKind.COMPOSITION: {
                    var comp = composition (c.composition);
                    if (comp == null) return null;
                    int w, h;
                    layer_size (c, comp.width, comp.height, out w, out h);
                    img = comp.render (src, w, h);
                    break;
                }
                default:
                    return null;
            }
            if (img == null) return null;
            var ctx = context (c, t);
            foreach (var e in c.effects) VideoFx.apply (e, img, ctx);
            return img;
        }

        Renderer nested_renderer (Sequence n) {
            var r = nested[n.id];
            if (r == null) {
                r = new Renderer (project, n, scale, proxies);
                r.burn_subtitles = burn_subtitles;
                r.fx = fx;
                nested[n.id] = r;
            }
            return r;
        }

        Composition? composition (string uri) {
            string s = stamp (uri);
            if (composition_stamps[uri] == s && compositions.has_key (uri)) return compositions[uri];
            try {
                var c = Composition.load (File.new_for_uri (uri));
                compositions[uri] = c;
                composition_stamps[uri] = s;
                return c;
            } catch (Error e) {
                note_error (e.message);
                return null;
            }
        }

        void note_error (string message) {
            if (!errors.contains (message)) errors.add (message);
        }

        FloatImage? media_frame (Clip c, MediaItem m, int64 src, string variant) {
            int w, h;
            layer_size (c, m.width, m.height, out w, out h);
            string primaries = ColorPipeline.primaries_of (m.colorimetry, m.transfer);
            string transfer = c.color_space == "auto" ? m.transfer : (c.color_space.contains ("pq") ? "pq" : (c.color_space.contains ("hlg") ? "hlg" : "sdr"));
            if (c.color_space != "auto") primaries = c.color_space.has_prefix ("rec2020") ? "rec2020" : "rec709";
            if (m.still) return still (m, w, h, primaries);
            string uri = m.playback_uri (proxies);
            bool wide = transfer != "sdr" || m.depth > 8;
            if (uri != m.uri) wide = false;
            string overrides = c.params.text ("keyframe-overrides");
            string key = "%s|%s|%s|%dx%d|%s".printf (c.id, variant, uri, w, h, overrides);
            var reader = readers[key];
            if (reader == null) {
                reader = new VideoReader (uri, w, h, wide);
                if (overrides != "") reader.overrides = overrides;
                readers[key] = reader;
            }
            reader_used[key] = counter;
            try {
                var frame = reader.frame_at (src);
                if (frame == null) return null;
                var img = ColorPipeline.to_working (frame, transfer, primaries, working);
                if (c.frame_blend && c.speed_changed && !c.reverse && frame.duration > 0) {
                    double weight = (double) (src - frame.pts) / frame.duration;
                    if (weight > 0.05 && weight < 0.95) {
                        var next = reader.next_after (frame);
                        if (next != null) {
                            var other = ColorPipeline.to_working (next, transfer, primaries, working);
                            Compose.mix_with (img, other, (float) weight);
                        }
                    }
                }
                if (working == "rec709" && transfer != "sdr") ColorPipeline.tone_map_sdr (img);
                return img;
            } catch (Error e) {
                note_error ("%s: %s".printf (m.name, e.message));
                return null;
            }
        }

        FloatImage? still (MediaItem m, int w, int h, string primaries) {
            string key = "%s|%dx%d".printf (m.uri, w, h);
            if (stills.has_key (key)) return stills[key].copy ();
            try {
                var file = File.new_for_uri (m.uri);
                var pixbuf = new Gdk.Pixbuf.from_file_at_scale (file.get_path (), w, h, false);
                if (!pixbuf.has_alpha) pixbuf = pixbuf.add_alpha (false, 0, 0, 0);
                var f = new Frame ();
                f.width = pixbuf.width;
                f.height = pixbuf.height;
                f.bytes = new uint8[f.width * f.height * 4];
                unowned uint8[] px = pixbuf.get_pixels_with_length ();
                for (int y = 0; y < f.height; y++) Memory.copy ((uint8*) f.bytes + y * f.width * 4, (uint8*) px + y * pixbuf.rowstride, f.width * 4);
                var img = ColorPipeline.to_working (f, "sdr", primaries, working);
                stills[key] = img;
                return img.copy ();
            } catch (Error e) {
                note_error ("%s: %s".printf (m.name, e.message));
                return null;
            }
        }

        void prune_readers () {
            if (readers.size <= max_readers) return;
            var keys = new Gee.ArrayList<string> ();
            keys.add_all (readers.keys);
            keys.sort ((a, b) => {
                int64 ua = reader_used[a] ?? 0, ub = reader_used[b] ?? 0;
                return ua < ub ? -1 : (ua > ub ? 1 : 0);
            });
            for (int i = 0; i < keys.size - max_readers; i++) {
                if ((reader_used[keys[i]] ?? 0) >= counter) continue;
                readers[keys[i]].close ();
                readers.unset (keys[i]);
                reader_used.unset (keys[i]);
            }
        }

        public uint8[] render_rgba8 (int64 t) {
            var img = render (t);
            return ColorPipeline.encode_rgba8 (img, true);
        }
    }
}
