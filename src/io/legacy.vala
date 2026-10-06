namespace Singularity.Apps.Montage {
    namespace LegacyFormat {
        public bool detect (Json.Object o) {
            return !o.has_member ("format") && o.has_member ("clips") && (Js.integer (o, "version", 0) == 2 || !o.has_member ("version"));
        }

        public Project read (Json.Object o) throws Error {
            var p = new Project ();
            p.sequences.clear ();
            var s = new Sequence (_("Sequence 1"));
            p.sequences.add (s);
            p.active = s.id;
            var tracks = Js.objects (o, "tracks");
            if (tracks.size == 0) s.tracks.add (new Track ("V1", TrackKind.VIDEO));
            foreach (var to in tracks) {
                var t = new Track (Js.str (to, "name", "Track"), Js.str (to, "kind", "video") == "audio" ? TrackKind.AUDIO : TrackKind.VIDEO);
                t.id = Js.str (to, "id", new_id ());
                t.locked = Js.flag (to, "locked");
                t.muted = Js.flag (to, "muted");
                t.visible = Js.flag (to, "visible", true);
                s.tracks.add (t);
            }
            if (tracks.size == 0) foreach (var t in s.tracks) t.id = "video-1";
            int64 cursor = 0;
            foreach (var co in Js.objects (o, "clips")) {
                string uri = Js.str (co, "uri");
                var m = p.media_by_uri (uri);
                if (m == null) {
                    try {
                        m = Probe.probe (uri);
                    } catch (Error e) {
                        m = new MediaItem ();
                        m.uri = uri;
                        m.name = File.new_for_uri (uri).get_basename () ?? uri;
                        m.duration = Js.integer (co, "end");
                        m.has_video = true;
                        m.has_audio = true;
                    }
                    p.media.add (m);
                }
                var c = new Clip ();
                c.id = Js.str (co, "id", new_id ());
                c.media = m.id;
                c.track = Js.str (co, "track", "video-1");
                c.in_point = Js.integer (co, "start");
                c.duration = Js.integer (co, "end") - c.in_point;
                c.position = co.has_member ("position") ? Js.integer (co, "position") : cursor;
                cursor = c.position + c.duration;
                if (c.duration <= 0 || s.track (c.track) == null) continue;
                s.clips.add (c);
            }
            var v = new Gee.ArrayList<Track> ();
            var a = new Gee.ArrayList<Track> ();
            foreach (var t in s.tracks) {
                if (t.kind == TrackKind.AUDIO) a.add (t);
                else v.add (t);
            }
            s.tracks.clear ();
            s.tracks.add_all (v);
            s.tracks.add_all (a);
            if (a.size == 0) s.tracks.add (new Track ("A1", TrackKind.AUDIO));
            return p;
        }

        public string write (Project p, Sequence s) {
            var b = new Json.Builder ();
            b.begin_object ();
            Js.i (b, "version", 2);
            b.set_member_name ("tracks");
            b.begin_array ();
            foreach (var t in s.tracks) {
                if (t.kind == TrackKind.SUBTITLE) continue;
                b.begin_object ();
                Js.s (b, "id", t.id);
                Js.s (b, "name", t.name);
                Js.s (b, "kind", t.kind == TrackKind.AUDIO ? "audio" : "video");
                Js.f (b, "locked", t.locked);
                Js.f (b, "muted", t.muted);
                Js.f (b, "visible", t.visible);
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("clips");
            b.begin_array ();
            foreach (var c in s.clips) {
                var m = p.find_media (c.media);
                if (c.kind != ClipKind.MEDIA || m == null || !c.enabled) continue;
                var t = s.track (c.track);
                if (t == null || t.kind == TrackKind.SUBTITLE) continue;
                b.begin_object ();
                Js.s (b, "id", c.id);
                Js.s (b, "uri", m.uri);
                Js.s (b, "track", c.track);
                Js.i (b, "position", c.position);
                Js.i (b, "start", c.in_point);
                Js.i (b, "end", c.in_point + c.source_span ());
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();
            return Js.write (b.get_root (), true);
        }
    }
}
