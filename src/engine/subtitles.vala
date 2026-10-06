using Singularity.Imaging;

namespace Singularity.Apps.Montage {
    public class Cue : Object {
        public int64 start;
        public int64 end;
        public string text;

        public Cue (int64 start, int64 end, string text) {
            this.start = start;
            this.end = end;
            this.text = text;
        }
    }

    namespace Subtitles {
        public TitleData style_of (Clip c) {
            var data = new TitleData ();
            var l = new TitleLayer ();
            l.text = c.text;
            l.font = c.params.text ("font", "Sans Bold");
            l.size = double.parse (c.params.text ("size", "48"));
            l.color = c.params.text ("color", "#ffffffff");
            l.outline = double.parse (c.params.text ("outline", "2"));
            l.box = c.params.text ("box", "false") == "true";
            l.box_color = c.params.text ("box-color", "#000000b0");
            l.box_padding = 10;
            l.width = 86;
            string pos = c.params.text ("position", "bottom");
            l.y = pos == "top" ? 10 : (pos == "middle" ? 50 : 88);
            data.layers.add (l);
            return data;
        }

        public FloatImage render (Clip c, int w, int h, double scale) {
            return Titles.render (style_of (c), w, h, scale, c.duration / 2, c.duration);
        }

        int64 parse_time (string text) throws Error {
            string t = text.strip ().replace (",", ".");
            var parts = t.split (":");
            double seconds;
            int64 hours = 0, minutes = 0;
            if (parts.length == 3) {
                hours = int64.parse (parts[0]);
                minutes = int64.parse (parts[1]);
                seconds = double.parse (parts[2]);
            } else if (parts.length == 2) {
                minutes = int64.parse (parts[0]);
                seconds = double.parse (parts[1]);
            } else {
                throw new IOError.INVALID_DATA (_("Invalid subtitle time: %s").printf (text));
            }
            return (hours * 3600 + minutes * 60) * Tc.SECOND + (int64) Math.round (seconds * Tc.SECOND);
        }

        public Gee.ArrayList<Cue> parse (string data) throws Error {
            var cues = new Gee.ArrayList<Cue> ();
            string text = data.replace ("\r\n", "\n").replace ("\r", "\n");
            if (text.has_prefix ("\xef\xbb\xbf")) text = text.substring (3);
            foreach (var block in text.split ("\n\n")) {
                var lines = new Gee.ArrayList<string> ();
                foreach (var l in block.split ("\n")) if (l.strip () != "" || lines.size > 0) lines.add (l);
                int i = 0;
                while (i < lines.size && !lines[i].contains ("-->")) i++;
                if (i >= lines.size) continue;
                var times = lines[i].split ("-->");
                if (times.length != 2) continue;
                int64 start = parse_time (times[0]);
                int64 end = parse_time (times[1].strip ().split (" ")[0]);
                var body = new StringBuilder ();
                for (int k = i + 1; k < lines.size; k++) {
                    if (lines[k].strip () == "") continue;
                    if (body.len > 0) body.append ("\n");
                    body.append (strip_tags (lines[k]));
                }
                if (end > start) cues.add (new Cue (start, end, body.str));
            }
            return cues;
        }

        string strip_tags (string s) {
            try {
                return new Regex ("<[^>]*>").replace (s, -1, 0, "");
            } catch (RegexError e) {
                return s;
            }
        }

        public string to_srt (Gee.List<Cue> cues) {
            var sb = new StringBuilder ();
            int n = 1;
            foreach (var c in cues) {
                sb.append ("%d\n%s --> %s\n%s\n\n".printf (n++, Tc.srt (c.start), Tc.srt (c.end), c.text));
            }
            return sb.str;
        }

        public string to_vtt (Gee.List<Cue> cues) {
            var sb = new StringBuilder ("WEBVTT\n\n");
            foreach (var c in cues) sb.append ("%s --> %s\n%s\n\n".printf (Tc.vtt (c.start), Tc.vtt (c.end), c.text));
            return sb.str;
        }

        public Gee.ArrayList<Cue> from_track (Sequence seq, string track_id) {
            var cues = new Gee.ArrayList<Cue> ();
            foreach (var c in seq.on_track (track_id)) if (c.kind == ClipKind.SUBTITLE) cues.add (new Cue (c.position, c.end, c.text));
            return cues;
        }

        public Gee.ArrayList<Cue> all (Sequence seq) {
            foreach (var t in seq.tracks) if (t.kind == TrackKind.SUBTITLE && t.visible) return from_track (seq, t.id);
            return new Gee.ArrayList<Cue> ();
        }

        public void add_cues (Project project, Gee.List<Cue> cues, string label) throws Error {
            var seq = project.sequence;
            var edits = new Edits (project);
            Track? track = null;
            foreach (var t in seq.tracks) if (t.kind == TrackKind.SUBTITLE) track = t;
            project.checkpoint (label);
            if (track == null) {
                track = new Track ("S1", TrackKind.SUBTITLE);
                seq.tracks.add (track);
            }
            foreach (var cue in cues) {
                edits.clear_range (track.id, cue.start, cue.end);
                var c = new Clip ();
                c.kind = ClipKind.SUBTITLE;
                c.track = track.id;
                c.position = cue.start;
                c.duration = cue.end - cue.start;
                c.text = cue.text;
                seq.clips.add (c);
            }
            project.commit ();
        }
    }
}
