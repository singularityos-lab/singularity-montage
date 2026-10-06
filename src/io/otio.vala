namespace Singularity.Apps.Montage {
    namespace Otio {
        void rational (Json.Builder b, string name, int64 t, double rate) {
            b.set_member_name (name);
            b.begin_object ();
            Js.s (b, "OTIO_SCHEMA", "RationalTime.1");
            Js.d (b, "rate", rate);
            Js.d (b, "value", Math.round ((double) t * rate / Tc.SECOND * 1000) / 1000);
            b.end_object ();
        }

        void range (Json.Builder b, string name, int64 start, int64 duration, double rate) {
            b.set_member_name (name);
            b.begin_object ();
            Js.s (b, "OTIO_SCHEMA", "TimeRange.1");
            rational (b, "start_time", start, rate);
            rational (b, "duration", duration, rate);
            b.end_object ();
        }

        string color_name (int c) {
            string[] names = { "PURPLE", "RED", "ORANGE", "YELLOW", "GREEN", "MAGENTA", "CYAN", "PINK" };
            return names[c.clamp (0, 7)];
        }

        int color_index (string name) {
            string[] names = { "PURPLE", "RED", "ORANGE", "YELLOW", "GREEN", "MAGENTA", "CYAN", "PINK" };
            for (int i = 0; i < names.length; i++) if (names[i] == name.up ()) return i;
            return 0;
        }

        void marker (Json.Builder b, Marker m, double rate) {
            b.begin_object ();
            Js.s (b, "OTIO_SCHEMA", "Marker.2");
            Js.s (b, "name", m.name);
            Js.s (b, "comment", m.comment);
            Js.s (b, "color", m.kind == "chapter" ? "YELLOW" : color_name (m.color));
            range (b, "marked_range", m.time, m.duration, rate);
            b.set_member_name ("metadata");
            b.begin_object ();
            b.set_member_name ("montage");
            b.begin_object ();
            Js.s (b, "kind", m.kind);
            b.end_object ();
            b.end_object ();
            b.end_object ();
        }

        string transition_type (string kind) {
            switch (kind) {
                case "dissolve":
                case "additive":
                case "constant-gain": return "SMPTE_Dissolve";
                default: return "Custom_Transition";
            }
        }

        public string write (Project p, Sequence s) {
            var b = new Json.Builder ();
            write_timeline (b, p, s);
            return Js.write (b.get_root (), true);
        }

        void write_timeline (Json.Builder b, Project p, Sequence s) {
            double rate = (double) s.fps_n / s.fps_d;
            b.begin_object ();
            Js.s (b, "OTIO_SCHEMA", "Timeline.1");
            Js.s (b, "name", s.name);
            rational (b, "global_start_time", 0, rate);
            b.set_member_name ("metadata");
            b.begin_object ();
            b.set_member_name ("montage");
            b.begin_object ();
            Js.i (b, "width", s.width);
            Js.i (b, "height", s.height);
            Js.i (b, "fps-n", s.fps_n);
            Js.i (b, "fps-d", s.fps_d);
            Js.s (b, "color-space", s.color_space);
            Js.s (b, "id", s.id);
            b.end_object ();
            b.end_object ();
            b.set_member_name ("tracks");
            write_stack (b, p, s, rate, "tracks", 0, s.duration);
            b.end_object ();
        }

        void write_stack (Json.Builder b, Project p, Sequence s, double rate, string name, int64 start, int64 duration) {
            b.begin_object ();
            Js.s (b, "OTIO_SCHEMA", "Stack.1");
            Js.s (b, "name", name);
            b.set_member_name ("source_range");
            if (start > 0 || duration != s.duration) {
                b.begin_object ();
                Js.s (b, "OTIO_SCHEMA", "TimeRange.1");
                rational (b, "start_time", start, rate);
                rational (b, "duration", duration, rate);
                b.end_object ();
            } else {
                b.add_null_value ();
            }
            b.set_member_name ("markers");
            b.begin_array ();
            foreach (var m in s.markers) marker (b, m, rate);
            b.end_array ();
            b.set_member_name ("effects");
            b.begin_array ();
            b.end_array ();
            b.set_member_name ("metadata");
            b.begin_object ();
            b.end_object ();
            b.set_member_name ("children");
            b.begin_array ();
            foreach (var t in s.tracks) {
                if (t.kind == TrackKind.SUBTITLE) continue;
                write_track (b, p, s, t, rate);
            }
            b.end_array ();
            b.end_object ();
        }

        void write_track (Json.Builder b, Project p, Sequence s, Track t, double rate) {
            b.begin_object ();
            Js.s (b, "OTIO_SCHEMA", "Track.1");
            Js.s (b, "name", t.name);
            Js.s (b, "kind", t.kind == TrackKind.AUDIO ? "Audio" : "Video");
            Js.f (b, "enabled", t.kind == TrackKind.AUDIO ? !t.muted : t.visible);
            b.set_member_name ("source_range");
            b.add_null_value ();
            b.set_member_name ("markers");
            b.begin_array ();
            b.end_array ();
            b.set_member_name ("effects");
            b.begin_array ();
            b.end_array ();
            b.set_member_name ("metadata");
            b.begin_object ();
            b.set_member_name ("montage");
            t.write (b);
            b.end_object ();
            b.set_member_name ("children");
            b.begin_array ();
            int64 cursor = 0;
            Clip? previous = null;
            foreach (var c in s.on_track (t.id)) {
                if (c.position > cursor) {
                    b.begin_object ();
                    Js.s (b, "OTIO_SCHEMA", "Gap.1");
                    Js.s (b, "name", "");
                    range (b, "source_range", 0, c.position - cursor, rate);
                    b.set_member_name ("effects");
                    b.begin_array ();
                    b.end_array ();
                    b.set_member_name ("markers");
                    b.begin_array ();
                    b.end_array ();
                    b.set_member_name ("metadata");
                    b.begin_object ();
                    b.end_object ();
                    b.end_object ();
                    previous = null;
                }
                var tr = previous != null ? s.transition_between (previous.id, c.id) : null;
                if (tr != null) {
                    int64 start = tr.start_at (c.position);
                    b.begin_object ();
                    Js.s (b, "OTIO_SCHEMA", "Transition.1");
                    Js.s (b, "name", tr.kind);
                    Js.s (b, "transition_type", transition_type (tr.kind));
                    rational (b, "in_offset", c.position - start, rate);
                    rational (b, "out_offset", start + tr.duration - c.position, rate);
                    b.set_member_name ("metadata");
                    b.begin_object ();
                    b.set_member_name ("montage");
                    tr.write (b);
                    b.end_object ();
                    b.end_object ();
                }
                write_clip (b, p, s, c, rate);
                cursor = c.end;
                previous = c;
            }
            b.end_array ();
            b.end_object ();
        }

        void write_clip (Json.Builder b, Project p, Sequence s, Clip c, double rate) {
            if (c.kind == ClipKind.SEQUENCE) {
                var n = p.find_sequence (c.sequence);
                if (n != null) {
                    write_stack (b, p, n, rate, n.name, c.in_point, c.duration);
                    return;
                }
            }
            b.begin_object ();
            Js.s (b, "OTIO_SCHEMA", "Clip.2");
            Js.s (b, "name", p.clip_label (c));
            Js.f (b, "enabled", c.enabled);
            int64 span = c.source_span ();
            range (b, "source_range", c.in_point, c.speed_changed ? c.duration : span, rate);
            b.set_member_name ("media_references");
            b.begin_object ();
            b.set_member_name ("DEFAULT_MEDIA");
            b.begin_object ();
            var m = p.find_media (c.media);
            if (c.kind == ClipKind.MEDIA && m != null) {
                Js.s (b, "OTIO_SCHEMA", "ExternalReference.1");
                Js.s (b, "name", m.name);
                Js.s (b, "target_url", m.uri);
                if (!m.still) range (b, "available_range", 0, m.duration, rate);
            } else if (c.kind == ClipKind.COLOR || c.kind == ClipKind.TITLE || c.kind == ClipKind.ADJUSTMENT) {
                Js.s (b, "OTIO_SCHEMA", "GeneratorReference.1");
                Js.s (b, "name", c.kind.key ());
                Js.s (b, "generator_kind", c.kind == ClipKind.COLOR ? "SolidColor" : (c.kind == ClipKind.TITLE ? "Title" : "Adjustment"));
                b.set_member_name ("parameters");
                b.begin_object ();
                if (c.kind == ClipKind.COLOR) Js.s (b, "color", c.color);
                if (c.kind == ClipKind.TITLE && c.title != null && c.title.layers.size > 0) Js.s (b, "text", Titles.expand (c.title.layers[0].text, c.title));
                b.end_object ();
            } else {
                Js.s (b, "OTIO_SCHEMA", "MissingReference.1");
                Js.s (b, "name", "");
            }
            b.set_member_name ("metadata");
            b.begin_object ();
            b.end_object ();
            b.end_object ();
            b.end_object ();
            Js.s (b, "active_media_reference_key", "DEFAULT_MEDIA");
            b.set_member_name ("effects");
            b.begin_array ();
            if (c.speed_changed && !c.params.values["speed"].animated) {
                b.begin_object ();
                Js.s (b, "OTIO_SCHEMA", "LinearTimeWarp.1");
                Js.s (b, "name", "speed");
                Js.s (b, "effect_name", "LinearTimeWarp");
                Js.d (b, "time_scalar", c.params.get_value ("speed", c.in_point, 100) / 100 * (c.reverse ? -1 : 1));
                b.end_object ();
            }
            foreach (var e in c.effects) {
                b.begin_object ();
                Js.s (b, "OTIO_SCHEMA", "Effect.1");
                Js.s (b, "name", e.type);
                Js.s (b, "effect_name", e.type);
                b.set_member_name ("metadata");
                b.begin_object ();
                b.end_object ();
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("markers");
            b.begin_array ();
            foreach (var mk in c.markers) {
                var shifted = mk.copy ();
                shifted.time = mk.time + c.in_point;
                marker (b, shifted, rate);
            }
            b.end_array ();
            b.set_member_name ("metadata");
            b.begin_object ();
            b.set_member_name ("montage");
            c.write (b);
            if (m != null) {
                b.set_member_name ("montage_media");
                m.write (b);
            }
            b.end_object ();
            b.end_object ();
        }

        int64 rt (Json.Object? o, double fallback_rate = 25) {
            if (o == null) return 0;
            double rate = Js.num (o, "rate", fallback_rate);
            double value = Js.num (o, "value", 0);
            return (int64) Math.round (value / double.max (1e-9, rate) * Tc.SECOND);
        }

        double rt_rate (Json.Object? o, double fallback) {
            return o != null ? Js.num (o, "rate", fallback) : fallback;
        }

        void tr_range (Json.Object? o, out int64 start, out int64 duration) {
            start = duration = 0;
            if (o == null) return;
            start = rt (Js.obj (o, "start_time"));
            duration = rt (Js.obj (o, "duration"));
        }

        public Project read (string text, File? origin) throws Error {
            var root = Js.parse (text);
            string schema = Js.str (root, "OTIO_SCHEMA");
            var p = new Project ();
            p.sequences.clear ();
            if (schema.has_prefix ("SerializableCollection")) {
                foreach (var child in Js.objects (root, "children")) {
                    if (Js.str (child, "OTIO_SCHEMA").has_prefix ("Timeline")) read_timeline (p, child, origin);
                }
            } else if (schema.has_prefix ("Timeline")) {
                read_timeline (p, root, origin);
            } else {
                throw new IOError.INVALID_DATA (_("This OpenTimelineIO file has no timeline."));
            }
            if (p.sequences.size == 0) throw new IOError.INVALID_DATA (_("This OpenTimelineIO file has no timeline."));
            p.active = p.sequences[0].id;
            return p;
        }

        Sequence read_timeline (Project p, Json.Object o, File? origin) {
            var s = new Sequence (Js.str (o, "name", _("Imported Timeline")));
            var meta = Js.obj (o, "metadata");
            var mm = meta != null ? Js.obj (meta, "montage") : null;
            double rate = rt_rate (Js.obj (o, "global_start_time"), 25);
            if (mm != null) {
                s.width = (int) Js.integer (mm, "width", 1920);
                s.height = (int) Js.integer (mm, "height", 1080);
                s.fps_n = (int) Js.integer (mm, "fps-n", 25);
                s.fps_d = (int) Js.integer (mm, "fps-d", 1);
                s.color_space = Js.str (mm, "color-space", "rec709");
            } else {
                set_rate (s, rate);
            }
            p.sequences.add (s);
            var stack = Js.obj (o, "tracks");
            if (stack != null) read_stack (p, s, stack, origin);
            return s;
        }

        void set_rate (Sequence s, double rate) {
            if ((rate - 29.97).abs () < 0.01) {
                s.fps_n = 30000;
                s.fps_d = 1001;
            } else if ((rate - 23.976).abs () < 0.01) {
                s.fps_n = 24000;
                s.fps_d = 1001;
            } else if ((rate - 59.94).abs () < 0.01) {
                s.fps_n = 60000;
                s.fps_d = 1001;
            } else {
                s.fps_n = int.max (1, (int) Math.round (rate));
                s.fps_d = 1;
            }
        }

        void read_stack (Project p, Sequence s, Json.Object stack, File? origin) {
            foreach (var m in Js.objects (stack, "markers")) s.markers.add (read_marker (m, 0));
            int vcount = 0, acount = 0;
            foreach (var to in Js.objects (stack, "children")) {
                string schema = Js.str (to, "OTIO_SCHEMA");
                if (!schema.has_prefix ("Track")) continue;
                bool audio = Js.str (to, "kind") == "Audio";
                Track t;
                var tm = Js.obj (to, "metadata");
                var mt = tm != null ? Js.obj (tm, "montage") : null;
                if (mt != null) t = Track.read (mt);
                else {
                    t = new Track (Js.str (to, "name", audio ? "A%d".printf (acount + 1) : "V%d".printf (vcount + 1)), audio ? TrackKind.AUDIO : TrackKind.VIDEO);
                    if (!Js.flag (to, "enabled", true)) {
                        if (audio) t.muted = true;
                        else t.visible = false;
                    }
                }
                if (t.name == "") t.name = audio ? "A%d".printf (acount + 1) : "V%d".printf (vcount + 1);
                if (s.track (t.id) != null) t.id = new_id ();
                if (audio) acount++;
                else vcount++;
                s.tracks.add (t);
                read_track (p, s, t, to, origin);
            }
            if (vcount == 0) s.tracks.insert (0, new Track ("V1", TrackKind.VIDEO));
            if (acount == 0) s.tracks.add (new Track ("A1", TrackKind.AUDIO));
            var v = new Gee.ArrayList<Track> ();
            var a = new Gee.ArrayList<Track> ();
            foreach (var t in s.tracks) {
                if (t.kind == TrackKind.AUDIO) a.add (t);
                else v.add (t);
            }
            s.tracks.clear ();
            s.tracks.add_all (v);
            s.tracks.add_all (a);
        }

        Marker read_marker (Json.Object o, int64 offset) {
            int64 start, duration;
            tr_range (Js.obj (o, "marked_range"), out start, out duration);
            var m = new Marker (start + offset, Js.str (o, "name"));
            m.duration = duration;
            m.comment = Js.str (o, "comment");
            m.color = color_index (Js.str (o, "color", "PURPLE"));
            var meta = Js.obj (o, "metadata");
            var mm = meta != null ? Js.obj (meta, "montage") : null;
            if (mm != null) m.kind = Js.str (mm, "kind", "comment");
            return m;
        }

        MediaItem media_for (Project p, string url, string name, int64 available, File? origin) {
            string uri = url;
            if (Uri.parse_scheme (url) == null) {
                var base_dir = origin != null ? origin.get_parent () : null;
                uri = (Path.is_absolute (url) || base_dir == null) ? File.new_for_path (url).get_uri () : base_dir.resolve_relative_path (url).get_uri ();
            }
            var existing = p.media_by_uri (uri);
            if (existing != null) return existing;
            MediaItem m;
            try {
                m = Probe.probe (uri);
            } catch (Error e) {
                m = new MediaItem ();
                m.uri = uri;
                m.name = name != "" ? name : (File.new_for_uri (uri).get_basename () ?? uri);
                m.duration = available > 0 ? available : 3600L * Tc.SECOND;
                m.has_video = true;
                m.has_audio = true;
                m.width = 1920;
                m.height = 1080;
            }
            p.media.add (m);
            return m;
        }

        void read_track (Project p, Sequence s, Track t, Json.Object to, File? origin) {
            int64 cursor = 0;
            Clip? previous = null;
            Json.Object? pending_transition = null;
            foreach (var item in Js.objects (to, "children")) {
                string schema = Js.str (item, "OTIO_SCHEMA");
                if (schema.has_prefix ("Gap")) {
                    int64 st, du;
                    tr_range (Js.obj (item, "source_range"), out st, out du);
                    cursor += du;
                    previous = null;
                    continue;
                }
                if (schema.has_prefix ("Transition")) {
                    pending_transition = item;
                    continue;
                }
                Clip? c = null;
                if (schema.has_prefix ("Stack")) {
                    var nested = new Sequence (Js.str (item, "name", _("Nested")));
                    nested.width = s.width;
                    nested.height = s.height;
                    nested.fps_n = s.fps_n;
                    nested.fps_d = s.fps_d;
                    p.sequences.add (nested);
                    read_stack (p, nested, item, origin);
                    c = new Clip ();
                    c.kind = ClipKind.SEQUENCE;
                    c.sequence = nested.id;
                    int64 st, du;
                    tr_range (Js.obj (item, "source_range"), out st, out du);
                    c.in_point = st;
                    c.duration = du > 0 ? du : nested.duration;
                } else if (schema.has_prefix ("Clip")) {
                    c = read_clip (p, item, origin);
                }
                if (c == null || c.duration <= 0) continue;
                c.track = t.id;
                c.position = cursor;
                if (s.clip (c.id) != null) c.id = new_id ();
                s.clips.add (c);
                if (pending_transition != null) {
                    var tr = new Transition ();
                    var tm = Js.obj (pending_transition, "metadata");
                    var mt = tm != null ? Js.obj (tm, "montage") : null;
                    if (mt != null) tr = Transition.read (mt);
                    int64 in_off = rt (Js.obj (pending_transition, "in_offset"));
                    int64 out_off = rt (Js.obj (pending_transition, "out_offset"));
                    tr.id = new_id ();
                    tr.track = t.id;
                    tr.from_clip = previous != null ? previous.id : "";
                    tr.to_clip = c.id;
                    tr.duration = in_off + out_off;
                    tr.align = in_off == out_off ? 0 : (in_off > out_off ? -1 : 1);
                    if (mt == null) tr.kind = Js.str (pending_transition, "transition_type") == "SMPTE_Dissolve" ? "dissolve" : "dissolve";
                    if (tr.duration > 0) s.transitions.add (tr);
                    pending_transition = null;
                }
                cursor += c.duration;
                previous = c;
            }
        }

        Clip? read_clip (Project p, Json.Object o, File? origin) {
            var meta = Js.obj (o, "metadata");
            var mc = meta != null ? Js.obj (meta, "montage") : null;
            int64 st, du;
            tr_range (Js.obj (o, "source_range"), out st, out du);
            if (mc != null) {
                var c = Clip.read (mc);
                var mm = Js.obj (meta, "montage_media");
                if (mm != null && c.media != "") {
                    var media = MediaItem.read (mm);
                    var existing = p.media_by_uri (media.uri);
                    if (existing != null) c.media = existing.id;
                    else if (p.find_media (media.id) == null) p.media.add (media);
                }
                return c;
            }
            var c = new Clip ();
            c.name = Js.str (o, "name");
            c.enabled = Js.flag (o, "enabled", true);
            c.in_point = st;
            c.duration = du;
            var refs = Js.obj (o, "media_references");
            string key = Js.str (o, "active_media_reference_key", "DEFAULT_MEDIA");
            Json.Object? r = refs != null ? Js.obj (refs, key) : Js.obj (o, "media_reference");
            if (r == null) return null;
            string rs = Js.str (r, "OTIO_SCHEMA");
            if (rs.has_prefix ("ExternalReference")) {
                int64 ast, adu;
                tr_range (Js.obj (r, "available_range"), out ast, out adu);
                var m = media_for (p, Js.str (r, "target_url"), Js.str (r, "name"), adu, origin);
                c.media = m.id;
                if (ast > 0) c.in_point -= ast;
                if (c.in_point < 0) c.in_point = 0;
            } else if (rs.has_prefix ("GeneratorReference")) {
                string kind = Js.str (r, "generator_kind");
                var par = Js.obj (r, "parameters");
                if (kind == "SolidColor") {
                    c.kind = ClipKind.COLOR;
                    if (par != null) c.color = Js.str (par, "color", "#000000ff");
                } else {
                    c.kind = ClipKind.TITLE;
                    c.title = Titles.builtin ()[0].data.copy ();
                    c.title.fields["title"] = par != null ? Js.str (par, "text", c.name) : c.name;
                }
            } else {
                return null;
            }
            foreach (var e in Js.objects (o, "effects")) {
                if (Js.str (e, "OTIO_SCHEMA").has_prefix ("LinearTimeWarp")) {
                    double scalar = Js.num (e, "time_scalar", 1);
                    if (scalar < 0) c.reverse = true;
                    c.params.ensure ("speed", 100).value = scalar.abs () * 100;
                    c.duration = (int64) (du / double.max (0.01, scalar.abs ()));
                }
            }
            foreach (var mk in Js.objects (o, "markers")) {
                var m = read_marker (mk, -c.in_point);
                c.markers.add (m);
            }
            return c;
        }

        public void write_bundle (Project p, Sequence s, File file) throws Error {
            var zip = new ZipArchive ();
            zip.add_text ("version.txt", "1.0.0", false);
            var copy = p.clone ();
            var seq = copy.find_sequence (s.id);
            var used = new Gee.HashSet<string> ();
            foreach (var c in seq.clips) if (c.media != "") used.add (c.media);
            foreach (var id in used) {
                var m = copy.find_media (id);
                if (m == null || m.kind != "file") continue;
                var src = File.new_for_uri (m.uri);
                if (!src.query_exists ()) continue;
                uint8[] data;
                src.load_contents (null, out data, null);
                string name = "media/%s-%s".printf (m.id, src.get_basename ());
                zip.add (name, data, false);
                m.uri = name;
            }
            zip.add_text ("content.otio", write (copy, seq));
            zip.save (file);
        }

        public Project read_bundle (File file, File extract_dir) throws Error {
            var zip = ZipArchive.read (file);
            var content = zip.text ("content.otio");
            if (content == null) throw new IOError.INVALID_DATA (_("The bundle has no content.otio."));
            if (!extract_dir.query_exists ()) extract_dir.make_directory_with_parents ();
            foreach (var name in zip.names ()) {
                if (!name.has_prefix ("media/") || name.contains ("..")) continue;
                var target = extract_dir.resolve_relative_path (name);
                var parent = target.get_parent ();
                if (!parent.query_exists ()) parent.make_directory_with_parents ();
                target.replace_contents (zip.get (name), null, false, FileCreateFlags.NONE, null);
            }
            return read (content, extract_dir.get_child ("content.otio"));
        }
    }

    namespace Interchange {
        public void merge (Project into, Project from) {
            into.checkpoint (_("Import Timeline"));
            var media_map = new Gee.HashMap<string, string> ();
            foreach (var m in from.media) {
                var existing = into.media_by_uri (m.uri);
                if (existing != null) media_map[m.id] = existing.id;
                else {
                    into.media.add (m);
                    media_map[m.id] = m.id;
                }
            }
            foreach (var s in from.sequences) {
                foreach (var c in s.clips) if (media_map.has_key (c.media)) c.media = media_map[c.media];
                if (into.find_sequence (s.id) != null) s.id = new_id ();
                into.sequences.add (s);
            }
            into.active = from.sequences[0].id;
            into.media_changed ();
            into.commit ();
        }
    }
}
