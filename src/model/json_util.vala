namespace Singularity.Apps.Montage {
    namespace Js {
        public string str (Json.Object o, string name, string fallback = "") {
            if (!o.has_member (name)) return fallback;
            var n = o.get_member (name);
            if (n.get_node_type () != Json.NodeType.VALUE || n.get_value_type () != typeof (string)) return fallback;
            return n.get_string ();
        }

        public int64 integer (Json.Object o, string name, int64 fallback = 0) {
            if (!o.has_member (name)) return fallback;
            var n = o.get_member (name);
            if (n.get_node_type () != Json.NodeType.VALUE) return fallback;
            var t = n.get_value_type ();
            if (t == typeof (int64)) return n.get_int ();
            if (t == typeof (double)) return (int64) n.get_double ();
            return fallback;
        }

        public double num (Json.Object o, string name, double fallback = 0) {
            if (!o.has_member (name)) return fallback;
            var n = o.get_member (name);
            if (n.get_node_type () != Json.NodeType.VALUE) return fallback;
            var t = n.get_value_type ();
            if (t == typeof (double)) return n.get_double ();
            if (t == typeof (int64)) return (double) n.get_int ();
            return fallback;
        }

        public bool flag (Json.Object o, string name, bool fallback = false) {
            if (!o.has_member (name)) return fallback;
            var n = o.get_member (name);
            if (n.get_node_type () != Json.NodeType.VALUE || n.get_value_type () != typeof (bool)) return fallback;
            return n.get_boolean ();
        }

        public Json.Array? arr (Json.Object o, string name) {
            if (!o.has_member (name)) return null;
            var n = o.get_member (name);
            return n.get_node_type () == Json.NodeType.ARRAY ? n.get_array () : null;
        }

        public Json.Object? obj (Json.Object o, string name) {
            if (!o.has_member (name)) return null;
            var n = o.get_member (name);
            return n.get_node_type () == Json.NodeType.OBJECT ? n.get_object () : null;
        }

        public Gee.ArrayList<Json.Object> objects (Json.Object o, string name) {
            var result = new Gee.ArrayList<Json.Object> ();
            var a = arr (o, name);
            if (a == null) return result;
            foreach (var n in a.get_elements ()) if (n.get_node_type () == Json.NodeType.OBJECT) result.add (n.get_object ());
            return result;
        }

        public void s (Json.Builder b, string name, string value) {
            b.set_member_name (name);
            b.add_string_value (value);
        }

        public void i (Json.Builder b, string name, int64 value) {
            b.set_member_name (name);
            b.add_int_value (value);
        }

        public void d (Json.Builder b, string name, double value) {
            b.set_member_name (name);
            b.add_double_value (value);
        }

        public void f (Json.Builder b, string name, bool value) {
            b.set_member_name (name);
            b.add_boolean_value (value);
        }

        public Json.Object parse (string data) throws Error {
            var parser = new Json.Parser ();
            parser.load_from_data (data, -1);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT)
                throw new IOError.INVALID_DATA (_("The document is not a valid JSON object."));
            return root.get_object ();
        }

        public string write (Json.Node node, bool pretty = false) {
            var g = new Json.Generator ();
            g.pretty = pretty;
            g.set_root (node);
            return g.to_data (null);
        }
    }

    namespace Tc {
        public const int64 SECOND = 1000000000;

        public int64 frame_duration (int fps_n, int fps_d) {
            return (int64) ((double) SECOND * fps_d / int.max (1, fps_n));
        }

        public int64 to_frames (int64 t, int fps_n, int fps_d) {
            return (int64) Math.floor ((double) t * fps_n / fps_d / SECOND + 1e-6);
        }

        public int64 from_frames (int64 frames, int fps_n, int fps_d) {
            return (int64) Math.round ((double) frames * fps_d * SECOND / int.max (1, fps_n));
        }

        public int64 snap (int64 t, int fps_n, int fps_d) {
            return from_frames ((int64) Math.round ((double) t * fps_n / fps_d / SECOND), fps_n, fps_d);
        }

        public int nominal (int fps_n, int fps_d) {
            return int.max (1, (int) Math.round ((double) fps_n / int.max (1, fps_d)));
        }

        public string format (int64 t, int fps_n, int fps_d) {
            bool negative = t < 0;
            int64 frames = to_frames (negative ? -t : t, fps_n, fps_d);
            int fps = nominal (fps_n, fps_d);
            int64 ff = frames % fps;
            int64 total = frames / fps;
            return "%s%02d:%02d:%02d:%02d".printf (negative ? "-" : "", (int) (total / 3600), (int) ((total / 60) % 60), (int) (total % 60), (int) ff);
        }

        public int64 parse (string text, int fps_n, int fps_d) throws Error {
            var parts = text.strip ().replace (";", ":").split (":");
            if (parts.length != 4) throw new IOError.INVALID_ARGUMENT (_("Use the format HH:MM:SS:FF."));
            int64 h = int64.parse (parts[0]), m = int64.parse (parts[1]), sec = int64.parse (parts[2]), ff = int64.parse (parts[3]);
            int fps = nominal (fps_n, fps_d);
            return from_frames (((h * 60 + m) * 60 + sec) * fps + ff, fps_n, fps_d);
        }

        public string clock (int64 t) {
            int64 ms = (t < 0 ? -t : t) / 1000000;
            return "%s%02d:%02d.%03d".printf (t < 0 ? "-" : "", (int) (ms / 60000), (int) ((ms / 1000) % 60), (int) (ms % 1000));
        }

        public string srt (int64 t) {
            int64 ms = int64.max (0, t) / 1000000;
            return "%02d:%02d:%02d,%03d".printf ((int) (ms / 3600000), (int) ((ms / 60000) % 60), (int) ((ms / 1000) % 60), (int) (ms % 1000));
        }

        public string vtt (int64 t) {
            return srt (t).replace (",", ".");
        }
    }
}
