namespace Singularity.Apps.Montage {
    namespace InterchangeFormats {
        public Project read (string name, uint8[] data, File file) throws Error {
            string text = (string) data;
            if (name.has_suffix (".edl")) return Edl.read (text, file);
            if (name.has_suffix (".fcpxml")) return FcpXml.read (text, file);
            if (name.has_suffix (".fcpxmld")) throw new IOError.NOT_SUPPORTED (_("Open the Info.fcpxml file inside the bundle."));
            if (name.has_suffix (".prproj")) return Premiere.read (data, file);
            if (name.has_suffix (".aaf")) return Aaf.read (data, file);
            if (name.has_suffix (".kdenlive") || name.has_suffix (".mlt")) return Mlt.read (text, file);
            if (name.has_suffix (".xml")) {
                if (text.contains ("<fcpxml")) return FcpXml.read (text, file);
                if (text.contains ("<mlt")) return Mlt.read (text, file);
                return Fcp7.read (text, file);
            }
            throw new IOError.NOT_SUPPORTED (_("This timeline format is not supported."));
        }

        public MediaItem find_or_add (Project p, string location, string name, int64 fallback_duration, File? origin) {
            string uri = location;
            if (location == "" && name != "") {
                foreach (var m in p.media) if (m.name == name) return m;
                if (origin != null) {
                    var sibling = origin.get_parent ().get_child (name);
                    if (sibling.query_exists ()) uri = sibling.get_uri ();
                }
            }
            if (uri != "" && Uri.parse_scheme (uri) == null) {
                var base_dir = origin != null ? origin.get_parent () : null;
                uri = Path.is_absolute (uri) || base_dir == null ? File.new_for_path (uri).get_uri () : base_dir.resolve_relative_path (uri).get_uri ();
            }
            if (uri == "") uri = "file:///missing/" + Uri.escape_string (name != "" ? name : "media");
            var existing = p.media_by_uri (uri);
            if (existing != null) return existing;
            MediaItem m;
            try {
                m = Probe.probe (uri);
            } catch (Error e) {
                m = new MediaItem ();
                m.uri = uri;
                m.name = name != "" ? name : (File.new_for_uri (uri).get_basename () ?? "media");
                m.duration = fallback_duration > 0 ? fallback_duration : 3600L * Tc.SECOND;
                m.has_video = true;
                m.has_audio = true;
                m.width = 1920;
                m.height = 1080;
            }
            if (name != "" && m.name != name) m.metadata["source name"] = name;
            p.media.add (m);
            return m;
        }

        public Project empty_project (string name) {
            var p = new Project ();
            p.sequences.clear ();
            var s = new Sequence (name);
            p.sequences.add (s);
            p.active = s.id;
            return p;
        }

        public Track ensure_track (Sequence s, TrackKind kind, int index) {
            var list = s.tracks_of (kind);
            while (list.size <= index) {
                var t = new Track ("%s%d".printf (kind == TrackKind.AUDIO ? "A" : "V", list.size + 1), kind);
                if (kind == TrackKind.AUDIO) s.tracks.add (t);
                else {
                    int at = 0;
                    for (int i = 0; i < s.tracks.size; i++) if (s.tracks[i].kind == TrackKind.VIDEO) at = i + 1;
                    s.tracks.insert (at, t);
                }
                list = s.tracks_of (kind);
            }
            return list[index];
        }

        public string? attr (Xml.Node* n, string name) {
            return n->get_prop (name);
        }

        public Xml.Node* child (Xml.Node* n, string name) {
            if (n == null) return null;
            for (Xml.Node* c = n->children; c != null; c = c->next) if (c->type == Xml.ElementType.ELEMENT_NODE && c->name == name) return c;
            return null;
        }

        public Gee.ArrayList<Xml.Node*> children (Xml.Node* n, string name) {
            var r = new Gee.ArrayList<Xml.Node*> ();
            if (n == null) return r;
            for (Xml.Node* c = n->children; c != null; c = c->next) if (c->type == Xml.ElementType.ELEMENT_NODE && (name == "*" || c->name == name)) r.add (c);
            return r;
        }

        public string text (Xml.Node* n, string name, string fallback = "") {
            var c = child (n, name);
            if (c == null) return fallback;
            return c->get_content ().strip ();
        }

        public Xml.Doc* parse_xml (string text) throws Error {
            Xml.Doc* doc = Xml.Parser.read_memory (text, text.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.NOBLANKS | Xml.ParserOption.NOENT);
            if (doc == null) throw new IOError.INVALID_DATA (_("The XML document could not be read."));
            return doc;
        }

        public string esc (string s) {
            return Markup.escape_text (s);
        }

        public void tidy (Sequence s) {
            if (s.tracks_of (TrackKind.VIDEO).size == 0) s.tracks.insert (0, new Track ("V1", TrackKind.VIDEO));
            if (s.tracks_of (TrackKind.AUDIO).size == 0) s.tracks.add (new Track ("A1", TrackKind.AUDIO));
        }

        public void link_pairs (Sequence s) {
            foreach (var v in s.clips) {
                var vt = s.track (v.track);
                if (vt == null || vt.kind != TrackKind.VIDEO || v.link != "" || v.media == "") continue;
                foreach (var a in s.clips) {
                    var at = s.track (a.track);
                    if (at == null || at.kind != TrackKind.AUDIO || a.link != "") continue;
                    if (a.media == v.media && a.position == v.position && a.duration == v.duration && a.in_point == v.in_point) {
                        string id = new_id ();
                        v.link = id;
                        a.link = id;
                        break;
                    }
                }
            }
        }
    }

    namespace Edl {
        public string write (Project p, Sequence s) {
            int fps = Tc.nominal (s.fps_n, s.fps_d);
            var sb = new StringBuilder ();
            sb.append ("TITLE: %s\n".printf (s.name.up ().substring (0, int.min (70, s.name.length))));
            sb.append ("FCM: NON-DROP FRAME\n\n");
            int n = 1;
            int64 base_tc = 3600L * Tc.SECOND;
            var tracks = new Gee.ArrayList<Track> ();
            foreach (var t in s.tracks) if (t.kind != TrackKind.SUBTITLE) tracks.add (t);
            int vindex = 0, aindex = 0;
            foreach (var t in tracks) {
                string track_code;
                if (t.kind == TrackKind.VIDEO) track_code = vindex++ == 0 ? "V" : "V%d".printf (vindex);
                else track_code = aindex++ == 0 ? "A" : "A%d".printf (aindex);
                Clip? prev = null;
                foreach (var c in s.on_track (t.id)) {
                    var m = p.find_media (c.media);
                    string clipname = p.clip_label (c);
                    string reel = reel_of (m, c);
                    var tr = prev != null ? s.transition_between (prev.id, c.id) : null;
                    int64 src_in = c.in_point, src_out = c.in_point + c.source_span ();
                    if (tr != null && (tr.kind == "dissolve" || tr.kind == "additive" || tr.kind == "constant-gain" || tr.kind == "wipe")) {
                        int64 start = tr.start_at (c.position);
                        int64 lead = c.position - start;
                        sb.append ("%03d  %-8s %-5s C        %s %s %s %s\n".printf (n, reel_of (p.find_media (prev.media), prev), track_code,
                            Tc.format (prev.in_point + prev.source_span () - lead, s.fps_n, s.fps_d), Tc.format (prev.in_point + prev.source_span () - lead, s.fps_n, s.fps_d),
                            Tc.format (base_tc + start, s.fps_n, s.fps_d), Tc.format (base_tc + start, s.fps_n, s.fps_d)));
                        string code = tr.kind == "wipe" ? "W001" : "D   ";
                        sb.append ("%03d  %-8s %-5s %s %03d %s %s %s %s\n".printf (n, reel, track_code, code, (int) Tc.to_frames (tr.duration, s.fps_n, s.fps_d),
                            Tc.format (src_in - lead, s.fps_n, s.fps_d), Tc.format (src_out, s.fps_n, s.fps_d),
                            Tc.format (base_tc + start, s.fps_n, s.fps_d), Tc.format (base_tc + c.end, s.fps_n, s.fps_d)));
                    } else {
                        int64 rec_end = c.end;
                    foreach (var o in s.on_track (t.id)) {
                        var nt = s.transition_between (c.id, o.id);
                        if (nt != null && (nt.kind == "dissolve" || nt.kind == "additive" || nt.kind == "constant-gain" || nt.kind == "wipe")) rec_end = int64.min (rec_end, nt.start_at (c.end));
                    }
                    sb.append ("%03d  %-8s %-5s C        %s %s %s %s\n".printf (n, reel, track_code,
                            Tc.format (src_in, s.fps_n, s.fps_d), Tc.format (src_in + (rec_end - c.position), s.fps_n, s.fps_d),
                            Tc.format (base_tc + c.position, s.fps_n, s.fps_d), Tc.format (base_tc + rec_end, s.fps_n, s.fps_d)));
                    }
                    if (c.speed_changed) {
                        double speed = c.params.get_value ("speed", c.in_point, 100) / 100.0 * (c.reverse ? -1 : 1);
                        sb.append ("M2   %-8s %06.1f %s\n".printf (reel, speed * fps, Tc.format (src_in, s.fps_n, s.fps_d)));
                    }
                    bool dissolve = tr != null && (tr.kind == "dissolve" || tr.kind == "additive" || tr.kind == "constant-gain" || tr.kind == "wipe");
                    if (dissolve) {
                        var pm = p.find_media (prev.media);
                        sb.append ("* FROM CLIP NAME: %s\n".printf (p.clip_label (prev)));
                        if (pm != null && pm.kind == "file") sb.append ("* FROM CLIP: %s\n".printf (pm.uri));
                        sb.append ("* TO CLIP NAME: %s\n".printf (clipname));
                        if (m != null && m.kind == "file") sb.append ("* TO CLIP: %s\n".printf (m.uri));
                    } else {
                        sb.append ("* FROM CLIP NAME: %s\n".printf (clipname));
                        if (m != null && m.kind == "file") sb.append ("* SOURCE FILE: %s\n".printf (File.new_for_uri (m.uri).get_path () ?? m.uri));
                    }
                    foreach (var e in c.effects) if (e.type == "color.lut" && e.params.text ("file") != "") sb.append ("* ASC_SAT 1.0\n* LUT: %s\n".printf (e.params.text ("file")));
                    sb.append ("\n");
                    n++;
                    prev = c;
                }
            }
            foreach (var mk in s.markers) {
                sb.append ("* LOC: %s %s %s\n".printf (Tc.format (base_tc + mk.time, s.fps_n, s.fps_d), mk.kind == "chapter" ? "YELLOW" : "RED", mk.name.replace ("\n", " ")));
            }
            return sb.str;
        }

        string reel_of (MediaItem? m, Clip c) {
            if (c.kind == ClipKind.COLOR || c.kind == ClipKind.TITLE) return "BL";
            if (m == null) return "AX";
            if (m.metadata.has_key ("reel")) return m.metadata["reel"].up ().substring (0, int.min (8, m.metadata["reel"].length));
            return "AX";
        }

        public Project read (string text, File? origin) throws Error {
            var p = InterchangeFormats.empty_project (_("EDL Timeline"));
            var s = p.sequence;
            s.fps_n = 25;
            int64 base_tc = -1;
            string? pending_name = null, pending_file = null;
            var events = new Gee.ArrayList<string> ();
            var lines = text.replace ("\r", "").split ("\n");
            foreach (var raw in lines) {
                string line = raw.strip ();
                if (line.has_prefix ("FCM:") && line.contains ("DROP") && !line.contains ("NON")) {
                    s.fps_n = 30000;
                    s.fps_d = 1001;
                }
                if (line.has_prefix ("TITLE:")) s.name = line.substring (6).strip ();
            }
            foreach (var raw in lines) {
                string line = raw.strip ();
                if (line == "" || line.has_prefix ("TITLE:") || line.has_prefix ("FCM:")) continue;
                events.add (line);
            }
            Clip? last = null;
            Clip? last_cut_of_dissolve = null;
            bool last_transition = false;
            bool to_section = false;
            var parts = new Gee.ArrayList<string> ();
            foreach (var line in events) {
                if (line.has_prefix ("*")) {
                    string body = line.substring (1).strip ();
                    if (body.has_prefix ("TO CLIP NAME:") || body.has_prefix ("TO CLIP:")) to_section = true;
                    if (last_transition && !to_section && (body.has_prefix ("FROM CLIP") || body.has_prefix ("SOURCE FILE"))) continue;
                    if (body.has_prefix ("TO CLIP NAME:")) body = "FROM CLIP NAME:" + body.substring (13);
                    else if (body.has_prefix ("TO CLIP:")) body = "FROM CLIP:" + body.substring (8);
                    if (body.has_prefix ("FROM CLIP NAME:")) {
                        pending_name = body.substring (15).strip ();
                        if (last != null && last.media != "") {
                            var m = p.find_media (last.media);
                            if (m != null && m.uri.has_prefix ("file:///missing/")) {
                                var better = InterchangeFormats.find_or_add (p, "", pending_name, m.duration, origin);
                                if (better != m) {
                                    foreach (var c in s.clips) if (c.media == m.id) c.media = better.id;
                                    p.media.remove (m);
                                }
                            }
                        }
                    } else if (body.has_prefix ("SOURCE FILE:") || body.has_prefix ("FROM CLIP:")) {
                        pending_file = body.substring (body.index_of (":") + 1).strip ();
                        if (last != null) {
                            var m = p.find_media (last.media);
                            var better = InterchangeFormats.find_or_add (p, pending_file, pending_name ?? "", m != null ? m.duration : 0, origin);
                            if (m != null && better != m) {
                                foreach (var c in s.clips) if (c.media == m.id) c.media = better.id;
                                bool used = false;
                                foreach (var c in s.clips) if (c.media == m.id) used = true;
                                if (!used) p.media.remove (m);
                            }
                        }
                    } else if (body.has_prefix ("LOC:")) {
                        var loc = body.substring (4).strip ().split (" ", 3);
                        if (loc.length >= 1) {
                            int64 t = Tc.parse (loc[0], s.fps_n, s.fps_d);
                            var mk = new Marker (int64.max (0, t - int64.max (0, base_tc)), loc.length >= 3 ? loc[2] : "");
                            if (loc.length >= 2 && loc[1] == "YELLOW") mk.kind = "chapter";
                            s.markers.add (mk);
                        }
                    }
                    continue;
                }
                if (line.has_prefix ("M2")) {
                    var f = split (line);
                    if (f.size >= 3 && last != null) {
                        double speed = double.parse (f[2]) / Tc.nominal (s.fps_n, s.fps_d);
                        last.reverse = speed < 0;
                        last.params.ensure ("speed", 100).value = speed.abs () * 100;
                    }
                    continue;
                }
                parts = split (line);
                if (parts.size < 8 || int.parse (parts[0]) <= 0) continue;
                int k = 3;
                string kind = parts[k];
                int dur_frames = 0;
                if (kind == "D" || kind.has_prefix ("W") || kind == "K") {
                    dur_frames = int.parse (parts[k + 1]);
                    k += 2;
                } else {
                    k += 1;
                }
                if (parts.size < k + 4) continue;
                int64 src_in = Tc.parse (parts[k], s.fps_n, s.fps_d), src_out = Tc.parse (parts[k + 1], s.fps_n, s.fps_d);
                int64 rec_in = Tc.parse (parts[k + 2], s.fps_n, s.fps_d), rec_out = Tc.parse (parts[k + 3], s.fps_n, s.fps_d);
                if (base_tc < 0) base_tc = rec_in >= 3600L * Tc.SECOND ? 3600L * Tc.SECOND : 0;
                string track = parts[2];
                bool audio = track.has_prefix ("A") && !track.contains ("V");
                int index = 0;
                string digits = track.substring (1);
                if (digits.length > 0 && digits[0].isdigit ()) index = int.max (0, int.parse (digits) - 1);
                var t = InterchangeFormats.ensure_track (s, audio ? TrackKind.AUDIO : TrackKind.VIDEO, index);
                if (rec_out <= rec_in) {
                    last_cut_of_dissolve = null;
                    continue;
                }
                string reel = parts[1];
                var c = new Clip ();
                c.track = t.id;
                c.position = rec_in - base_tc;
                c.in_point = src_in;
                c.duration = rec_out - rec_in;
                if (reel == "BL" || reel == "BLACK") {
                    c.kind = ClipKind.COLOR;
                    c.color = "#000000ff";
                    c.in_point = 0;
                } else {
                    var m = InterchangeFormats.find_or_add (p, "", reel, src_out, origin);
                    m.metadata["reel"] = reel;
                    c.media = m.id;
                }
                if (dur_frames > 0) {
                    int64 d = Tc.from_frames (dur_frames, s.fps_n, s.fps_d);
                    Clip? previous = null;
                    foreach (var o in s.on_track (t.id)) if (o.end <= c.position + 1 && (previous == null || o.end > previous.end)) previous = o;
                    if (previous != null && previous.end > c.position) previous.duration = c.position - previous.position;
                    if (previous != null && previous.duration <= 0) {
                        s.clips.remove (previous);
                        previous = null;
                    }
                    if (previous != null) {
                        var tr = new Transition ();
                        tr.track = t.id;
                        tr.from_clip = previous.id;
                        tr.to_clip = c.id;
                        tr.duration = d;
                        tr.align = 1;
                        tr.kind = kind.has_prefix ("W") ? "wipe" : "dissolve";
                        s.transitions.add (tr);
                    }
                }
                s.clips.add (c);
                last = c;
                last_transition = dur_frames > 0;
                to_section = false;
                pending_name = null;
                pending_file = null;
            }
            InterchangeFormats.tidy (s);
            var empty = new Gee.ArrayList<Clip> ();
            foreach (var c in s.clips) if (c.duration <= 0) empty.add (c);
            foreach (var c in empty) s.clips.remove (c);
            InterchangeFormats.link_pairs (s);
            return p;
        }

        Gee.ArrayList<string> split (string line) {
            var r = new Gee.ArrayList<string> ();
            foreach (var part in line.split_set (" \t")) if (part != "") r.add (part);
            return r;
        }
    }

    namespace Fcp7 {
        public string write (Project p, Sequence s) {
            int timebase = Tc.nominal (s.fps_n, s.fps_d);
            bool ntsc = s.fps_d == 1001;
            var sb = new StringBuilder ();
            sb.append ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE xmeml>\n<xmeml version=\"5\">\n");
            sb.append ("<sequence id=\"%s\">\n<name>%s</name>\n<duration>%lld</duration>\n".printf (s.id, InterchangeFormats.esc (s.name), Tc.to_frames (s.duration, s.fps_n, s.fps_d)));
            string rate = "<rate><timebase>%d</timebase><ntsc>%s</ntsc></rate>".printf (timebase, ntsc ? "TRUE" : "FALSE");
            sb.append (rate + "\n<media>\n<video>\n<format><samplecharacteristics>%s<width>%d</width><height>%d</height></samplecharacteristics></format>\n".printf (rate, s.width, s.height));
            var written_files = new Gee.HashSet<string> ();
            foreach (var t in s.tracks_of (TrackKind.VIDEO)) write_track (sb, p, s, t, rate, written_files);
            sb.append ("</video>\n<audio>\n");
            foreach (var t in s.tracks_of (TrackKind.AUDIO)) write_track (sb, p, s, t, rate, written_files);
            sb.append ("</audio>\n</media>\n");
            foreach (var m in s.markers) {
                int64 f = Tc.to_frames (m.time, s.fps_n, s.fps_d);
                sb.append ("<marker><name>%s</name><comment>%s</comment><in>%lld</in><out>-1</out></marker>\n".printf (InterchangeFormats.esc (m.name), InterchangeFormats.esc (m.comment), f));
            }
            sb.append ("</sequence>\n</xmeml>\n");
            return sb.str;
        }

        void write_track (StringBuilder sb, Project p, Sequence s, Track t, string rate, Gee.HashSet<string> files) {
            sb.append ("<track>\n");
            if (t.locked) sb.append ("<locked>TRUE</locked>\n");
            sb.append ("<enabled>%s</enabled>\n".printf ((t.kind == TrackKind.AUDIO ? !t.muted : t.visible) ? "TRUE" : "FALSE"));
            Clip? prev = null;
            foreach (var c in s.on_track (t.id)) {
                var tr = prev != null ? s.transition_between (prev.id, c.id) : null;
                if (tr != null) {
                    int64 start = tr.start_at (c.position);
                    sb.append ("<transitionitem>%s<start>%lld</start><end>%lld</end><alignment>%s</alignment><effect><name>%s</name><effectid>%s</effectid><effectcategory>Dissolve</effectcategory><effecttype>transition</effecttype><mediatype>%s</mediatype></effect></transitionitem>\n"
                        .printf (rate, Tc.to_frames (start, s.fps_n, s.fps_d), Tc.to_frames (start + tr.duration, s.fps_n, s.fps_d),
                            tr.align == 0 ? "center" : (tr.align < 0 ? "end-black" : "start-black"),
                            tr.kind == "dissolve" ? "Cross Dissolve" : tr.kind, tr.kind == "dissolve" ? "Cross Dissolve" : tr.kind,
                            t.kind == TrackKind.AUDIO ? "audio" : "video"));
                }
                var m = p.find_media (c.media);
                int64 in_f = Tc.to_frames (c.in_point, s.fps_n, s.fps_d);
                sb.append ("<clipitem id=\"%s\">\n<name>%s</name>\n<enabled>%s</enabled>\n%s\n".printf (c.id, InterchangeFormats.esc (p.clip_label (c)), c.enabled ? "TRUE" : "FALSE", rate));
                sb.append ("<start>%lld</start><end>%lld</end><in>%lld</in><out>%lld</out>\n".printf (Tc.to_frames (c.position, s.fps_n, s.fps_d), Tc.to_frames (c.end, s.fps_n, s.fps_d),
                    in_f, in_f + Tc.to_frames (c.source_span (), s.fps_n, s.fps_d)));
                if (m != null && m.kind == "file") {
                    if (files.add (m.id)) {
                        sb.append ("<file id=\"file-%s\"><name>%s</name><pathurl>%s</pathurl>%s<duration>%lld</duration><media>%s%s</media></file>\n".printf (m.id, InterchangeFormats.esc (m.name),
                            InterchangeFormats.esc (m.uri), rate, Tc.to_frames (m.duration, s.fps_n, s.fps_d),
                            m.has_video ? "<video><samplecharacteristics><width>%d</width><height>%d</height></samplecharacteristics></video>".printf (m.width, m.height) : "",
                            m.has_audio ? "<audio><channelcount>%d</channelcount></audio>".printf (m.channels) : ""));
                    } else {
                        sb.append ("<file id=\"file-%s\"/>\n".printf (m.id));
                    }
                }
                if (c.speed_changed) {
                    double speed = c.params.get_value ("speed", c.in_point, 100) * (c.reverse ? -1 : 1);
                    sb.append ("<filter><effect><name>Time Remap</name><effectid>timeremap</effectid><parameter><parameterid>speed</parameterid><value>%g</value></parameter><parameter><parameterid>reverse</parameterid><value>%s</value></parameter></effect></filter>\n".printf (speed.abs (), c.reverse ? "TRUE" : "FALSE"));
                }
                if (c.link != "") {
                    foreach (var l in s.linked (c)) {
                        if (l == c) continue;
                        var lt = s.track (l.track);
                        sb.append ("<link><linkclipref>%s</linkclipref><mediatype>%s</mediatype></link>\n".printf (l.id, lt != null && lt.kind == TrackKind.AUDIO ? "audio" : "video"));
                    }
                }
                foreach (var mk in c.markers) sb.append ("<marker><name>%s</name><in>%lld</in><out>-1</out></marker>\n".printf (InterchangeFormats.esc (mk.name), in_f + Tc.to_frames (mk.time, s.fps_n, s.fps_d)));
                sb.append ("</clipitem>\n");
                prev = c;
            }
            sb.append ("</track>\n");
        }

        void read_rate (Xml.Node* n, Sequence s) {
            var r = InterchangeFormats.child (n, "rate");
            if (r == null) return;
            int tb = int.parse (InterchangeFormats.text (r, "timebase", "25"));
            bool ntsc = InterchangeFormats.text (r, "ntsc", "FALSE").up () == "TRUE";
            if (tb <= 0) return;
            s.fps_n = ntsc ? tb * 1000 : tb;
            s.fps_d = ntsc ? 1001 : 1;
        }

        public Project read (string text, File? origin) throws Error {
            var doc = InterchangeFormats.parse_xml (text);
            var p = InterchangeFormats.empty_project (_("Imported Sequence"));
            p.sequences.clear ();
            try {
                var root = doc->get_root_element ();
                if (root == null || root->name != "xmeml") throw new IOError.INVALID_DATA (_("This is not a Final Cut Pro XML file."));
                var seqs = new Gee.ArrayList<Xml.Node*> ();
                collect (root, "sequence", seqs);
                var files = new Gee.HashMap<string, MediaItem> ();
                foreach (var sn in seqs) {
                    var s = new Sequence (InterchangeFormats.text (sn, "name", _("Sequence")));
                    read_rate (sn, s);
                    p.sequences.add (s);
                    var media = InterchangeFormats.child (sn, "media");
                    var video = InterchangeFormats.child (media, "video");
                    var fmt = InterchangeFormats.child (InterchangeFormats.child (video, "format"), "samplecharacteristics");
                    if (fmt != null) {
                        s.width = int.parse (InterchangeFormats.text (fmt, "width", "1920"));
                        s.height = int.parse (InterchangeFormats.text (fmt, "height", "1080"));
                    }
                    var link_map = new Gee.HashMap<string, Clip> ();
                    var links = new Gee.HashMap<string, Gee.ArrayList<string>> ();
                    int vi = 0;
                    foreach (var tn in InterchangeFormats.children (video, "track")) read_track (p, s, tn, TrackKind.VIDEO, vi++, files, origin, link_map, links);
                    int ai = 0;
                    foreach (var tn in InterchangeFormats.children (InterchangeFormats.child (media, "audio"), "track")) read_track (p, s, tn, TrackKind.AUDIO, ai++, files, origin, link_map, links);
                    foreach (var e in links.entries) {
                        var c = link_map[e.key];
                        if (c == null) continue;
                        foreach (var other in e.value) {
                            var o = link_map[other];
                            if (o == null) continue;
                            if (c.link == "") c.link = o.link != "" ? o.link : new_id ();
                            o.link = c.link;
                        }
                    }
                    foreach (var mn in InterchangeFormats.children (sn, "marker")) {
                        var mk = new Marker (Tc.from_frames (int64.parse (InterchangeFormats.text (mn, "in", "0")), s.fps_n, s.fps_d), InterchangeFormats.text (mn, "name"));
                        mk.comment = InterchangeFormats.text (mn, "comment");
                        s.markers.add (mk);
                    }
                    InterchangeFormats.tidy (s);
                }
            } finally {
                delete doc;
            }
            if (p.sequences.size == 0) throw new IOError.INVALID_DATA (_("The file has no sequence."));
            p.active = p.sequences[0].id;
            return p;
        }

        void collect (Xml.Node* n, string name, Gee.ArrayList<Xml.Node*> into) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == name) {
                    into.add (c);
                    continue;
                }
                collect (c, name, into);
            }
        }

        void read_track (Project p, Sequence s, Xml.Node* tn, TrackKind kind, int index, Gee.HashMap<string, MediaItem> files, File? origin,
                         Gee.HashMap<string, Clip> link_map, Gee.HashMap<string, Gee.ArrayList<string>> links) {
            var t = InterchangeFormats.ensure_track (s, kind, index);
            if (InterchangeFormats.text (tn, "enabled", "TRUE").up () == "FALSE") {
                if (kind == TrackKind.AUDIO) t.muted = true;
                else t.visible = false;
            }
            t.locked = InterchangeFormats.text (tn, "locked", "FALSE").up () == "TRUE";
            Clip? prev = null;
            Xml.Node* pending_transition = null;
            foreach (var item in InterchangeFormats.children (tn, "*")) {
                if (item->name == "transitionitem") {
                    pending_transition = item;
                    continue;
                }
                if (item->name != "clipitem") continue;
                string? ref_id = InterchangeFormats.attr (item, "id");
                if (item->children == null && ref_id != null && link_map.has_key (ref_id)) {
                    var original = link_map[ref_id];
                    var dup = original.copy ();
                    dup.id = new_id ();
                    dup.track = t.id;
                    dup.markers.clear ();
                    if (original.link == "") original.link = new_id ();
                    dup.link = original.link;
                    s.clips.add (dup);
                    prev = dup;
                    continue;
                }
                int64 start = int64.parse (InterchangeFormats.text (item, "start", "-1"));
                int64 end = int64.parse (InterchangeFormats.text (item, "end", "-1"));
                int64 in_f = int64.parse (InterchangeFormats.text (item, "in", "0"));
                int64 out_f = int64.parse (InterchangeFormats.text (item, "out", "0"));
                if (start < 0 && pending_transition != null) start = int64.parse (InterchangeFormats.text (pending_transition, "start", "0"));
                if (end < 0) end = start + (out_f - in_f);
                if (end <= start) continue;
                var c = new Clip ();
                c.track = t.id;
                c.position = Tc.from_frames (start, s.fps_n, s.fps_d);
                c.duration = Tc.from_frames (end, s.fps_n, s.fps_d) - c.position;
                c.in_point = Tc.from_frames (in_f, s.fps_n, s.fps_d);
                c.enabled = InterchangeFormats.text (item, "enabled", "TRUE").up () != "FALSE";
                var fn = InterchangeFormats.child (item, "file");
                if (fn != null) {
                    string id = InterchangeFormats.attr (fn, "id") ?? new_id ();
                    var m = files[id];
                    if (m == null) {
                        string path = InterchangeFormats.text (fn, "pathurl");
                        if (path.has_prefix ("file://localhost/")) path = "file:///" + path.substring (17);
                        int64 dur = Tc.from_frames (int64.parse (InterchangeFormats.text (fn, "duration", "0")), s.fps_n, s.fps_d);
                        m = InterchangeFormats.find_or_add (p, path, InterchangeFormats.text (fn, "name"), dur, origin);
                        files[id] = m;
                    }
                    c.media = m.id;
                } else {
                    c.kind = ClipKind.COLOR;
                    c.name = InterchangeFormats.text (item, "name");
                }
                foreach (var filter in InterchangeFormats.children (item, "filter")) {
                    var effect = InterchangeFormats.child (filter, "effect");
                    if (InterchangeFormats.text (effect, "effectid") != "timeremap") continue;
                    foreach (var par in InterchangeFormats.children (effect, "parameter")) {
                        string pid = InterchangeFormats.text (par, "parameterid");
                        if (pid == "speed") c.params.ensure ("speed", 100).value = double.parse (InterchangeFormats.text (par, "value", "100")).abs ();
                        if (pid == "reverse") c.reverse = InterchangeFormats.text (par, "value").up () == "TRUE";
                    }
                }
                string? cid = InterchangeFormats.attr (item, "id");
                if (cid != null) {
                    link_map[cid] = c;
                    var refs = new Gee.ArrayList<string> ();
                    foreach (var ln in InterchangeFormats.children (item, "link")) {
                        string r = InterchangeFormats.text (ln, "linkclipref");
                        if (r != "" && r != cid) refs.add (r);
                    }
                    if (refs.size > 0) links[cid] = refs;
                }
                if (pending_transition != null && prev != null) {
                    int64 ts = Tc.from_frames (int64.parse (InterchangeFormats.text (pending_transition, "start", "0")), s.fps_n, s.fps_d);
                    int64 te = Tc.from_frames (int64.parse (InterchangeFormats.text (pending_transition, "end", "0")), s.fps_n, s.fps_d);
                    if (prev.end > c.position) prev.duration = c.position - prev.position;
                    var tr = new Transition ();
                    tr.track = t.id;
                    tr.from_clip = prev.id;
                    tr.to_clip = c.id;
                    tr.duration = te - ts;
                    string align = InterchangeFormats.text (pending_transition, "alignment", "center");
                    tr.align = align == "center" ? 0 : (align.has_prefix ("end") ? -1 : 1);
                    var eff = InterchangeFormats.child (pending_transition, "effect");
                    string name = InterchangeFormats.text (eff, "name").down ();
                    tr.kind = name.contains ("wipe") ? "wipe" : (name.contains ("dip") ? "dip" : "dissolve");
                    if (tr.duration > 0) s.transitions.add (tr);
                }
                pending_transition = null;
                s.clips.add (c);
                prev = c;
            }
        }
    }

    namespace FcpXml {
        string rt (int64 t, int fps_n, int fps_d) {
            int64 frames = Tc.to_frames (t, fps_n, fps_d);
            if (frames == 0) return "0s";
            return "%lld/%ds".printf (frames * fps_d, fps_n);
        }

        int64 parse_rt (string? v) {
            if (v == null || v == "") return 0;
            string s = v.strip ();
            if (s.has_suffix ("s")) s = s.substring (0, s.length - 1);
            if (s.contains ("/")) {
                var parts = s.split ("/");
                double num = double.parse (parts[0]), den = double.parse (parts[1]);
                if (den == 0) return 0;
                return (int64) Math.round (num / den * Tc.SECOND);
            }
            return (int64) Math.round (double.parse (s) * Tc.SECOND);
        }

        public string write (Project p, Sequence s) {
            var sb = new StringBuilder ();
            sb.append ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE fcpxml>\n<fcpxml version=\"1.10\">\n<resources>\n");
            sb.append ("<format id=\"r1\" name=\"FFVideoFormat%dp%d\" frameDuration=\"%d/%ds\" width=\"%d\" height=\"%d\"/>\n".printf (s.height, Tc.nominal (s.fps_n, s.fps_d), s.fps_d, s.fps_n, s.width, s.height));
            var ids = new Gee.HashMap<string, string> ();
            int n = 2;
            foreach (var c in s.clips) {
                var m = p.find_media (c.media);
                if (m == null || ids.has_key (m.id) || m.kind != "file") continue;
                string rid = "r%d".printf (n++);
                ids[m.id] = rid;
                sb.append ("<asset id=\"%s\" name=\"%s\" start=\"0s\" duration=\"%s\" hasVideo=\"%d\" hasAudio=\"%d\" format=\"r1\"%s>\n<media-rep kind=\"original-media\" src=\"%s\"/>\n</asset>\n"
                    .printf (rid, InterchangeFormats.esc (m.name), rt (m.duration, s.fps_n, s.fps_d), m.has_video ? 1 : 0, m.has_audio ? 1 : 0,
                        m.has_audio ? " audioSources=\"1\" audioChannels=\"%d\" audioRate=\"%d\"".printf (m.channels, m.sample_rate) : "", InterchangeFormats.esc (m.uri)));
            }
            sb.append ("<effect id=\"rdis\" name=\"Cross Dissolve\" uid=\"FxPlug:4731E73A-8DAC-4113-9A30-AE85B1761265\"/>\n");
            sb.append ("</resources>\n<library>\n<event name=\"Montage\">\n<project name=\"%s\">\n".printf (InterchangeFormats.esc (s.name)));
            sb.append ("<sequence format=\"r1\" duration=\"%s\" tcStart=\"0s\" tcFormat=\"NDF\">\n<spine>\n".printf (rt (s.duration, s.fps_n, s.fps_d)));
            var v = s.tracks_of (TrackKind.VIDEO);
            var a = s.tracks_of (TrackKind.AUDIO);
            var primary = v.size > 0 ? v[0] : null;
            int64 cursor = 0;
            var attached = new Gee.HashSet<string> ();
            linked_video = new Gee.HashSet<string> ();
            if (primary != null) {
                foreach (var c in s.on_track (primary.id)) {
                    foreach (var o in s.clips) {
                        var ot = s.track (o.track);
                        if (ot == null || ot.kind != TrackKind.AUDIO || attached.contains (o.id)) continue;
                        if (o.media == c.media && o.position == c.position && o.in_point == c.in_point && o.duration == c.duration) {
                            attached.add (o.id);
                            linked_video.add (c.id);
                            break;
                        }
                    }
                }
                Clip? prev = null;
                foreach (var c in s.on_track (primary.id)) {
                    if (c.position > cursor) {
                        sb.append ("<gap name=\"Gap\" offset=\"%s\" start=\"0s\" duration=\"%s\">\n".printf (rt (cursor, s.fps_n, s.fps_d), rt (c.position - cursor, s.fps_n, s.fps_d)));
                        sb.append (connected (p, s, ids, cursor, c.position, 0, attached));
                        sb.append ("</gap>\n");
                    }
                    var tr = prev != null ? s.transition_between (prev.id, c.id) : null;
                    if (tr != null && tr.align == 0) {
                        sb.append ("<transition name=\"Cross Dissolve\" offset=\"%s\" duration=\"%s\"><filter-video ref=\"rdis\" name=\"Cross Dissolve\"/></transition>\n"
                            .printf (rt (tr.start_at (c.position), s.fps_n, s.fps_d), rt (tr.duration, s.fps_n, s.fps_d)));
                    }
                    current_tag = media_tag (s, c);
                    sb.append (clip_xml (p, s, ids, c, 0, false));
                    current_tag = media_tag (s, c);
                    sb.append (connected (p, s, ids, c.position, c.end, c.position - c.in_point, attached, c));
                    current_tag = media_tag (s, c);
                    sb.append (close_tag (c));
                    cursor = c.end;
                    prev = c;
                }
            }
            int64 end = s.duration;
            if (cursor < end) {
                sb.append ("<gap name=\"Gap\" offset=\"%s\" start=\"0s\" duration=\"%s\">\n".printf (rt (cursor, s.fps_n, s.fps_d), rt (end - cursor, s.fps_n, s.fps_d)));
                sb.append (connected (p, s, ids, cursor, end, 0, attached));
                sb.append ("</gap>\n");
            }
            sb.append ("</spine>\n</sequence>\n</project>\n</event>\n</library>\n</fcpxml>\n");
            return sb.str;
        }

        Gee.HashSet<string> linked_video;
        string? current_tag;

        string media_tag (Sequence s, Clip c) {
            var track = s.track (c.track);
            if (track != null && track.kind == TrackKind.AUDIO) return "clip";
            return linked_video != null && linked_video.contains (c.id) ? "asset-clip" : "clip";
        }

        string close_tag (Clip c) {
            if (c.kind == ClipKind.MEDIA) return "</%s>\n".printf (current_tag ?? "asset-clip");
            if (c.kind == ClipKind.TITLE) return "</title>\n";
            if (c.kind == ClipKind.TITLE) return "</title>\n";
            return "</gap>\n";
        }

        string clip_xml (Project p, Sequence s, Gee.HashMap<string, string> ids, Clip c, int lane, bool self_close) {
            var m = p.find_media (c.media);
            string lane_attr = lane != 0 ? " lane=\"%d\"".printf (lane) : "";
            string offset = rt (c.position, s.fps_n, s.fps_d);
            string dur = rt (c.duration, s.fps_n, s.fps_d);
            string start = rt (c.in_point, s.fps_n, s.fps_d);
            string markers = "";
            foreach (var mk in c.markers) markers += "<marker start=\"%s\" duration=\"%s\" value=\"%s\"/>\n".printf (rt (c.in_point + mk.time, s.fps_n, s.fps_d), rt (int64.max (s.frame, mk.duration), s.fps_n, s.fps_d), InterchangeFormats.esc (mk.name));
            string inner = markers;
            if (c.kind == ClipKind.MEDIA && m != null && ids.has_key (m.id)) {
                var track = s.track (c.track);
                string role = track != null && track.kind == TrackKind.AUDIO ? " audioRole=\"dialogue\"" : "";
                if (c.params.get_value ("volume", c.in_point, 0) != 0) inner += "<adjust-volume amount=\"%gdB\"/>\n".printf (c.params.get_value ("volume", c.in_point, 0));
                string tag = media_tag (s, c);
                string open;
                if (tag == "clip") {
                    string inner_tag = track != null && track.kind == TrackKind.AUDIO ? "audio" : "video";
                    open = "<clip%s offset=\"%s\" name=\"%s\" start=\"%s\" duration=\"%s\"%s>\n<%s ref=\"%s\" offset=\"%s\" duration=\"%s\"%s/>\n".printf (lane_attr, offset,
                        InterchangeFormats.esc (m.name), start, dur, c.enabled ? "" : " enabled=\"0\"", inner_tag, ids[m.id], start, dur, inner_tag == "audio" ? role : "");
                } else {
                    open = "<%s ref=\"%s\"%s offset=\"%s\" name=\"%s\" start=\"%s\" duration=\"%s\"%s%s>\n".printf (tag, ids[m.id], lane_attr, offset,
                        InterchangeFormats.esc (m.name), start, dur, role, c.enabled ? "" : " enabled=\"0\"");
                }
                return open + inner + (self_close ? "</%s>\n".printf (tag) : "");
            }
            if (c.kind == ClipKind.TITLE) {
                string txt = c.title != null && c.title.layers.size > 0 ? Titles.expand (c.title.layers[0].text, c.title) : "";
                string open = "<title%s offset=\"%s\" name=\"%s\" start=\"0s\" duration=\"%s\">\n<text><text-style>%s</text-style></text>\n".printf (lane_attr, offset, InterchangeFormats.esc (txt), dur, InterchangeFormats.esc (txt));
                return open + inner + (self_close ? "</title>\n" : "");
            }
            return "<gap%s offset=\"%s\" name=\"%s\" start=\"0s\" duration=\"%s\">\n".printf (lane_attr, offset, InterchangeFormats.esc (p.clip_label (c)), dur) + inner + (self_close ? "</gap>\n" : "");
        }

        string connected (Project p, Sequence s, Gee.HashMap<string, string> ids, int64 start, int64 end, int64 local_offset, Gee.HashSet<string> attached, Clip? parent = null) {
            var sb = new StringBuilder ();
            var v = s.tracks_of (TrackKind.VIDEO);
            var a = s.tracks_of (TrackKind.AUDIO);
            for (int i = 1; i < v.size; i++) foreach (var c in s.on_track (v[i].id)) {
                if (c.position < start || c.position >= end || !attached.add (c.id)) continue;
                var shifted = c.copy ();
                shifted.position = c.position - start + (parent != null ? parent.in_point : 0);
                sb.append (clip_xml (p, s, ids, shifted, i, true));
            }
            for (int i = 0; i < a.size; i++) foreach (var c in s.on_track (a[i].id)) {
                if (c.position < start || c.position >= end || !attached.add (c.id)) continue;
                if (parent != null && c.link != "" && c.link == parent.link) continue;
                var shifted = c.copy ();
                shifted.position = c.position - start + (parent != null ? parent.in_point : 0);
                sb.append (clip_xml (p, s, ids, shifted, -(i + 1), true));
            }
            return sb.str;
        }

        public Project read (string text, File? origin) throws Error {
            var doc = InterchangeFormats.parse_xml (text);
            var p = InterchangeFormats.empty_project (_("Imported Project"));
            p.sequences.clear ();
            try {
                var root = doc->get_root_element ();
                if (root == null || root->name != "fcpxml") throw new IOError.INVALID_DATA (_("This is not an FCPXML file."));
                var resources = InterchangeFormats.child (root, "resources");
                var assets = new Gee.HashMap<string, MediaItem> ();
                var formats = new Gee.HashMap<string, Xml.Node*> ();
                foreach (var r in InterchangeFormats.children (resources, "*")) {
                    string id = InterchangeFormats.attr (r, "id") ?? "";
                    if (r->name == "format") formats[id] = r;
                    if (r->name == "asset") {
                        string src = InterchangeFormats.attr (r, "src") ?? "";
                        var rep = InterchangeFormats.child (r, "media-rep");
                        if (rep != null) src = InterchangeFormats.attr (rep, "src") ?? src;
                        var am = InterchangeFormats.find_or_add (p, src, InterchangeFormats.attr (r, "name") ?? "", parse_rt (InterchangeFormats.attr (r, "duration")), origin);
                        if (am.uri.has_prefix ("file:///missing/") || !File.new_for_uri (am.uri).query_exists ()) {
                            am.has_video = (InterchangeFormats.attr (r, "hasVideo") ?? "1") != "0";
                            am.has_audio = (InterchangeFormats.attr (r, "hasAudio") ?? "0") != "0";
                        }
                        assets[id] = am;
                    }
                }
                var seqs = new Gee.ArrayList<Xml.Node*> ();
                find (root, "sequence", seqs);
                foreach (var sn in seqs) {
                    var project_node = sn->parent;
                    var s = new Sequence (project_node != null && project_node->name == "project" ? (InterchangeFormats.attr (project_node, "name") ?? _("Project")) : _("Sequence"));
                    var fmt = formats[InterchangeFormats.attr (sn, "format") ?? ""];
                    if (fmt != null) {
                        s.width = int.parse (InterchangeFormats.attr (fmt, "width") ?? "1920");
                        s.height = int.parse (InterchangeFormats.attr (fmt, "height") ?? "1080");
                        string fd = InterchangeFormats.attr (fmt, "frameDuration") ?? "1/25s";
                        fd = fd.replace ("s", "");
                        var parts = fd.split ("/");
                        if (parts.length == 2) {
                            s.fps_n = int.parse (parts[1]);
                            s.fps_d = int.parse (parts[0]);
                        }
                    }
                    p.sequences.add (s);
                    s.tracks.add (new Track ("V1", TrackKind.VIDEO));
                    s.tracks.add (new Track ("A1", TrackKind.AUDIO));
                    var spine = InterchangeFormats.child (sn, "spine");
                    read_items (p, s, spine, assets, 0, 0, 0);
                    InterchangeFormats.link_pairs (s);
                    InterchangeFormats.tidy (s);
                }
            } finally {
                delete doc;
            }
            if (p.sequences.size == 0) throw new IOError.INVALID_DATA (_("The FCPXML file has no project."));
            p.active = p.sequences[0].id;
            return p;
        }

        void find (Xml.Node* n, string name, Gee.ArrayList<Xml.Node*> into) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == name) into.add (c);
                else find (c, name, into);
            }
        }

        Xml.Node* first_ref (Xml.Node* n) {
            foreach (var c in InterchangeFormats.children (n, "*")) {
                if ((c->name == "video" || c->name == "audio" || c->name == "asset-clip") && InterchangeFormats.attr (c, "ref") != null) return c;
                if (c->name == "gap" || c->name == "clip") {
                    var r = first_ref (c);
                    if (r != null) return r;
                }
            }
            return null;
        }

        void read_items (Project p, Sequence s, Xml.Node* container, Gee.HashMap<string, MediaItem> assets, int64 parent_offset, int64 parent_start, int parent_lane, bool inside_clip = false) {
            Clip? prev = null;
            Xml.Node* transition = null;
            foreach (var n in InterchangeFormats.children (container, "*")) {
                string name = n->name;
                if (name == "transition") {
                    transition = n;
                    continue;
                }
                if (name != "asset-clip" && name != "clip" && name != "gap" && name != "title" && name != "video" && name != "audio" && name != "ref-clip") continue;
                if ((name == "video" || name == "audio") && InterchangeFormats.attr (n, "lane") == null && container->name != "spine") continue;
                if (inside_clip && (name == "gap" || InterchangeFormats.attr (n, "lane") == null)) continue;
                int lane = int.parse (InterchangeFormats.attr (n, "lane") ?? "0");
                if (parent_lane != 0 && lane == 0) lane = parent_lane;
                int64 offset = parse_rt (InterchangeFormats.attr (n, "offset"));
                int64 start = parse_rt (InterchangeFormats.attr (n, "start"));
                int64 duration = parse_rt (InterchangeFormats.attr (n, "duration"));
                int64 position = parent_offset + (offset - parent_start);
                if (name == "gap") {
                    read_items (p, s, n, assets, position, start, 0);
                    prev = null;
                    continue;
                }
                Clip? c = null;
                bool audio_only = false;
                if (name == "title") {
                    c = new Clip ();
                    c.kind = ClipKind.TITLE;
                    c.title = Titles.builtin ()[0].data.copy ();
                    c.title.fields["title"] = InterchangeFormats.attr (n, "name") ?? "";
                } else {
                    string rid = InterchangeFormats.attr (n, "ref") ?? "";
                    var m = assets[rid];
                    Xml.Node* inner = null;
                    if (m == null && name == "clip") {
                        inner = first_ref (n);
                        if (inner != null) m = assets[InterchangeFormats.attr (inner, "ref") ?? ""];
                    }
                    if (m == null) continue;
                    c = new Clip ();
                    c.media = m.id;
                    audio_only = lane < 0 || name == "audio" || (inner != null && inner->name == "audio") || (!m.has_video && m.has_audio);
                    string? vol = null;
                    var adj = InterchangeFormats.child (n, "adjust-volume");
                    if (adj != null) vol = InterchangeFormats.attr (adj, "amount");
                    if (vol != null) c.params.ensure ("volume", 0).value = double.parse (vol.replace ("dB", ""));
                }
                c.position = int64.max (0, position);
                c.in_point = start;
                c.duration = duration;
                c.enabled = (InterchangeFormats.attr (n, "enabled") ?? "1") != "0";
                if (c.duration <= 0) continue;
                Track t;
                if (audio_only) t = InterchangeFormats.ensure_track (s, TrackKind.AUDIO, lane < 0 ? -lane - 1 : 0);
                else t = InterchangeFormats.ensure_track (s, TrackKind.VIDEO, lane > 0 ? lane : 0);
                c.track = t.id;
                foreach (var mk in InterchangeFormats.children (n, "marker")) {
                    var marker = new Marker (parse_rt (InterchangeFormats.attr (mk, "start")) - start, InterchangeFormats.attr (mk, "value") ?? "");
                    c.markers.add (marker);
                }
                s.clips.add (c);
                if (!audio_only && lane == 0 && c.media != "" && name == "asset-clip") {
                    var m = p.find_media (c.media);
                    if (m != null && m.has_audio) {
                        var a = c.copy ();
                        a.id = new_id ();
                        a.markers.clear ();
                        a.track = InterchangeFormats.ensure_track (s, TrackKind.AUDIO, 0).id;
                        string link = new_id ();
                        c.link = link;
                        a.link = link;
                        s.clips.add (a);
                    }
                }
                if (transition != null && prev != null && lane == 0) {
                    var tr = new Transition ();
                    tr.track = t.id;
                    tr.from_clip = prev.id;
                    tr.to_clip = c.id;
                    tr.duration = parse_rt (InterchangeFormats.attr (transition, "duration"));
                    tr.align = 0;
                    s.transitions.add (tr);
                }
                transition = null;
                read_items (p, s, n, assets, c.position, start, lane, true);
                if (lane == 0) prev = c;
            }
        }
    }

    namespace Mlt {
        int64 time_of (string v, double fps) {
            if (v.contains (":")) {
                var parts = v.split (":");
                double sec = 0;
                foreach (var part in parts) sec = sec * 60 + double.parse (part.replace (",", "."));
                return (int64) Math.round (sec * Tc.SECOND);
            }
            return (int64) Math.round (double.parse (v) / fps * Tc.SECOND);
        }

        public Project read (string text, File? origin) throws Error {
            var doc = InterchangeFormats.parse_xml (text);
            var p = InterchangeFormats.empty_project (_("Imported Kdenlive or Shotcut Project"));
            var s = p.sequence;
            try {
                var root = doc->get_root_element ();
                if (root == null || root->name != "mlt") throw new IOError.INVALID_DATA (_("This is not an MLT project."));
                double fps = 25;
                var profile = InterchangeFormats.child (root, "profile");
                if (profile != null) {
                    int fn = int.parse (InterchangeFormats.attr (profile, "frame_rate_num") ?? "25");
                    int fd = int.parse (InterchangeFormats.attr (profile, "frame_rate_den") ?? "1");
                    if (fn > 0 && fd > 0) {
                        s.fps_n = fn;
                        s.fps_d = fd;
                        fps = (double) fn / fd;
                    }
                    s.width = int.parse (InterchangeFormats.attr (profile, "width") ?? "1920");
                    s.height = int.parse (InterchangeFormats.attr (profile, "height") ?? "1080");
                }
                var producers = new Gee.HashMap<string, MediaItem> ();
                var playlists = new Gee.HashMap<string, Xml.Node*> ();
                var colors = new Gee.HashMap<string, string> ();
                foreach (var n in InterchangeFormats.children (root, "*")) {
                    string id = InterchangeFormats.attr (n, "id") ?? "";
                    if (n->name == "producer" || n->name == "chain") {
                        string resource = "", service = "";
                        int64 length = 0;
                        foreach (var prop in InterchangeFormats.children (n, "property")) {
                            string key = InterchangeFormats.attr (prop, "name") ?? "";
                            if (key == "resource") resource = prop->get_content ();
                            if (key == "mlt_service") service = prop->get_content ();
                            if (key == "length") length = time_of (prop->get_content (), fps);
                        }
                        if (service == "color" || service == "colour") {
                            colors[id] = resource;
                            continue;
                        }
                        if (resource == "" || service == "tractor") continue;
                        producers[id] = InterchangeFormats.find_or_add (p, resource, Path.get_basename (resource), length, origin);
                    }
                    if (n->name == "playlist") playlists[id] = n;
                }
                Xml.Node* tractor = null;
                var tractors = new Gee.HashMap<string, Xml.Node*> ();
                foreach (var n in InterchangeFormats.children (root, "tractor")) {
                    tractor = n;
                    string? tid = InterchangeFormats.attr (n, "id");
                    if (tid != null) tractors[tid] = n;
                }
                var track_nodes = new Gee.ArrayList<Xml.Node*> ();
                var audio_hint = new Gee.HashSet<string> ();
                if (tractor != null) {
                    var mt = InterchangeFormats.child (tractor, "multitrack");
                    foreach (var tn in InterchangeFormats.children (mt != null ? mt : tractor, "track")) {
                        string pid = InterchangeFormats.attr (tn, "producer") ?? "";
                        var inner = tractors[pid];
                        if (inner == null) {
                            track_nodes.add (tn);
                            continue;
                        }
                        bool is_audio = false;
                        foreach (var prop in InterchangeFormats.children (inner, "property")) if ((InterchangeFormats.attr (prop, "name") ?? "") == "kdenlive:audio_track" && prop->get_content () == "1") is_audio = true;
                        var first = InterchangeFormats.children (inner, "track");
                        if (first.size == 0) continue;
                        track_nodes.add (first[0]);
                        if (is_audio) audio_hint.add (InterchangeFormats.attr (first[0], "producer") ?? "");
                    }
                }
                s.tracks.clear ();
                int vi = 0, ai = 0;
                foreach (var tn in track_nodes) {
                    string pid = InterchangeFormats.attr (tn, "producer") ?? "";
                    var pl = playlists[pid];
                    if (pl == null || pid == "main_bin" || pid == "background") continue;
                    bool audio = (InterchangeFormats.attr (tn, "hide") ?? "") == "video" || audio_hint.contains (pid);
                    foreach (var prop in InterchangeFormats.children (pl, "property")) {
                        if ((InterchangeFormats.attr (prop, "name") ?? "") == "kdenlive:audio_track" && prop->get_content () == "1") audio = true;
                    }
                    var t = new Track (audio ? "A%d".printf (++ai) : "V%d".printf (++vi), audio ? TrackKind.AUDIO : TrackKind.VIDEO);
                    s.tracks.add (t);
                    int64 cursor = 0;
                    foreach (var e in InterchangeFormats.children (pl, "*")) {
                        if (e->name == "property") continue;
                        if (e->name == "blank") {
                            cursor += time_of (InterchangeFormats.attr (e, "length") ?? "0", fps);
                            continue;
                        }
                        if (e->name != "entry") continue;
                        string prod = InterchangeFormats.attr (e, "producer") ?? "";
                        int64 in_t = time_of (InterchangeFormats.attr (e, "in") ?? "0", fps);
                        int64 out_t = time_of (InterchangeFormats.attr (e, "out") ?? "0", fps) + (int64) (Tc.SECOND / fps);
                        var c = new Clip ();
                        c.track = t.id;
                        c.position = cursor;
                        c.in_point = in_t;
                        c.duration = out_t - in_t;
                        if (producers.has_key (prod)) c.media = producers[prod].id;
                        else if (colors.has_key (prod)) {
                            c.kind = ClipKind.COLOR;
                            string col = colors[prod];
                            c.color = col.has_prefix ("0x") ? "#" + col.substring (2) : col;
                            c.in_point = 0;
                        } else {
                            cursor += c.duration;
                            continue;
                        }
                        if (c.duration > 0) s.clips.add (c);
                        cursor += c.duration;
                    }
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
                InterchangeFormats.tidy (s);
                InterchangeFormats.link_pairs (s);
            } finally {
                delete doc;
            }
            return p;
        }
    }

    namespace Importers {
        public Project read (File file) throws Error {
            string name = (file.get_basename () ?? "").down ();
            uint8[] data;
            if (name.has_suffix (".otioz")) {
                var dir = File.new_for_path (Path.build_filename (Environment.get_user_data_dir (), "singularity-montage", "bundles", new_id ()));
                return Otio.read_bundle (file, dir);
            }
            file.load_contents (null, out data, null);
            string text = (string) data;
            if (name.has_suffix (".otio")) return Otio.read (text, file);
            return InterchangeFormats.read (name, data, file);
        }
    }
}
