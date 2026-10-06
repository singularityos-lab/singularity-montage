namespace Singularity.Apps.Montage {
    namespace Premiere {
        public const int64 TICKS = 254016000000;

        int64 ticks (string v) {
            return (int64) ((double) int64.parse (v.strip ()) / TICKS * Tc.SECOND);
        }

        public uint8[] gunzip (uint8[] data) throws Error {
            if (data.length < 2 || data[0] != 0x1f || data[1] != 0x8b) return data;
            var conv = new ZlibDecompressor (ZlibCompressorFormat.GZIP);
            var stream = new ConverterInputStream (new MemoryInputStream.from_data (data), conv);
            var out_buf = new ByteArray ();
            var chunk = new uint8[65536];
            ssize_t n;
            while ((n = stream.read (chunk)) > 0) out_buf.append (chunk[0:n]);
            return out_buf.steal ();
        }

        class Index {
            public Gee.HashMap<string, Xml.Node*> by_id = new Gee.HashMap<string, Xml.Node*> ();
            public Gee.HashMap<string, Xml.Node*> by_uid = new Gee.HashMap<string, Xml.Node*> ();

            public Xml.Node* resolve (Xml.Node* reference) {
                if (reference == null) return null;
                string? r = reference->get_prop ("ObjectRef");
                if (r != null) return by_id[r];
                string? u = reference->get_prop ("ObjectURef");
                if (u != null) return by_uid[u];
                return null;
            }
        }

        void index_all (Xml.Node* n, Index idx) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                string? id = c->get_prop ("ObjectID");
                if (id != null) idx.by_id[id] = c;
                string? uid = c->get_prop ("ObjectUID");
                if (uid != null) idx.by_uid[uid] = c;
                if (c->children != null) index_all (c, idx);
            }
        }

        Xml.Node* path (Xml.Node* n, string spec) {
            Xml.Node* cur = n;
            foreach (var part in spec.split ("/")) {
                if (cur == null) return null;
                cur = InterchangeFormats.child (cur, part);
            }
            return cur;
        }

        public Project read (uint8[] raw, File? origin) throws Error {
            var data = gunzip (raw);
            var sb = new StringBuilder.sized (data.length + 1);
            sb.append_len ((string) data, data.length);
            string text = sb.str;
            var doc = InterchangeFormats.parse_xml (text);
            var p = InterchangeFormats.empty_project (_("Premiere Project"));
            p.sequences.clear ();
            int skipped = 0;
            try {
                var root = doc->get_root_element ();
                if (root == null || root->name != "PremiereData") throw new IOError.INVALID_DATA (_("This is not a Premiere Pro project."));
                var idx = new Index ();
                index_all (root, idx);
                var media_cache = new Gee.HashMap<string, MediaItem> ();
                foreach (var n in InterchangeFormats.children (root, "Sequence")) {
                    if (n->get_prop ("ObjectUID") == null) continue;
                    var s = new Sequence (InterchangeFormats.text (n, "Name", _("Sequence")));
                    p.sequences.add (s);
                    var groups = InterchangeFormats.child (n, "TrackGroups");
                    int vi = 0, ai = 0;
                    foreach (var tg in InterchangeFormats.children (groups, "TrackGroup")) {
                        var group = idx.resolve (InterchangeFormats.child (tg, "Second"));
                        if (group == null) continue;
                        bool audio = group->name == "AudioTrackGroup";
                        if (group->name != "VideoTrackGroup" && !audio) continue;
                        var inner = InterchangeFormats.child (group, "TrackGroup");
                        string rate = InterchangeFormats.text (inner, "FrameRate", "");
                        if (!audio && rate != "") {
                            double fps = (double) TICKS / double.max (1, double.parse (rate));
                            if ((fps - 29.97).abs () < 0.01) {
                                s.fps_n = 30000;
                                s.fps_d = 1001;
                            } else if ((fps - 23.976).abs () < 0.01) {
                                s.fps_n = 24000;
                                s.fps_d = 1001;
                            } else {
                                s.fps_n = int.max (1, (int) Math.round (fps));
                                s.fps_d = 1;
                            }
                        }
                        foreach (var tr in InterchangeFormats.children (InterchangeFormats.child (inner, "Tracks"), "Track")) {
                            var track_node = idx.resolve (tr);
                            if (track_node == null) continue;
                            var t = InterchangeFormats.ensure_track (s, audio ? TrackKind.AUDIO : TrackKind.VIDEO, audio ? ai++ : vi++);
                            var items = path (track_node, "ClipTrack/ClipItems/TrackItems");
                            foreach (var ti in InterchangeFormats.children (items, "TrackItem")) {
                                var item = idx.resolve (ti);
                                if (item == null) continue;
                                var cti = InterchangeFormats.child (item, "ClipTrackItem");
                                var trackitem = InterchangeFormats.child (cti, "TrackItem");
                                int64 start = ticks (InterchangeFormats.text (trackitem, "Start", "0"));
                                int64 end = ticks (InterchangeFormats.text (trackitem, "End", "0"));
                                var sub = idx.resolve (InterchangeFormats.child (cti, "SubClip"));
                                var clip_node = sub != null ? idx.resolve (InterchangeFormats.child (sub, "Clip")) : null;
                                var clip_inner = clip_node != null ? InterchangeFormats.child (clip_node, "Clip") : null;
                                var source = clip_inner != null ? idx.resolve (InterchangeFormats.child (clip_inner, "Source")) : null;
                                var media_ref = source != null ? path (source, "MediaSource/Media") : null;
                                var media_node = idx.resolve (media_ref);
                                if (media_node == null || end <= start) {
                                    skipped++;
                                    continue;
                                }
                                string file_path = InterchangeFormats.text (media_node, "ActualMediaFilePath", InterchangeFormats.text (media_node, "FilePath"));
                                string key = media_node->get_prop ("ObjectUID") ?? file_path;
                                var m = media_cache[key];
                                if (m == null) {
                                    m = InterchangeFormats.find_or_add (p, file_path, InterchangeFormats.text (media_node, "Title", Path.get_basename (file_path)), 0, origin);
                                    media_cache[key] = m;
                                }
                                var c = new Clip ();
                                c.media = m.id;
                                c.track = t.id;
                                c.position = start;
                                c.duration = end - start;
                                c.in_point = ticks (InterchangeFormats.text (clip_inner, "InPoint", "0"));
                                double speed = double.parse (InterchangeFormats.text (clip_inner, "PlaybackSpeed", "1"));
                                if (speed != 0 && speed != 1) {
                                    c.reverse = speed < 0;
                                    c.params.ensure ("speed", 100).value = speed.abs () * 100;
                                }
                                string name = sub != null ? InterchangeFormats.text (sub, "Name") : "";
                                if (name != "" && name != m.name) c.name = name;
                                s.clips.add (c);
                            }
                        }
                    }
                    InterchangeFormats.tidy (s);
                    InterchangeFormats.link_pairs (s);
                }
            } finally {
                delete doc;
            }
            if (p.sequences.size == 0) throw new IOError.INVALID_DATA (_("The Premiere project has no sequences Montage can read."));
            p.active = p.sequences[0].id;
            if (skipped > 0) p.notes = ngettext ("%d item of the Premiere project was skipped (effects, graphics or nested items are not read).", "%d items of the Premiere project were skipped (effects, graphics or nested items are not read).", skipped).printf (skipped);
            return p;
        }
    }
}
