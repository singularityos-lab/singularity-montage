namespace Singularity.Apps.Montage {
    public class Project : Object {
        public const int VERSION = 3;
        public string name = "";
        public Gee.ArrayList<MediaItem> media = new Gee.ArrayList<MediaItem> ();
        public Gee.ArrayList<Bin> bins = new Gee.ArrayList<Bin> ();
        public Gee.ArrayList<Sequence> sequences = new Gee.ArrayList<Sequence> ();
        public string active = "";
        public bool use_proxies = true;
        public Gee.HashSet<string> foreign_locks = new Gee.HashSet<string> ();
        public string notes = "";
        Gee.ArrayList<string> undo_stack = new Gee.ArrayList<string> ();
        Gee.ArrayList<string> redo_stack = new Gee.ArrayList<string> ();
        Gee.ArrayList<string> undo_labels = new Gee.ArrayList<string> ();
        Gee.ArrayList<string> redo_labels = new Gee.ArrayList<string> ();
        public int revision { get; private set; }
        public signal void changed ();
        public signal void media_changed ();

        public Project () {
            var s = new Sequence (_("Sequence 1"));
            s.add_default_tracks ();
            sequences.add (s);
            active = s.id;
        }

        public Sequence sequence {
            owned get {
                foreach (var s in sequences) if (s.id == active) return s;
                return sequences[0];
            }
        }

        public Sequence? find_sequence (string id) {
            foreach (var s in sequences) if (s.id == id) return s;
            return null;
        }

        public MediaItem? find_media (string id) {
            foreach (var m in media) if (m.id == id) return m;
            return null;
        }

        public MediaItem? media_by_uri (string uri) {
            foreach (var m in media) if (m.uri == uri) return m;
            return null;
        }

        public Bin? find_bin (string id) {
            foreach (var b in bins) if (b.id == id) return b;
            return null;
        }

        public bool can_undo {
            get { return undo_stack.size > 0; }
        }

        public bool can_redo {
            get { return redo_stack.size > 0; }
        }

        public string undo_label {
            owned get { return undo_labels.size > 0 ? undo_labels[undo_labels.size - 1] : ""; }
        }

        int batch_depth;

        public void begin_batch (string label) {
            if (batch_depth == 0) checkpoint (label);
            batch_depth++;
        }

        public void end_batch () {
            if (batch_depth > 0) batch_depth--;
            if (batch_depth == 0) commit ();
        }

        public void checkpoint (string label) {
            if (batch_depth > 0) return;
            coalesce_key = "";
            push_undo (label);
        }

        void push_undo (string label) {
            undo_stack.add (serialize ());
            undo_labels.add (label);
            if (undo_stack.size > 200) {
                undo_stack.remove_at (0);
                undo_labels.remove_at (0);
            }
            redo_stack.clear ();
            redo_labels.clear ();
        }

        string coalesce_key = "";
        int64 coalesce_time;

        public void checkpoint_once (string key, string label) {
            int64 now = get_monotonic_time ();
            if (key == coalesce_key && now - coalesce_time < 1500000 && undo_stack.size > 0) {
                coalesce_time = now;
                return;
            }
            push_undo (label);
            coalesce_key = key;
            coalesce_time = now;
        }

        public void drop_checkpoint () {
            if (undo_stack.size == 0) return;
            undo_stack.remove_at (undo_stack.size - 1);
            undo_labels.remove_at (undo_labels.size - 1);
        }

        public void commit () {
            revision++;
            changed ();
        }

        public void undo () {
            if (!can_undo) return;
            redo_stack.add (serialize ());
            redo_labels.add (undo_labels.remove_at (undo_labels.size - 1));
            restore (undo_stack.remove_at (undo_stack.size - 1));
        }

        public void redo () {
            if (!can_redo) return;
            undo_stack.add (serialize ());
            undo_labels.add (redo_labels.remove_at (redo_labels.size - 1));
            restore (redo_stack.remove_at (redo_stack.size - 1));
        }

        void restore (string data) {
            try {
                var other = Project.parse (data);
                take (other);
            } catch (Error e) {
                warning ("Could not restore project state: %s", e.message);
            }
            revision++;
            media_changed ();
            changed ();
        }

        void take (Project other) {
            name = other.name;
            media = other.media;
            bins = other.bins;
            sequences = other.sequences;
            active = other.active;
            use_proxies = other.use_proxies;
            notes = other.notes;
        }

        public void replace_with (Project other) {
            take (other);
            undo_stack.clear ();
            redo_stack.clear ();
            undo_labels.clear ();
            redo_labels.clear ();
            revision++;
            media_changed ();
            changed ();
        }

        public Project clone () {
            try {
                return Project.parse (serialize ());
            } catch (Error e) {
                error ("Project clone failed: %s", e.message);
            }
        }

        public string serialize (bool pretty = false) {
            var b = new Json.Builder ();
            b.begin_object ();
            Js.s (b, "format", "montage");
            Js.i (b, "version", VERSION);
            Js.s (b, "name", name);
            Js.s (b, "active", active);
            Js.f (b, "proxies", use_proxies);
            Js.s (b, "notes", notes);
            b.set_member_name ("bins");
            b.begin_array ();
            foreach (var bin in bins) {
                b.begin_object ();
                Js.s (b, "id", bin.id);
                Js.s (b, "name", bin.name);
                Js.s (b, "parent", bin.parent);
                Js.i (b, "label", bin.label);
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("media");
            b.begin_array ();
            foreach (var m in media) m.write (b);
            b.end_array ();
            b.set_member_name ("sequences");
            b.begin_array ();
            foreach (var s in sequences) s.write (b);
            b.end_array ();
            b.end_object ();
            return Js.write (b.get_root (), pretty);
        }

        public static Project parse (string data) throws Error {
            if (data.length > 256 * 1024 * 1024) throw new IOError.INVALID_DATA (_("The project is too large to open."));
            var o = Js.parse (data);
            if (Js.str (o, "format") != "montage") throw new IOError.INVALID_DATA (_("This is not a Montage project."));
            if (Js.integer (o, "version") > VERSION) throw new IOError.NOT_SUPPORTED (_("This project was made by a newer Montage."));
            var p = new Project ();
            p.sequences.clear ();
            p.name = Js.str (o, "name");
            p.use_proxies = Js.flag (o, "proxies", true);
            p.notes = Js.str (o, "notes");
            foreach (var bo in Js.objects (o, "bins")) {
                var bin = new Bin (Js.str (bo, "name", _("Bin")));
                bin.id = Js.str (bo, "id", new_id ());
                bin.parent = Js.str (bo, "parent");
                bin.label = (int) Js.integer (bo, "label");
                p.bins.add (bin);
            }
            var ids = new Gee.HashSet<string> ();
            foreach (var mo in Js.objects (o, "media")) {
                var m = MediaItem.read (mo);
                if (!ids.add (m.id)) throw new IOError.INVALID_DATA (_("The project has a duplicated media item."));
                if (m.kind == "file" && (m.uri.length > 8192 || Uri.parse_scheme (m.uri) == null))
                    throw new IOError.INVALID_DATA (_("The project has an invalid media location."));
                p.media.add (m);
            }
            foreach (var so in Js.objects (o, "sequences")) p.sequences.add (Sequence.read (so));
            if (p.sequences.size == 0) throw new IOError.INVALID_DATA (_("The project has no sequences."));
            p.active = Js.str (o, "active", p.sequences[0].id);
            if (p.find_sequence (p.active) == null) p.active = p.sequences[0].id;
            return p;
        }

        public Gee.ArrayList<MediaItem> search (string query, string bin_id, int label) {
            var r = new Gee.ArrayList<MediaItem> ();
            foreach (var m in media) {
                if (bin_id != "*" && m.bin != bin_id) continue;
                if (label > 0 && m.label != label) continue;
                if (!m.matches (query)) continue;
                r.add (m);
            }
            return r;
        }

        public bool sequence_contains (Sequence outer, string inner_id) {
            if (outer.id == inner_id) return true;
            foreach (var c in outer.clips) {
                if (c.kind != ClipKind.SEQUENCE) continue;
                var nested = find_sequence (c.sequence);
                if (nested != null && sequence_contains (nested, inner_id)) return true;
            }
            return false;
        }

        public int64 media_length (Clip c) {
            switch (c.kind) {
                case ClipKind.MEDIA: {
                    var m = find_media (c.media);
                    if (m == null || m.still) return int64.MAX / 4;
                    return m.duration;
                }
                case ClipKind.SEQUENCE: {
                    var s = find_sequence (c.sequence);
                    return s != null ? s.duration : 0;
                }
                case ClipKind.MULTICAM: {
                    var m = find_media (c.media);
                    return m != null ? m.duration : 0;
                }
                default:
                    return int64.MAX / 4;
            }
        }

        public string clip_label (Clip c) {
            if (c.name != "") return c.name;
            switch (c.kind) {
                case ClipKind.MEDIA:
                case ClipKind.MULTICAM: {
                    var m = find_media (c.media);
                    return m != null ? m.name : _("Missing Media");
                }
                case ClipKind.SEQUENCE: {
                    var s = find_sequence (c.sequence);
                    return s != null ? s.name : _("Missing Sequence");
                }
                case ClipKind.TITLE: return c.title != null && c.title.layers.size > 0 ? Titles.expand (c.title.layers[0].text, c.title).replace ("\n", " ") : _("Title");
                case ClipKind.COLOR: return _("Colour Matte");
                case ClipKind.ADJUSTMENT: return _("Adjustment Layer");
                case ClipKind.COMPOSITION: return File.new_for_uri (c.composition).get_basename () ?? _("Composition");
                case ClipKind.SUBTITLE: return c.text;
                default: return "";
            }
        }
    }
}
