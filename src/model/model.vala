using Singularity.Keyframes;

namespace Singularity.Apps.Montage {
    public enum TrackKind {
        VIDEO,
        AUDIO,
        SUBTITLE;

        public string key () {
            switch (this) {
                case AUDIO: return "audio";
                case SUBTITLE: return "subtitle";
                default: return "video";
            }
        }

        public static TrackKind from_key (string key) {
            switch (key) {
                case "audio": return AUDIO;
                case "subtitle": return SUBTITLE;
                default: return VIDEO;
            }
        }
    }

    public enum ClipKind {
        MEDIA,
        TITLE,
        COLOR,
        ADJUSTMENT,
        SEQUENCE,
        MULTICAM,
        COMPOSITION,
        SUBTITLE;

        public string key () {
            switch (this) {
                case TITLE: return "title";
                case COLOR: return "color";
                case ADJUSTMENT: return "adjustment";
                case SEQUENCE: return "sequence";
                case MULTICAM: return "multicam";
                case COMPOSITION: return "composition";
                case SUBTITLE: return "subtitle";
                default: return "media";
            }
        }

        public static ClipKind from_key (string key) {
            switch (key) {
                case "title": return TITLE;
                case "color": return COLOR;
                case "adjustment": return ADJUSTMENT;
                case "sequence": return SEQUENCE;
                case "multicam": return MULTICAM;
                case "composition": return COMPOSITION;
                case "subtitle": return SUBTITLE;
                default: return MEDIA;
            }
        }

        public bool generated () {
            return this != MEDIA && this != MULTICAM && this != SEQUENCE;
        }
    }

    public string new_id () {
        return Uuid.string_random ().substring (0, 13).replace ("-", "");
    }

    public class ParamSet : Object {
        public Gee.TreeMap<string, AnimatedValue> values = new Gee.TreeMap<string, AnimatedValue> ();
        public Gee.TreeMap<string, string> texts = new Gee.TreeMap<string, string> ();

        public double get_value (string name, int64 t, double fallback) {
            var v = values[name];
            return v != null ? v.at (t) : fallback;
        }

        public AnimatedValue ensure (string name, double fallback) {
            var v = values[name];
            if (v == null) {
                v = new AnimatedValue (fallback);
                values[name] = v;
            }
            return v;
        }

        public string text (string name, string fallback = "") {
            return texts.has_key (name) ? texts[name] : fallback;
        }

        public bool animated () {
            foreach (var v in values.values) if (v.animated) return true;
            return false;
        }

        public ParamSet copy () {
            var p = new ParamSet ();
            foreach (var e in values.entries) p.values[e.key] = e.value.copy ();
            foreach (var e in texts.entries) p.texts[e.key] = e.value;
            return p;
        }

        public void write (Json.Builder b) {
            b.set_member_name ("values");
            b.begin_object ();
            foreach (var e in values.entries) {
                b.set_member_name (e.key);
                b.add_value (e.value.to_json ());
            }
            b.end_object ();
            b.set_member_name ("texts");
            b.begin_object ();
            foreach (var e in texts.entries) Js.s (b, e.key, e.value);
            b.end_object ();
        }

        public void read (Json.Object o) {
            var v = Js.obj (o, "values");
            if (v != null) foreach (var name in v.get_members ()) values[name] = AnimatedValue.from_json (v.get_member (name));
            var t = Js.obj (o, "texts");
            if (t != null) foreach (var name in t.get_members ()) texts[name] = Js.str (t, name);
        }

        public void shift (int64 delta) {
            foreach (var v in values.values) v.shift (delta);
        }
    }

    public class Effect : Object {
        public string id = new_id ();
        public string type;
        public bool enabled = true;
        public ParamSet params = new ParamSet ();

        public Effect (string type) {
            this.type = type;
        }

        public Effect copy () {
            var e = new Effect (type);
            e.id = id;
            e.enabled = enabled;
            e.params = params.copy ();
            return e;
        }

        public void write (Json.Builder b) {
            b.begin_object ();
            Js.s (b, "id", id);
            Js.s (b, "type", type);
            Js.f (b, "enabled", enabled);
            params.write (b);
            b.end_object ();
        }

        public static Effect read (Json.Object o) {
            var e = new Effect (Js.str (o, "type", "unknown"));
            e.id = Js.str (o, "id", new_id ());
            e.enabled = Js.flag (o, "enabled", true);
            e.params.read (o);
            return e;
        }
    }

    public class Bin : Object {
        public string id = new_id ();
        public string name;
        public string parent = "";
        public int label;

        public Bin (string name) {
            this.name = name;
        }
    }

    public class MulticamAngle : Object {
        public string media_id;
        public string name;
        public int64 offset;

        public MulticamAngle (string media_id, string name, int64 offset) {
            this.media_id = media_id;
            this.name = name;
            this.offset = offset;
        }
    }

    public class MediaItem : Object {
        public string id = new_id ();
        public string kind = "file";
        public string uri = "";
        public string name = "";
        public string bin = "";
        public int label;
        public int rating;
        public string notes = "";
        public Gee.ArrayList<string> tags = new Gee.ArrayList<string> ();
        public Gee.TreeMap<string, string> metadata = new Gee.TreeMap<string, string> ();
        public int64 duration;
        public int width;
        public int height;
        public int fps_n = 30;
        public int fps_d = 1;
        public bool has_video;
        public bool has_audio;
        public bool still;
        public int channels = 2;
        public int sample_rate = 48000;
        public string colorimetry = "";
        public string transfer = "sdr";
        public int depth = 8;
        public bool variable_rate;
        public string proxy_uri = "";
        public string proxy_state = "none";
        public int64 imported;
        public Gee.ArrayList<MulticamAngle> angles = new Gee.ArrayList<MulticamAngle> ();
        public int audio_angle;
        public int64 mark_in = -1;
        public int64 mark_out = -1;
        public string transcript = "";

        public bool offline {
            get {
                if (kind != "file") return false;
                return !File.new_for_uri (uri).query_exists ();
            }
        }

        public string playback_uri (bool use_proxy) {
            if (use_proxy && proxy_state == "ready" && proxy_uri != "" && File.new_for_uri (proxy_uri).query_exists ()) return proxy_uri;
            return uri;
        }

        public bool matches (string query) {
            string q = query.casefold ();
            if (q == "") return true;
            if (name.casefold ().contains (q) || notes.casefold ().contains (q)) return true;
            foreach (var t in tags) if (t.casefold ().contains (q)) return true;
            foreach (var e in metadata.entries) if (e.value.casefold ().contains (q) || e.key.casefold ().contains (q)) return true;
            return false;
        }

        public void write (Json.Builder b) {
            b.begin_object ();
            Js.s (b, "id", id);
            Js.s (b, "kind", kind);
            Js.s (b, "uri", uri);
            Js.s (b, "name", name);
            Js.s (b, "bin", bin);
            Js.i (b, "label", label);
            Js.i (b, "rating", rating);
            Js.s (b, "notes", notes);
            b.set_member_name ("tags");
            b.begin_array ();
            foreach (var t in tags) b.add_string_value (t);
            b.end_array ();
            b.set_member_name ("metadata");
            b.begin_object ();
            foreach (var e in metadata.entries) Js.s (b, e.key, e.value);
            b.end_object ();
            Js.i (b, "duration", duration);
            Js.i (b, "width", width);
            Js.i (b, "height", height);
            Js.i (b, "fps-n", fps_n);
            Js.i (b, "fps-d", fps_d);
            Js.f (b, "video", has_video);
            Js.f (b, "audio", has_audio);
            Js.f (b, "still", still);
            Js.i (b, "channels", channels);
            Js.i (b, "rate", sample_rate);
            Js.s (b, "colorimetry", colorimetry);
            Js.s (b, "transfer", transfer);
            Js.i (b, "depth", depth);
            Js.f (b, "variable-rate", variable_rate);
            Js.s (b, "proxy", proxy_uri);
            Js.s (b, "proxy-state", proxy_state);
            Js.i (b, "imported", imported);
            Js.i (b, "mark-in", mark_in);
            Js.i (b, "mark-out", mark_out);
            if (transcript != "") Js.s (b, "transcript", transcript);
            if (angles.size > 0) {
                b.set_member_name ("angles");
                b.begin_array ();
                foreach (var a in angles) {
                    b.begin_object ();
                    Js.s (b, "media", a.media_id);
                    Js.s (b, "name", a.name);
                    Js.i (b, "offset", a.offset);
                    b.end_object ();
                }
                b.end_array ();
                Js.i (b, "audio-angle", audio_angle);
            }
            b.end_object ();
        }

        public static MediaItem read (Json.Object o) {
            var m = new MediaItem ();
            m.id = Js.str (o, "id", new_id ());
            m.kind = Js.str (o, "kind", "file");
            m.uri = Js.str (o, "uri");
            m.name = Js.str (o, "name");
            m.bin = Js.str (o, "bin");
            m.label = (int) Js.integer (o, "label");
            m.rating = (int) Js.integer (o, "rating");
            m.notes = Js.str (o, "notes");
            var tags = Js.arr (o, "tags");
            if (tags != null) foreach (var n in tags.get_elements ()) if (n.get_value_type () == typeof (string)) m.tags.add (n.get_string ());
            var meta = Js.obj (o, "metadata");
            if (meta != null) foreach (var k in meta.get_members ()) m.metadata[k] = Js.str (meta, k);
            m.duration = Js.integer (o, "duration");
            m.width = (int) Js.integer (o, "width");
            m.height = (int) Js.integer (o, "height");
            m.fps_n = (int) Js.integer (o, "fps-n", 30);
            m.fps_d = (int) Js.integer (o, "fps-d", 1);
            m.has_video = Js.flag (o, "video");
            m.has_audio = Js.flag (o, "audio");
            m.still = Js.flag (o, "still");
            m.channels = (int) Js.integer (o, "channels", 2);
            m.sample_rate = (int) Js.integer (o, "rate", 48000);
            m.colorimetry = Js.str (o, "colorimetry");
            m.transfer = Js.str (o, "transfer", "sdr");
            m.depth = (int) Js.integer (o, "depth", 8);
            m.variable_rate = Js.flag (o, "variable-rate");
            m.proxy_uri = Js.str (o, "proxy");
            m.proxy_state = Js.str (o, "proxy-state", "none");
            m.imported = Js.integer (o, "imported");
            foreach (var a in Js.objects (o, "angles"))
                m.angles.add (new MulticamAngle (Js.str (a, "media"), Js.str (a, "name"), Js.integer (a, "offset")));
            m.audio_angle = (int) Js.integer (o, "audio-angle");
            m.mark_in = Js.integer (o, "mark-in", -1);
            m.mark_out = Js.integer (o, "mark-out", -1);
            m.transcript = Js.str (o, "transcript");
            return m;
        }
    }

    public class Marker : Object {
        public string id = new_id ();
        public int64 time;
        public int64 duration;
        public string name = "";
        public string comment = "";
        public string kind = "comment";
        public int color;

        public Marker (int64 time, string name = "") {
            this.time = time;
            this.name = name;
        }

        public Marker copy () {
            var m = new Marker (time, name);
            m.id = id; m.duration = duration; m.comment = comment; m.kind = kind; m.color = color;
            return m;
        }

        public void write (Json.Builder b) {
            b.begin_object ();
            Js.s (b, "id", id);
            Js.i (b, "time", time);
            Js.i (b, "duration", duration);
            Js.s (b, "name", name);
            Js.s (b, "comment", comment);
            Js.s (b, "kind", kind);
            Js.i (b, "color", color);
            b.end_object ();
        }

        public static Marker read (Json.Object o) {
            var m = new Marker (Js.integer (o, "time"), Js.str (o, "name"));
            m.id = Js.str (o, "id", new_id ());
            m.duration = Js.integer (o, "duration");
            m.comment = Js.str (o, "comment");
            m.kind = Js.str (o, "kind", "comment");
            m.color = (int) Js.integer (o, "color");
            return m;
        }
    }

    public class ReviewReply : Object {
        public string author;
        public string text;
        public int64 created;

        public ReviewReply (string author, string text, int64 created) {
            this.author = author;
            this.text = text;
            this.created = created;
        }
    }

    public class ReviewComment : Object {
        public string id = new_id ();
        public int64 time;
        public int64 duration;
        public string author = "";
        public string text = "";
        public bool resolved;
        public int64 created;
        public Gee.ArrayList<ReviewReply> replies = new Gee.ArrayList<ReviewReply> ();

        public void write (Json.Builder b) {
            b.begin_object ();
            Js.s (b, "id", id);
            Js.i (b, "time", time);
            Js.i (b, "duration", duration);
            Js.s (b, "author", author);
            Js.s (b, "text", text);
            Js.f (b, "resolved", resolved);
            Js.i (b, "created", created);
            b.set_member_name ("replies");
            b.begin_array ();
            foreach (var r in replies) {
                b.begin_object ();
                Js.s (b, "author", r.author);
                Js.s (b, "text", r.text);
                Js.i (b, "created", r.created);
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();
        }

        public static ReviewComment read (Json.Object o) {
            var c = new ReviewComment ();
            c.id = Js.str (o, "id", new_id ());
            c.time = Js.integer (o, "time");
            c.duration = Js.integer (o, "duration");
            c.author = Js.str (o, "author");
            c.text = Js.str (o, "text");
            c.resolved = Js.flag (o, "resolved");
            c.created = Js.integer (o, "created");
            foreach (var r in Js.objects (o, "replies")) c.replies.add (new ReviewReply (Js.str (r, "author"), Js.str (r, "text"), Js.integer (r, "created")));
            return c;
        }
    }

    public class TitleLayer : Object {
        public string text = "";
        public string font = "Sans Bold";
        public double size = 72;
        public string color = "#ffffffff";
        public double outline;
        public string outline_color = "#000000ff";
        public double shadow;
        public double shadow_x = 4;
        public double shadow_y = 4;
        public string shadow_color = "#000000b0";
        public bool box;
        public string box_color = "#000000a0";
        public double box_padding = 16;
        public string align = "center";
        public double x = 50;
        public double y = 50;
        public double width = 90;
        public double spacing;
        public double tracking;

        public TitleLayer copy () {
            var l = new TitleLayer ();
            l.text = text; l.font = font; l.size = size; l.color = color; l.outline = outline; l.outline_color = outline_color;
            l.shadow = shadow; l.shadow_x = shadow_x; l.shadow_y = shadow_y; l.shadow_color = shadow_color;
            l.box = box; l.box_color = box_color; l.box_padding = box_padding; l.align = align;
            l.x = x; l.y = y; l.width = width; l.spacing = spacing; l.tracking = tracking;
            return l;
        }

        public void write (Json.Builder b) {
            b.begin_object ();
            Js.s (b, "text", text); Js.s (b, "font", font); Js.d (b, "size", size); Js.s (b, "color", color);
            Js.d (b, "outline", outline); Js.s (b, "outline-color", outline_color);
            Js.d (b, "shadow", shadow); Js.d (b, "shadow-x", shadow_x); Js.d (b, "shadow-y", shadow_y); Js.s (b, "shadow-color", shadow_color);
            Js.f (b, "box", box); Js.s (b, "box-color", box_color); Js.d (b, "box-padding", box_padding);
            Js.s (b, "align", align); Js.d (b, "x", x); Js.d (b, "y", y); Js.d (b, "width", width);
            Js.d (b, "spacing", spacing); Js.d (b, "tracking", tracking);
            b.end_object ();
        }

        public static TitleLayer read (Json.Object o) {
            var l = new TitleLayer ();
            l.text = Js.str (o, "text"); l.font = Js.str (o, "font", "Sans Bold"); l.size = Js.num (o, "size", 72);
            l.color = Js.str (o, "color", "#ffffffff"); l.outline = Js.num (o, "outline"); l.outline_color = Js.str (o, "outline-color", "#000000ff");
            l.shadow = Js.num (o, "shadow"); l.shadow_x = Js.num (o, "shadow-x", 4); l.shadow_y = Js.num (o, "shadow-y", 4);
            l.shadow_color = Js.str (o, "shadow-color", "#000000b0"); l.box = Js.flag (o, "box"); l.box_color = Js.str (o, "box-color", "#000000a0");
            l.box_padding = Js.num (o, "box-padding", 16); l.align = Js.str (o, "align", "center");
            l.x = Js.num (o, "x", 50); l.y = Js.num (o, "y", 50); l.width = Js.num (o, "width", 90);
            l.spacing = Js.num (o, "spacing"); l.tracking = Js.num (o, "tracking");
            return l;
        }
    }

    public class TitleData : Object {
        public Gee.ArrayList<TitleLayer> layers = new Gee.ArrayList<TitleLayer> ();
        public string mode = "still";
        public string anim_in = "none";
        public string anim_out = "none";
        public int64 anim_duration = 500000000;
        public string template_id = "";
        public Gee.TreeMap<string, string> fields = new Gee.TreeMap<string, string> ();

        public TitleData copy () {
            var t = new TitleData ();
            foreach (var l in layers) t.layers.add (l.copy ());
            t.mode = mode; t.anim_in = anim_in; t.anim_out = anim_out; t.anim_duration = anim_duration; t.template_id = template_id;
            foreach (var e in fields.entries) t.fields[e.key] = e.value;
            return t;
        }

        public void write (Json.Builder b) {
            b.begin_object ();
            Js.s (b, "mode", mode); Js.s (b, "in", anim_in); Js.s (b, "out", anim_out); Js.i (b, "anim", anim_duration);
            Js.s (b, "template", template_id);
            b.set_member_name ("fields");
            b.begin_object ();
            foreach (var e in fields.entries) Js.s (b, e.key, e.value);
            b.end_object ();
            b.set_member_name ("layers");
            b.begin_array ();
            foreach (var l in layers) l.write (b);
            b.end_array ();
            b.end_object ();
        }

        public static TitleData read (Json.Object o) {
            var t = new TitleData ();
            t.mode = Js.str (o, "mode", "still"); t.anim_in = Js.str (o, "in", "none"); t.anim_out = Js.str (o, "out", "none");
            t.anim_duration = Js.integer (o, "anim", 500000000); t.template_id = Js.str (o, "template");
            var f = Js.obj (o, "fields");
            if (f != null) foreach (var k in f.get_members ()) t.fields[k] = Js.str (f, k);
            foreach (var l in Js.objects (o, "layers")) t.layers.add (TitleLayer.read (l));
            return t;
        }
    }

    public class MulticamCut : Object {
        public int64 time;
        public int angle;

        public MulticamCut (int64 time, int angle) {
            this.time = time;
            this.angle = angle;
        }
    }

    public class Clip : Object {
        public string id = new_id ();
        public ClipKind kind = ClipKind.MEDIA;
        public string name = "";
        public string track = "";
        public int64 position;
        public int64 duration;
        public int64 in_point;
        public string media = "";
        public string sequence = "";
        public string link = "";
        public bool enabled = true;
        public int label;
        public bool reverse;
        public bool frame_blend = true;
        public string blend = "normal";
        public string color = "#000000ff";
        public string text = "";
        public string composition = "";
        public string color_space = "auto";
        public string role = "";
        public ParamSet params = new ParamSet ();
        public Gee.ArrayList<Effect> effects = new Gee.ArrayList<Effect> ();
        public TitleData? title;
        public Gee.ArrayList<MulticamCut> cuts = new Gee.ArrayList<MulticamCut> ();
        public Gee.ArrayList<Marker> markers = new Gee.ArrayList<Marker> ();

        public int64 end {
            get { return position + duration; }
        }

        public int64 key_time (int64 t) {
            return t - position + in_point;
        }

        public double speed_at (int64 key) {
            return params.get_value ("speed", key, 100) / 100.0;
        }

        public bool speed_changed {
            get {
                var s = params.values["speed"];
                return reverse || (s != null && (s.animated || s.value != 100));
            }
        }

        public int64 source_span () {
            var s = params.values["speed"];
            if (s == null || (!s.animated && s.value == 100)) return duration;
            return (int64) (s.integral (in_point, in_point + duration) / 100.0);
        }

        public int64 source_time (int64 t) {
            int64 u = (t - position).clamp (0, duration);
            var s = params.values["speed"];
            int64 offset;
            if (s == null || (!s.animated && s.value == 100)) offset = u;
            else offset = (int64) (s.integral (in_point, in_point + u) / 100.0);
            if (reverse) return in_point + int64.max (0, source_span () - offset - 1);
            return in_point + offset;
        }

        public Clip copy () {
            var c = new Clip ();
            c.id = id; c.kind = kind; c.name = name; c.track = track; c.position = position; c.duration = duration;
            c.in_point = in_point; c.media = media; c.sequence = sequence; c.link = link; c.enabled = enabled;
            c.label = label; c.reverse = reverse; c.frame_blend = frame_blend; c.blend = blend; c.color = color;
            c.text = text; c.composition = composition; c.color_space = color_space; c.role = role;
            c.params = params.copy ();
            foreach (var e in effects) c.effects.add (e.copy ());
            c.title = title != null ? title.copy () : null;
            foreach (var cut in cuts) c.cuts.add (new MulticamCut (cut.time, cut.angle));
            foreach (var m in markers) c.markers.add (m.copy ());
            return c;
        }

        public Effect? find_effect (string type) {
            foreach (var e in effects) if (e.type == type) return e;
            return null;
        }

        public int angle_at (int64 local) {
            int angle = 0;
            foreach (var cut in cuts) if (cut.time <= local) angle = cut.angle;
            return angle;
        }

        public void write (Json.Builder b) {
            b.begin_object ();
            Js.s (b, "id", id); Js.s (b, "kind", kind.key ()); Js.s (b, "name", name); Js.s (b, "track", track);
            Js.i (b, "position", position); Js.i (b, "duration", duration); Js.i (b, "in", in_point);
            Js.s (b, "media", media); Js.s (b, "sequence", sequence); Js.s (b, "link", link); Js.f (b, "enabled", enabled);
            Js.i (b, "label", label); Js.f (b, "reverse", reverse); Js.f (b, "frame-blend", frame_blend); Js.s (b, "blend", blend);
            Js.s (b, "color", color); Js.s (b, "text", text); Js.s (b, "composition", composition);
            Js.s (b, "color-space", color_space); Js.s (b, "role", role);
            b.set_member_name ("params");
            b.begin_object ();
            params.write (b);
            b.end_object ();
            b.set_member_name ("effects");
            b.begin_array ();
            foreach (var e in effects) e.write (b);
            b.end_array ();
            if (title != null) {
                b.set_member_name ("title");
                title.write (b);
            }
            b.set_member_name ("cuts");
            b.begin_array ();
            foreach (var cut in cuts) {
                b.begin_object ();
                Js.i (b, "time", cut.time);
                Js.i (b, "angle", cut.angle);
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("markers");
            b.begin_array ();
            foreach (var m in markers) m.write (b);
            b.end_array ();
            b.end_object ();
        }

        public static Clip read (Json.Object o) {
            var c = new Clip ();
            c.id = Js.str (o, "id", new_id ());
            c.kind = ClipKind.from_key (Js.str (o, "kind", "media"));
            c.name = Js.str (o, "name");
            c.track = Js.str (o, "track");
            c.position = Js.integer (o, "position");
            c.duration = Js.integer (o, "duration");
            c.in_point = Js.integer (o, "in");
            c.media = Js.str (o, "media");
            c.sequence = Js.str (o, "sequence");
            c.link = Js.str (o, "link");
            c.enabled = Js.flag (o, "enabled", true);
            c.label = (int) Js.integer (o, "label");
            c.reverse = Js.flag (o, "reverse");
            c.frame_blend = Js.flag (o, "frame-blend", true);
            c.blend = Js.str (o, "blend", "normal");
            c.color = Js.str (o, "color", "#000000ff");
            c.text = Js.str (o, "text");
            c.composition = Js.str (o, "composition");
            c.color_space = Js.str (o, "color-space", "auto");
            c.role = Js.str (o, "role");
            var p = Js.obj (o, "params");
            if (p != null) c.params.read (p);
            foreach (var e in Js.objects (o, "effects")) c.effects.add (Effect.read (e));
            var t = Js.obj (o, "title");
            if (t != null) c.title = TitleData.read (t);
            foreach (var cut in Js.objects (o, "cuts")) c.cuts.add (new MulticamCut (Js.integer (cut, "time"), (int) Js.integer (cut, "angle")));
            foreach (var m in Js.objects (o, "markers")) c.markers.add (Marker.read (m));
            return c;
        }
    }

    public class Track : Object {
        public string id = new_id ();
        public string name;
        public TrackKind kind;
        public bool locked;
        public bool muted;
        public bool solo;
        public bool visible = true;
        public bool sync_lock = true;
        public bool target = true;
        public string bus = "master";
        public string role = "";
        public AnimatedValue volume = new AnimatedValue (0);
        public AnimatedValue pan = new AnimatedValue (0);
        public Gee.ArrayList<Effect> effects = new Gee.ArrayList<Effect> ();

        public Track (string name, TrackKind kind) {
            this.name = name;
            this.kind = kind;
        }

        public Track copy () {
            var t = new Track (name, kind);
            t.id = id; t.locked = locked; t.muted = muted; t.solo = solo; t.visible = visible;
            t.sync_lock = sync_lock; t.target = target; t.bus = bus; t.role = role;
            t.volume = volume.copy (); t.pan = pan.copy ();
            foreach (var e in effects) t.effects.add (e.copy ());
            return t;
        }

        public void write (Json.Builder b) {
            b.begin_object ();
            Js.s (b, "id", id); Js.s (b, "name", name); Js.s (b, "kind", kind.key ());
            Js.f (b, "locked", locked); Js.f (b, "muted", muted); Js.f (b, "solo", solo); Js.f (b, "visible", visible);
            Js.f (b, "sync-lock", sync_lock); Js.f (b, "target", target); Js.s (b, "bus", bus); Js.s (b, "role", role);
            b.set_member_name ("volume"); b.add_value (volume.to_json ());
            b.set_member_name ("pan"); b.add_value (pan.to_json ());
            b.set_member_name ("effects");
            b.begin_array ();
            foreach (var e in effects) e.write (b);
            b.end_array ();
            b.end_object ();
        }

        public static Track read (Json.Object o) {
            var t = new Track (Js.str (o, "name", "Track"), TrackKind.from_key (Js.str (o, "kind", "video")));
            t.id = Js.str (o, "id", new_id ());
            t.locked = Js.flag (o, "locked"); t.muted = Js.flag (o, "muted"); t.solo = Js.flag (o, "solo");
            t.visible = Js.flag (o, "visible", true); t.sync_lock = Js.flag (o, "sync-lock", true); t.target = Js.flag (o, "target", true);
            t.bus = Js.str (o, "bus", "master"); t.role = Js.str (o, "role");
            t.volume = AnimatedValue.from_json (o.has_member ("volume") ? o.get_member ("volume") : null, 0);
            t.pan = AnimatedValue.from_json (o.has_member ("pan") ? o.get_member ("pan") : null, 0);
            foreach (var e in Js.objects (o, "effects")) t.effects.add (Effect.read (e));
            return t;
        }
    }

    public class Bus : Object {
        public string id = new_id ();
        public string name;
        public bool muted;
        public AnimatedValue volume = new AnimatedValue (0);
        public AnimatedValue pan = new AnimatedValue (0);
        public Gee.ArrayList<Effect> effects = new Gee.ArrayList<Effect> ();

        public Bus (string name) {
            this.name = name;
        }

        public Bus copy () {
            var b = new Bus (name);
            b.id = id; b.muted = muted; b.volume = volume.copy (); b.pan = pan.copy ();
            foreach (var e in effects) b.effects.add (e.copy ());
            return b;
        }

        public void write (Json.Builder b) {
            b.begin_object ();
            Js.s (b, "id", id); Js.s (b, "name", name); Js.f (b, "muted", muted);
            b.set_member_name ("volume"); b.add_value (volume.to_json ());
            b.set_member_name ("pan"); b.add_value (pan.to_json ());
            b.set_member_name ("effects");
            b.begin_array ();
            foreach (var e in effects) e.write (b);
            b.end_array ();
            b.end_object ();
        }

        public static Bus read (Json.Object o) {
            var b = new Bus (Js.str (o, "name", "Bus"));
            b.id = Js.str (o, "id", new_id ());
            b.muted = Js.flag (o, "muted");
            b.volume = AnimatedValue.from_json (o.has_member ("volume") ? o.get_member ("volume") : null, 0);
            b.pan = AnimatedValue.from_json (o.has_member ("pan") ? o.get_member ("pan") : null, 0);
            foreach (var e in Js.objects (o, "effects")) b.effects.add (Effect.read (e));
            return b;
        }
    }

    public class Transition : Object {
        public string id = new_id ();
        public string track = "";
        public string from_clip = "";
        public string to_clip = "";
        public string kind = "dissolve";
        public int64 duration = 1000000000;
        public int align;
        public string direction = "left";
        public string color = "#000000ff";
        public double softness = 0.05;

        public Transition copy () {
            var t = new Transition ();
            t.id = id; t.track = track; t.from_clip = from_clip; t.to_clip = to_clip; t.kind = kind;
            t.duration = duration; t.align = align; t.direction = direction; t.color = color; t.softness = softness;
            return t;
        }

        public void write (Json.Builder b) {
            b.begin_object ();
            Js.s (b, "id", id); Js.s (b, "track", track); Js.s (b, "from", from_clip); Js.s (b, "to", to_clip);
            Js.s (b, "kind", kind); Js.i (b, "duration", duration); Js.i (b, "align", align);
            Js.s (b, "direction", direction); Js.s (b, "color", color); Js.d (b, "softness", softness);
            b.end_object ();
        }

        public static Transition read (Json.Object o) {
            var t = new Transition ();
            t.id = Js.str (o, "id", new_id ()); t.track = Js.str (o, "track"); t.from_clip = Js.str (o, "from");
            t.to_clip = Js.str (o, "to"); t.kind = Js.str (o, "kind", "dissolve"); t.duration = Js.integer (o, "duration", 1000000000);
            t.align = (int) Js.integer (o, "align"); t.direction = Js.str (o, "direction", "left");
            t.color = Js.str (o, "color", "#000000ff"); t.softness = Js.num (o, "softness", 0.05);
            return t;
        }

        public int64 start_at (int64 cut) {
            if (align < 0) return cut - duration;
            if (align > 0) return cut;
            return cut - duration / 2;
        }
    }

    public class Sequence : Object {
        public string id = new_id ();
        public string name;
        public int width = 1920;
        public int height = 1080;
        public int fps_n = 30;
        public int fps_d = 1;
        public int sample_rate = 48000;
        public string color_space = "rec709";
        public double loudness_target = -14;
        public bool normalize;
        public int64 in_point = -1;
        public int64 out_point = -1;
        public int64 playhead;
        public Gee.ArrayList<Track> tracks = new Gee.ArrayList<Track> ();
        public Gee.ArrayList<Bus> buses = new Gee.ArrayList<Bus> ();
        public Gee.ArrayList<Clip> clips = new Gee.ArrayList<Clip> ();
        public Gee.ArrayList<Transition> transitions = new Gee.ArrayList<Transition> ();
        public Gee.ArrayList<Marker> markers = new Gee.ArrayList<Marker> ();
        public Gee.ArrayList<ReviewComment> comments = new Gee.ArrayList<ReviewComment> ();
        public AnimatedValue master_volume = new AnimatedValue (0);
        public Gee.ArrayList<Effect> master_effects = new Gee.ArrayList<Effect> ();

        public Sequence (string name) {
            this.name = name;
        }

        public void add_default_tracks () {
            tracks.add (new Track ("V1", TrackKind.VIDEO));
            tracks.add (new Track ("V2", TrackKind.VIDEO));
            tracks.add (new Track ("A1", TrackKind.AUDIO));
            tracks.add (new Track ("A2", TrackKind.AUDIO));
        }

        public int64 frame {
            get { return Tc.frame_duration (fps_n, fps_d); }
        }

        public int64 snap (int64 t) {
            return Tc.snap (t, fps_n, fps_d);
        }

        public int64 duration {
            get {
                int64 d = 0;
                foreach (var c in clips) d = int64.max (d, c.end);
                return d;
            }
        }

        public Track? track (string id) {
            foreach (var t in tracks) if (t.id == id) return t;
            return null;
        }

        public int track_index (string id) {
            for (int i = 0; i < tracks.size; i++) if (tracks[i].id == id) return i;
            return -1;
        }

        public Clip? clip (string id) {
            foreach (var c in clips) if (c.id == id) return c;
            return null;
        }

        public Bus? bus (string id) {
            foreach (var b in buses) if (b.id == id) return b;
            return null;
        }

        public Transition? transition (string id) {
            foreach (var t in transitions) if (t.id == id) return t;
            return null;
        }

        public Gee.ArrayList<Track> tracks_of (TrackKind kind) {
            var r = new Gee.ArrayList<Track> ();
            foreach (var t in tracks) if (t.kind == kind) r.add (t);
            return r;
        }

        public Gee.ArrayList<Clip> on_track (string track_id) {
            var r = new Gee.ArrayList<Clip> ();
            foreach (var c in clips) if (c.track == track_id) r.add (c);
            r.sort ((a, b) => a.position < b.position ? -1 : (a.position > b.position ? 1 : 0));
            return r;
        }

        public Clip? clip_at (string track_id, int64 t) {
            Clip? found = null;
            foreach (var c in clips) if (c.track == track_id && t >= c.position && t < c.end) found = c;
            return found;
        }

        public Gee.ArrayList<Clip> linked (Clip c) {
            var r = new Gee.ArrayList<Clip> ();
            if (c.link == "") {
                r.add (c);
                return r;
            }
            foreach (var other in clips) if (other.link == c.link) r.add (other);
            return r;
        }

        public Transition? transition_between (string from, string to) {
            foreach (var t in transitions) if (t.from_clip == from && t.to_clip == to) return t;
            return null;
        }

        public Gee.ArrayList<Transition> transitions_of (string clip_id) {
            var r = new Gee.ArrayList<Transition> ();
            foreach (var t in transitions) if (t.from_clip == clip_id || t.to_clip == clip_id) r.add (t);
            return r;
        }

        public Gee.ArrayList<int64?> edit_points () {
            var set = new Gee.TreeSet<int64?> ((a, b) => a < b ? -1 : (a > b ? 1 : 0));
            set.add (0);
            foreach (var c in clips) {
                set.add (c.position);
                set.add (c.end);
            }
            foreach (var m in markers) set.add (m.time);
            var r = new Gee.ArrayList<int64?> ();
            foreach (var v in set) r.add (v);
            return r;
        }

        public Sequence copy () {
            var s = new Sequence (name);
            s.id = id; s.width = width; s.height = height; s.fps_n = fps_n; s.fps_d = fps_d; s.sample_rate = sample_rate;
            s.color_space = color_space; s.loudness_target = loudness_target; s.normalize = normalize;
            s.in_point = in_point; s.out_point = out_point; s.playhead = playhead;
            foreach (var t in tracks) s.tracks.add (t.copy ());
            foreach (var b in buses) s.buses.add (b.copy ());
            foreach (var c in clips) s.clips.add (c.copy ());
            foreach (var t in transitions) s.transitions.add (t.copy ());
            foreach (var m in markers) s.markers.add (m.copy ());
            foreach (var c in comments) s.comments.add (c);
            s.master_volume = master_volume.copy ();
            foreach (var e in master_effects) s.master_effects.add (e.copy ());
            return s;
        }

        public void write (Json.Builder b) {
            b.begin_object ();
            Js.s (b, "id", id); Js.s (b, "name", name); Js.i (b, "width", width); Js.i (b, "height", height);
            Js.i (b, "fps-n", fps_n); Js.i (b, "fps-d", fps_d); Js.i (b, "rate", sample_rate);
            Js.s (b, "color-space", color_space); Js.d (b, "loudness-target", loudness_target); Js.f (b, "normalize", normalize);
            Js.i (b, "in", in_point); Js.i (b, "out", out_point); Js.i (b, "playhead", playhead);
            b.set_member_name ("master-volume"); b.add_value (master_volume.to_json ());
            b.set_member_name ("master-effects");
            b.begin_array ();
            foreach (var e in master_effects) e.write (b);
            b.end_array ();
            b.set_member_name ("tracks");
            b.begin_array ();
            foreach (var t in tracks) t.write (b);
            b.end_array ();
            b.set_member_name ("buses");
            b.begin_array ();
            foreach (var bus in buses) bus.write (b);
            b.end_array ();
            b.set_member_name ("clips");
            b.begin_array ();
            foreach (var c in clips) c.write (b);
            b.end_array ();
            b.set_member_name ("transitions");
            b.begin_array ();
            foreach (var t in transitions) t.write (b);
            b.end_array ();
            b.set_member_name ("markers");
            b.begin_array ();
            foreach (var m in markers) m.write (b);
            b.end_array ();
            b.set_member_name ("comments");
            b.begin_array ();
            foreach (var c in comments) c.write (b);
            b.end_array ();
            b.end_object ();
        }

        public static Sequence read (Json.Object o) throws Error {
            var s = new Sequence (Js.str (o, "name", _("Sequence")));
            s.id = Js.str (o, "id", new_id ());
            s.width = (int) Js.integer (o, "width", 1920).clamp (16, 16384);
            s.height = (int) Js.integer (o, "height", 1080).clamp (16, 16384);
            s.fps_n = (int) Js.integer (o, "fps-n", 30).clamp (1, 240000);
            s.fps_d = (int) Js.integer (o, "fps-d", 1).clamp (1, 100000);
            s.sample_rate = (int) Js.integer (o, "rate", 48000).clamp (8000, 192000);
            s.color_space = Js.str (o, "color-space", "rec709");
            s.loudness_target = Js.num (o, "loudness-target", -14);
            s.normalize = Js.flag (o, "normalize");
            s.in_point = Js.integer (o, "in", -1);
            s.out_point = Js.integer (o, "out", -1);
            s.playhead = Js.integer (o, "playhead");
            s.master_volume = AnimatedValue.from_json (o.has_member ("master-volume") ? o.get_member ("master-volume") : null, 0);
            foreach (var e in Js.objects (o, "master-effects")) s.master_effects.add (Effect.read (e));
            var ids = new Gee.HashSet<string> ();
            foreach (var t in Js.objects (o, "tracks")) {
                var track = Track.read (t);
                if (!ids.add (track.id)) throw new IOError.INVALID_DATA (_("The project has a duplicated track."));
                s.tracks.add (track);
            }
            foreach (var bus in Js.objects (o, "buses")) s.buses.add (Bus.read (bus));
            var clip_ids = new Gee.HashSet<string> ();
            foreach (var c in Js.objects (o, "clips")) {
                var clip = Clip.read (c);
                if (!ids.contains (clip.track) || !clip_ids.add (clip.id) || clip.duration <= 0 || clip.position < 0 || clip.in_point < 0)
                    throw new IOError.INVALID_DATA (_("The project has an invalid clip."));
                s.clips.add (clip);
            }
            foreach (var t in Js.objects (o, "transitions")) s.transitions.add (Transition.read (t));
            foreach (var m in Js.objects (o, "markers")) s.markers.add (Marker.read (m));
            foreach (var c in Js.objects (o, "comments")) s.comments.add (ReviewComment.read (c));
            return s;
        }
    }
}
