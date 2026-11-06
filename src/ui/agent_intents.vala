namespace Singularity.Apps.Montage {

    internal class MontageIntents : Object {
        private const string[] EDITS = { "split", "delete", "ripple-delete", "move", "speed", "transition", "close-gaps" };
        private const string[] KINDS = { "video", "audio", "subtitle" };

        private static string text (Json.Object args, string key) {
            return args.has_member (key) ? args.get_string_member (key) : "";
        }

        private static double num (Json.Object args, string key, double fallback) {
            return args.has_member (key) ? args.get_double_member (key) : fallback;
        }

        private static Json.Node obj (Json.Object o) {
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (o);
            return node;
        }

        private static string list (string[] values) {
            var b = new StringBuilder ("[");
            for (int i = 0; i < values.length; i++) {
                if (i > 0) b.append (",");
                b.append ("\"").append (values[i]).append ("\"");
            }
            return b.append ("]").str;
        }

        private static double secs (int64 t) {
            return Math.round (t / 1000000.0) / 1000.0;
        }

        private static int64 ticks (double s) {
            return (int64) Math.round (s * Tc.SECOND);
        }

        private static MontageWindow window (MontageApp app) {
            var w = app.get_active_window () as MontageWindow;
            if (w == null) {
                foreach (var win in app.get_windows ()) {
                    w = win as MontageWindow;
                    if (w != null) break;
                }
            }
            if (w == null) w = new MontageWindow (app);
            if (w.pages.visible_child_name != "workspace") w.new_project ();
            w.present ();
            return w;
        }

        private static Json.Node outline (MontageWindow w) {
            var ctl = w.ctl;
            var p = ctl.project;
            var seq = ctl.seq;
            var o = new Json.Object ();
            o.set_string_member ("project", p.name);
            o.set_string_member ("path", w.session.origin != null ? w.session.origin.get_path () ?? "" : "");
            o.set_boolean_member ("modified", w.session.modified);
            o.set_boolean_member ("can_undo", p.can_undo);
            o.set_boolean_member ("can_redo", p.can_redo);
            var so = new Json.Object ();
            so.set_string_member ("name", seq.name);
            so.set_int_member ("width", seq.width);
            so.set_int_member ("height", seq.height);
            so.set_double_member ("fps", seq.fps_d > 0 ? Math.round (seq.fps_n * 1000.0 / seq.fps_d) / 1000.0 : 0);
            so.set_double_member ("duration", secs (seq.duration));
            so.set_double_member ("playhead", secs (ctl.playhead));
            o.set_object_member ("sequence", so);
            var tracks = new Json.Array ();
            foreach (var t in seq.tracks) {
                var to = new Json.Object ();
                to.set_string_member ("id", t.id);
                to.set_string_member ("name", t.name);
                to.set_string_member ("kind", t.kind.key ());
                to.set_boolean_member ("muted", t.muted);
                to.set_boolean_member ("locked", t.locked);
                tracks.add_object_element (to);
            }
            o.set_array_member ("tracks", tracks);
            var clips = new Json.Array ();
            foreach (var c in seq.clips) {
                var co = new Json.Object ();
                co.set_string_member ("id", c.id);
                co.set_string_member ("name", p.clip_label (c));
                co.set_string_member ("track", c.track);
                co.set_double_member ("start", secs (c.position));
                co.set_double_member ("end", secs (c.end));
                if (c.media != "") co.set_string_member ("media", c.media);
                if (c.link != "") co.set_string_member ("link", c.link);
                clips.add_object_element (co);
            }
            o.set_array_member ("clips", clips);
            var media = new Json.Array ();
            foreach (var m in p.media) {
                var mo = new Json.Object ();
                mo.set_string_member ("id", m.id);
                mo.set_string_member ("name", m.name);
                mo.set_double_member ("duration", secs (m.duration));
                mo.set_boolean_member ("video", m.has_video);
                mo.set_boolean_member ("audio", m.has_audio);
                if (m.has_video) {
                    mo.set_int_member ("width", m.width);
                    mo.set_int_member ("height", m.height);
                }
                media.add_object_element (mo);
            }
            o.set_array_member ("media", media);
            var marks = new Json.Array ();
            foreach (var m in seq.markers) {
                var mo = new Json.Object ();
                mo.set_string_member ("name", m.name);
                mo.set_double_member ("at", secs (m.time));
                marks.add_object_element (mo);
            }
            o.set_array_member ("markers", marks);
            return obj (o);
        }

        private static MediaItem find_media (Project p, string key) throws Error {
            foreach (var m in p.media) if (m.id == key) return m;
            foreach (var m in p.media) if (m.name == key) return m;
            foreach (var m in p.media) if (m.name.casefold ().has_prefix (key.casefold ())) return m;
            throw new IOError.NOT_FOUND ("there is no media named %s", key);
        }

        private static Gee.ArrayList<string> clip_ids (Controller ctl, Json.Object args) throws Error {
            var ids = new Gee.ArrayList<string> ();
            if (args.has_member ("clips")) {
                foreach (var n in args.get_array_member ("clips").get_elements ()) {
                    string id = n.get_string ();
                    if (ctl.seq.clip (id) == null) throw new IOError.NOT_FOUND ("there is no clip %s", id);
                    ids.add (id);
                }
            }
            return ids;
        }

        private static void edit (Controller ctl, Json.Object args) throws Error {
            string op = text (args, "operation");
            if (!(op in EDITS)) throw new IOError.INVALID_ARGUMENT ("unknown operation %s", op);
            var ids = clip_ids (ctl, args);
            bool need_clips = op != "split" && op != "close-gaps";
            if (need_clips && ids.size == 0) throw new IOError.INVALID_ARGUMENT ("%s needs clips", op);
            switch (op) {
            case "split":
                ctl.edits.split (args.has_member ("at") ? ticks (num (args, "at", 0)) : ctl.playhead, ids);
                break;
            case "delete":
                ctl.edits.lift (ids);
                break;
            case "ripple-delete":
                ctl.edits.ripple_delete (ids);
                break;
            case "move":
                if (!args.has_member ("seconds")) throw new IOError.INVALID_ARGUMENT ("move needs seconds");
                ctl.edits.move (ids, ticks (num (args, "seconds", 0)), 0, false);
                break;
            case "speed": {
                double pct = num (args, "percent", 100);
                if (pct < 1 || pct > 10000) throw new IOError.INVALID_ARGUMENT ("percent must be between 1 and 10000");
                foreach (var id in ids) ctl.edits.set_speed (id, pct, args.has_member ("reverse") && args.get_boolean_member ("reverse"), true, true);
                break;
            }
            case "transition": {
                bool at_end = !(args.has_member ("at_start") && args.get_boolean_member ("at_start"));
                double dur = num (args, "seconds", 1);
                if (dur <= 0) throw new IOError.INVALID_ARGUMENT ("seconds must be positive");
                string kind = text (args, "kind");
                ctl.edits.add_transition (ids[0], at_end, kind != "" ? kind : "dissolve", ticks (dur), 0);
                break;
            }
            default: {
                string track = text (args, "track");
                if (track == "") {
                    foreach (var t in ctl.seq.tracks) ctl.edits.close_gaps (t.id);
                } else {
                    if (ctl.seq.track (track) == null) throw new IOError.NOT_FOUND ("there is no track %s", track);
                    ctl.edits.close_gaps (track);
                }
                break;
            }
            }
        }

        private static async void wait_job (ExportQueue queue, ExportJob job) throws Error {
            bool done = false;
            bool ok = false;
            string? error = null;
            ulong id = job.finished.connect ((good, err) => {
                done = true;
                ok = good;
                error = err;
                Idle.add (wait_job.callback);
            });
            queue.add (job);
            if (!done) yield;
            job.disconnect (id);
            if (!ok) throw new IOError.FAILED ("export failed: %s", error ?? job.message);
        }

        private static async Json.Node handle (MontageApp app, string name, Json.Object args) throws Error {
            var w = window (app);
            var ctl = w.ctl;
            switch (name) {
            case "montage_outline":
                return outline (w);
            case "montage_import": {
                var files = new Gee.ArrayList<File> ();
                if (args.has_member ("paths")) {
                    foreach (var n in args.get_array_member ("paths").get_elements ()) {
                        string path = n.get_string ();
                        if (!FileUtils.test (path, FileTest.IS_REGULAR)) throw new IOError.NOT_FOUND ("%s does not exist", path);
                        files.add (File.new_for_path (path));
                    }
                }
                if (files.size == 0) throw new IOError.INVALID_ARGUMENT ("give the paths to import");
                var errors = yield Importing.import_files (w, files);
                if (errors.size > 0) {
                    var o = outline (w).get_object ();
                    var a = new Json.Array ();
                    foreach (var e in errors) a.add_string_element (e);
                    o.set_array_member ("errors", a);
                    bool any = false;
                    foreach (var f in files) if (ctl.project.media_by_uri (f.get_uri ()) != null) any = true;
                    if (!any) throw new IOError.FAILED ("the files could not be imported: %s", string.joinv ("; ", errors.to_array ()));
                    return obj (o);
                }
                return outline (w);
            }
            case "montage_place": {
                var m = find_media (ctl.project, text (args, "media"));
                int64 in_p = ticks (num (args, "in", 0)).clamp (0, m.duration);
                int64 out_p = args.has_member ("out") ? ticks (num (args, "out", 0)) : (m.still ? in_p + 5 * Tc.SECOND : m.duration);
                if (!m.still) out_p = out_p.clamp (0, m.duration);
                if (out_p <= in_p) throw new IOError.INVALID_ARGUMENT ("out must come after in");
                string? v = m.has_video ? ctl.target_track (TrackKind.VIDEO) : null;
                string? a = m.has_audio ? ctl.target_track (TrackKind.AUDIO) : null;
                int64 at;
                if (args.has_member ("at")) {
                    at = ticks (num (args, "at", 0));
                    if (at < 0) throw new IOError.INVALID_ARGUMENT ("at cannot be negative");
                } else {
                    at = 0;
                    foreach (var c in ctl.seq.clips) if (c.track == v || c.track == a) at = int64.max (at, c.end);
                }
                var clips = ctl.edits.make_media_clips (m, in_p, out_p, v, a);
                ctl.edits.place (clips, at, args.has_member ("insert") && args.get_boolean_member ("insert"));
                if (clips.size > 0) ctl.select (clips[0]);
                return outline (w);
            }
            case "montage_edit":
                edit (ctl, args);
                return outline (w);
            case "montage_track": {
                string kind = text (args, "kind");
                if (!(kind in KINDS)) throw new IOError.INVALID_ARGUMENT ("kind must be video, audio or subtitle");
                ctl.edits.add_track (kind == "video" ? TrackKind.VIDEO : kind == "audio" ? TrackKind.AUDIO : TrackKind.SUBTITLE);
                return outline (w);
            }
            case "montage_marker": {
                if (!args.has_member ("at")) throw new IOError.INVALID_ARGUMENT ("a marker needs at, in seconds");
                int64 at = ticks (num (args, "at", 0));
                if (at < 0) throw new IOError.INVALID_ARGUMENT ("at cannot be negative");
                string label = text (args, "name");
                ctl.edits.add_marker (at, label != "" ? label : _("Marker"), "comment");
                return outline (w);
            }
            case "montage_history": {
                string step = text (args, "step");
                if (step == "undo") {
                    if (!ctl.project.can_undo) throw new IOError.FAILED ("there is nothing to undo");
                    ctl.project.undo ();
                } else if (step == "redo") {
                    if (!ctl.project.can_redo) throw new IOError.FAILED ("there is nothing to redo");
                    ctl.project.redo ();
                } else {
                    throw new IOError.INVALID_ARGUMENT ("step must be undo or redo");
                }
                return outline (w);
            }
            case "montage_seek":
                if (!args.has_member ("at")) throw new IOError.INVALID_ARGUMENT ("at is required");
                ctl.seek (ticks (num (args, "at", 0)).clamp (0, int64.max (0, ctl.seq.duration)));
                return outline (w);
            case "montage_presets": {
                var a = new Json.Array ();
                foreach (var pr in Presets.all ()) {
                    var po = new Json.Object ();
                    po.set_string_member ("id", pr.id);
                    po.set_string_member ("name", pr.name);
                    po.set_string_member ("category", pr.category);
                    po.set_string_member ("container", pr.container);
                    a.add_object_element (po);
                }
                var o = new Json.Object ();
                o.set_array_member ("presets", a);
                return obj (o);
            }
            case "montage_save": {
                string path = text (args, "path");
                if (path == "" && w.session.origin != null) path = w.session.origin.get_path () ?? "";
                if (path == "") throw new IOError.INVALID_ARGUMENT ("the project has no file yet; give a path");
                if (!path.has_suffix (NativeFormat.EXTENSION)) path += NativeFormat.EXTENSION;
                w.session.save (File.new_for_path (path));
                w.update_title ();
                return outline (w);
            }
            default: {
                if (ctl.seq.clips.size == 0) throw new IOError.FAILED ("the timeline is empty");
                string path = text (args, "path");
                if (path == "") throw new IOError.INVALID_ARGUMENT ("a path is required");
                string preset = text (args, "preset");
                ExportPreset? found = null;
                foreach (var pr in Presets.all ()) if (pr.id == (preset != "" ? preset : "web-1080")) found = pr;
                if (found == null) throw new IOError.NOT_FOUND ("unknown preset %s", preset);
                var settings = new ExportSettings ();
                settings.preset = found.copy ();
                settings.output = File.new_for_path (path);
                settings.hardware = false;
                if (args.has_member ("start")) settings.start = ticks (num (args, "start", 0));
                if (args.has_member ("end")) settings.end = ticks (num (args, "end", 0));
                settings.sequence_id = ctl.seq.id;
                var job = new ExportJob (ctl.project.clone (), settings);
                yield wait_job (ctl.queue, job);
                var o = new Json.Object ();
                o.set_string_member ("path", path);
                o.set_string_member ("preset", found.id);
                o.set_string_member ("encoder", job.encoder_used);
                return obj (o);
            }
            }
        }

        private static void add (MontageApp app, string name, string description, string schema, Singularity.AppIntentRisk risk) {
            app.agent.add_async_intent (name, description, schema, risk, (args, reply) => {
                handle.begin (app, name, args, (o, res) => {
                    try {
                        reply (handle.end (res), null);
                    } catch (Error e) {
                        reply (null, e);
                    }
                });
            });
        }

        internal static void install (MontageApp app) {
            add (app, "montage_outline", "Read the open project: the sequence (size, frame rate, duration, playhead), its tracks, clips with ids and times in seconds, the imported media and the markers.",
                "{\"type\":\"object\",\"properties\":{}}", Singularity.AppIntentRisk.READ);
            add (app, "montage_import", "Import video, audio or image files into the project. Into an empty timeline they are also placed one after another.",
                "{\"type\":\"object\",\"properties\":{\"paths\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}},\"required\":[\"paths\"]}", Singularity.AppIntentRisk.UNDOABLE);
            add (app, "montage_place", "Put imported media on the timeline, from in to out seconds of the source, at a time in seconds (default: after the last clip); insert pushes later clips.",
                "{\"type\":\"object\",\"properties\":{\"media\":{\"type\":\"string\",\"description\":\"Media id or name\"},\"in\":{\"type\":\"number\"},\"out\":{\"type\":\"number\"},\"at\":{\"type\":\"number\"},\"insert\":{\"type\":\"boolean\"}},\"required\":[\"media\"]}", Singularity.AppIntentRisk.UNDOABLE);
            add (app, "montage_edit", "Edit clips by id: split at seconds (or the playhead), delete leaving a gap, ripple delete, move by seconds, change speed in percent, add a transition of seconds at a clip end, or close the gaps of a track.",
                "{\"type\":\"object\",\"properties\":{\"operation\":{\"type\":\"string\",\"enum\":" + list (EDITS) + "},\"clips\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"at\":{\"type\":\"number\"},\"seconds\":{\"type\":\"number\"},\"percent\":{\"type\":\"number\"},\"reverse\":{\"type\":\"boolean\"},\"kind\":{\"type\":\"string\"},\"at_start\":{\"type\":\"boolean\"},\"track\":{\"type\":\"string\"}},\"required\":[\"operation\"]}", Singularity.AppIntentRisk.UNDOABLE);
            add (app, "montage_track", "Add a video, audio or subtitle track.",
                "{\"type\":\"object\",\"properties\":{\"kind\":{\"type\":\"string\",\"enum\":" + list (KINDS) + "}},\"required\":[\"kind\"]}", Singularity.AppIntentRisk.UNDOABLE);
            add (app, "montage_marker", "Add a marker to the sequence at a time in seconds.",
                "{\"type\":\"object\",\"properties\":{\"at\":{\"type\":\"number\"},\"name\":{\"type\":\"string\"}},\"required\":[\"at\"]}", Singularity.AppIntentRisk.UNDOABLE);
            add (app, "montage_history", "Undo or redo the last edit.",
                "{\"type\":\"object\",\"properties\":{\"step\":{\"type\":\"string\",\"enum\":[\"undo\",\"redo\"]}},\"required\":[\"step\"]}", Singularity.AppIntentRisk.UNDOABLE);
            add (app, "montage_seek", "Move the playhead to a time in seconds.",
                "{\"type\":\"object\",\"properties\":{\"at\":{\"type\":\"number\"}},\"required\":[\"at\"]}", Singularity.AppIntentRisk.READ);
            add (app, "montage_presets", "List the export presets.",
                "{\"type\":\"object\",\"properties\":{}}", Singularity.AppIntentRisk.READ);
            add (app, "montage_save", "Save the project as a Montage file, to its file or a new path.",
                "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}}}", Singularity.AppIntentRisk.IRREVERSIBLE);
            add (app, "montage_export", "Render the sequence to a file with an export preset (default web-1080), optionally only from start to end seconds, and wait until it is written.",
                "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"preset\":{\"type\":\"string\"},\"start\":{\"type\":\"number\"},\"end\":{\"type\":\"number\"}},\"required\":[\"path\"]}", Singularity.AppIntentRisk.IRREVERSIBLE);
        }
    }
}
