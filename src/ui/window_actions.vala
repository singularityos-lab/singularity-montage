using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Montage {
    namespace WindowActions {
        public delegate void Handler (MontageWindow w);
        public delegate void ParamHandler (MontageWindow w, string value);

        void add (MontageWindow w, string name, owned Handler handler) {
            var a = new SimpleAction (name, null);
            a.activate.connect (() => handler (w));
            w.add_action (a);
        }

        void add_param (MontageWindow w, string name, owned ParamHandler handler) {
            var a = new SimpleAction (name, VariantType.STRING);
            a.activate.connect ((v) => handler (w, v.get_string ()));
            w.add_action (a);
        }

        public delegate void Risky () throws Error;

        void attempt (MontageWindow w, owned Risky action) {
            try {
                action ();
            } catch (Error e) {
                w.say (e.message);
            }
        }

        public void install (MontageWindow w) {
            var ctl = w.ctl;
            add (w, "new-project", (w) => {
                if (w.session.modified) {
                    var other = new MontageWindow ((MontageApp) w.application);
                    other.present ();
                    other.new_project ();
                } else {
                    w.new_project ();
                }
            });
            add (w, "open", (w) => {
                FileOps.open_dialog.begin (w, {
                    FileOps.filter (_("All Supported Projects and Timelines"), { "montage", "otio", "otioz", "edl", "xml", "fcpxml", "prproj", "aaf", "kdenlive", "mlt" }),
                    FileOps.filter (_("Montage Projects"), { "montage" })
                }, (o, r) => {
                    var f = FileOps.open_dialog.end (r);
                    if (f == null) return;
                    if (w.session.modified || w.ctl.seq.clips.size > 0) {
                        var other = new MontageWindow ((MontageApp) w.application);
                        other.present ();
                        other.open_file (f);
                    } else {
                        w.open_file (f);
                    }
                });
            });
            add (w, "save", (w) => FileOps.save.begin (w, false));
            add (w, "save-as", (w) => FileOps.save.begin (w, true));
            add (w, "close-project", (w) => {
                if (w.session.modified) {
                    var dialog = new ConfirmDialog (w.application, _("Close Without Saving?"), "dialog-warning",
                        _("The project has unsaved changes."), _("Close Project"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
                    dialog.transient_for = w;
                    dialog.response.connect ((resp) => {
                        if (resp != ConfirmDialog.Response.PRIMARY) return;
                        w.session.discard_recovery ();
                        w.project.replace_with (new Project ());
                        w.session.opened (null);
                        w.show_welcome ();
                    });
                    dialog.present ();
                    return;
                }
                w.ctl.program.pause ();
                w.project.replace_with (new Project ());
                w.session.opened (null);
                w.show_welcome ();
            });
            add (w, "import", (w) => {
                var dialog = new FileDialog ();
                dialog.filters = FileOps.filters ({
                    FileOps.filter (_("Video, Audio and Pictures"), Probe.MEDIA_EXTENSIONS)
                });
                dialog.open_multiple.begin (w, null, (o, r) => {
                    try {
                        var list = dialog.open_multiple.end (r);
                        var files = new Gee.ArrayList<File> ();
                        for (uint i = 0; i < list.get_n_items (); i++) files.add ((File) list.get_item (i));
                        if (w.pages.visible_child_name != "workspace") w.new_project ();
                        Importing.import_files.begin (w, files);
                    } catch (Error e) {
                    }
                });
            });
            add (w, "import-folder", (w) => {
                var dialog = new FileDialog ();
                dialog.select_folder.begin (w, null, (o, r) => {
                    try {
                        var folder = dialog.select_folder.end (r);
                        var files = Probe.scan_folder (folder);
                        if (files.size == 0) {
                            w.say (_("No media files found in %s.").printf (folder.get_basename ()));
                            return;
                        }
                        w.project.checkpoint (_("New Bin"));
                        var bin = new Bin (folder.get_basename () ?? _("Folder"));
                        w.project.bins.add (bin);
                        w.project.commit ();
                        Importing.import_files.begin (w, files, bin.id);
                    } catch (Error e) {
                    }
                });
            });
            add (w, "import-card", (w) => {
                var folders = Probe.camera_folders ();
                if (folders.size == 0) {
                    w.say (_("No camera card or phone storage is mounted. Connect it and try again."));
                    return;
                }
                foreach (var folder in folders) {
                    var files = Probe.scan_folder (folder);
                    if (files.size == 0) continue;
                    w.project.checkpoint (_("New Bin"));
                    var bin = new Bin (_("Card %s").printf (new DateTime.now_local ().format ("%x")));
                    w.project.bins.add (bin);
                    w.project.commit ();
                    Importing.import_files.begin (w, files, bin.id);
                }
            });
            add (w, "import-nearby", (w) => NearbyImport.run.begin (w));
            add (w, "import-subtitles", (w) => {
                FileOps.open_dialog.begin (w, { FileOps.filter (_("Subtitles"), { "srt", "vtt" }) }, (o, r) => {
                    var f = FileOps.open_dialog.end (r);
                    if (f == null) return;
                    attempt (w, () => {
                        uint8[] data;
                        f.load_contents (null, out data, null);
                        var cues = Subtitles.parse ((string) data);
                        Subtitles.add_cues (w.project, cues, _("Import Subtitles"));
                        w.say (ngettext ("Imported %d caption.", "Imported %d captions.", cues.size).printf (cues.size));
                    });
                });
            });
            add (w, "import-timeline", (w) => {
                FileOps.open_dialog.begin (w, {
                    FileOps.filter (_("Timelines"), { "otio", "otioz", "edl", "xml", "fcpxml", "prproj", "aaf", "kdenlive", "mlt" })
                }, (o, r) => {
                    var f = FileOps.open_dialog.end (r);
                    if (f == null) return;
                    attempt (w, () => {
                        var imported = Importers.read (f);
                        if (w.pages.visible_child_name != "workspace") w.new_project ();
                        Interchange.merge (w.project, imported);
                        w.timeline.zoom_fit ();
                        w.say (imported.notes != "" ? imported.notes : _("Imported %s as a new sequence.").printf (f.get_basename ()));
                    });
                });
            });
            add (w, "import-composition", (w) => {
                FileOps.open_dialog.begin (w, { FileOps.filter (_("Keyframe Compositions"), { "keyframe", "json" }) }, (o, r) => {
                    var f = FileOps.open_dialog.end (r);
                    if (f == null) return;
                    attempt (w, () => {
                        if ((f.get_basename () ?? "").has_suffix (".keyframe")) {
                            var zip = ZipArchive.read (f);
                            if (zip.text ("project.json") != null) {
                                var files = new Gee.ArrayList<File> ();
                                files.add (f);
                                Importing.import_files.begin (w, files, null, (o2, r2) => {
                                    Importing.import_files.end (r2);
                                    var m = w.project.media_by_uri (f.get_uri ());
                                    if (m != null) Importing.append_to_timeline (w, m);
                                    CompositionWatch.watch (w, f);
                                });
                                return;
                            }
                        }
                        var comp = Composition.load (f);
                        var c = new Clip ();
                        c.kind = ClipKind.COMPOSITION;
                        c.composition = f.get_uri ();
                        c.duration = comp.duration;
                        c.track = w.ctl.target_track (TrackKind.VIDEO);
                        var list = new Gee.ArrayList<Clip> ();
                        list.add (c);
                        w.ctl.edits.place (list, w.ctl.playhead, false);
                        CompositionWatch.watch (w, f);
                        w.ctl.select (c);
                    });
                });
            });
            add (w, "undo", (w) => {
                if (!w.project.can_undo) return;
                string label = w.project.undo_label;
                w.project.undo ();
                w.say (_("Undid %s").printf (label));
            });
            add (w, "redo", (w) => w.project.redo ());
            add (w, "split", (w) => attempt (w, () => w.ctl.edits.split (w.ctl.playhead, w.ctl.selection)));
            add (w, "lift", (w) => attempt (w, () => w.ctl.edits.lift (w.ctl.selection)));
            add (w, "ripple-delete", (w) => attempt (w, () => w.ctl.edits.ripple_delete (w.ctl.selection)));
            add (w, "lift-range", (w) => attempt (w, () => w.ctl.edits.delete_range (w.ctl.seq.in_point, w.ctl.seq.out_point, false)));
            add (w, "extract-range", (w) => attempt (w, () => w.ctl.edits.delete_range (w.ctl.seq.in_point, w.ctl.seq.out_point, true)));
            add (w, "close-gaps", (w) => attempt (w, () => w.ctl.edits.close_gaps (w.ctl.selected_track != "" ? w.ctl.selected_track : w.ctl.seq.tracks[0].id)));
            add (w, "link", (w) => attempt (w, () => w.ctl.edits.link (w.ctl.selection, true)));
            add (w, "unlink", (w) => attempt (w, () => w.ctl.edits.link (w.ctl.selection, false)));
            add (w, "nest", (w) => attempt (w, () => {
                var n = w.ctl.edits.nest (w.ctl.selection, _("Nested Sequence %d").printf (w.project.sequences.size));
                w.say (_("Created %s. Open it from the project panel to edit inside.").printf (n.name));
            }));
            add (w, "toggle-clip", (w) => {
                var clips = w.ctl.selected_clips ();
                if (clips.size == 0) return;
                w.project.checkpoint (_("Enable or Disable"));
                bool target = !clips[0].enabled;
                foreach (var c in clips) c.enabled = target;
                w.project.commit ();
            });
            add (w, "resync", (w) => {
                var c = w.ctl.primary;
                if (c != null) attempt (w, () => w.ctl.edits.resync (c.id));
            });
            add (w, "speed", (w) => {
                w.inspector_stack.visible_child_name = "edit";
                w.workspace_switch.set_active ("edit");
                w.inspector_revealer.reveal_child = true;
                w.say (_("Set the speed in the Speed group of the inspector."));
            });
            add (w, "insert", (w) => place_source (w, true));
            add (w, "overwrite", (w) => place_source (w, false));
            add (w, "append", (w) => {
                var m = w.ctl.source_media;
                if (m != null) Importing.append_to_timeline (w, m);
            });
            add (w, "add-title", (w) => add_generated (w, ClipKind.TITLE));
            add (w, "add-color", (w) => add_generated (w, ClipKind.COLOR));
            add (w, "add-adjustment", (w) => add_generated (w, ClipKind.ADJUSTMENT));
            add (w, "add-transition", (w) => {
                var c = w.ctl.primary;
                if (c == null) {
                    w.say (_("Select a clip first."));
                    return;
                }
                attempt (w, () => {
                    var app = (MontageApp) w.application;
                    int frames = app.get_int ("transition-frames", 25);
                    bool at_end = w.ctl.playhead >= c.position + c.duration / 2;
                    w.ctl.edits.add_transition (c.id, at_end, "dissolve", Tc.from_frames (frames, w.ctl.seq.fps_n, w.ctl.seq.fps_d), 0);
                });
            });
            add_param (w, "add-track", (w, kind) => {
                var t = w.ctl.edits.add_track (TrackKind.from_key (kind));
                w.ctl.selected_track = t.id;
            });
            add (w, "add-bus", (w) => {
                w.project.checkpoint (_("Add Bus"));
                w.ctl.seq.buses.add (new Bus (_("Bus %d").printf (w.ctl.seq.buses.size + 1)));
                w.project.commit ();
            });
            add (w, "play-pause", (w) => {
                if (w.pages.visible_child_name != "workspace") return;
                w.ctl.program.toggle ();
            });
            add (w, "shuttle-forward", (w) => shuttle (w, 1));
            add (w, "shuttle-back", (w) => shuttle (w, -1));
            add (w, "shuttle-stop", (w) => w.ctl.program.pause ());
            add (w, "frame-back", (w) => {
                w.ctl.program.pause ();
                w.ctl.seek (w.ctl.playhead - w.ctl.seq.frame);
            });
            add (w, "frame-forward", (w) => {
                w.ctl.program.pause ();
                w.ctl.seek (w.ctl.playhead + w.ctl.seq.frame);
            });
            add (w, "go-start", (w) => w.ctl.seek (0));
            add (w, "go-end", (w) => w.ctl.seek (w.ctl.seq.duration - w.ctl.seq.frame));
            add (w, "next-edit", (w) => {
                foreach (var p in w.ctl.seq.edit_points ()) if (p > w.ctl.playhead) {
                    w.ctl.seek (p);
                    return;
                }
            });
            add (w, "previous-edit", (w) => {
                int64 best = 0;
                foreach (var p in w.ctl.seq.edit_points ()) if (p < w.ctl.playhead) best = p;
                w.ctl.seek (best);
            });
            add (w, "mark-in", (w) => {
                w.project.checkpoint (_("Mark In"));
                w.ctl.seq.in_point = w.ctl.playhead;
                if (w.ctl.seq.out_point >= 0 && w.ctl.seq.out_point <= w.ctl.seq.in_point) w.ctl.seq.out_point = -1;
                w.project.commit ();
            });
            add (w, "mark-out", (w) => {
                w.project.checkpoint (_("Mark Out"));
                w.ctl.seq.out_point = w.ctl.playhead + w.ctl.seq.frame;
                if (w.ctl.seq.in_point >= w.ctl.seq.out_point) w.ctl.seq.in_point = -1;
                w.project.commit ();
            });
            add (w, "clear-marks", (w) => {
                w.project.checkpoint (_("Clear In and Out"));
                w.ctl.seq.in_point = w.ctl.seq.out_point = -1;
                w.project.commit ();
            });
            add (w, "add-marker", (w) => w.ctl.edits.add_marker (w.ctl.playhead, _("Marker %d").printf (w.ctl.seq.markers.size + 1), "comment"));
            add (w, "add-chapter", (w) => w.ctl.edits.add_marker (w.ctl.playhead, _("Chapter %d").printf (w.ctl.seq.markers.size + 1), "chapter"));
            add (w, "ripple-trim-previous", (w) => ripple_to_playhead (w, true));
            add (w, "ripple-trim-next", (w) => ripple_to_playhead (w, false));
            add_param (w, "tool", (w, tool) => {
                var b = w.tool_buttons[tool];
                if (b != null) b.active = true;
            });
            add_param (w, "workspace", (w, name) => {
                if (w.simple) w.set_simple (false);
                w.workspace_switch.set_active (name);
                w.inspector_stack.visible_child_name = name;
                w.inspector_revealer.reveal_child = true;
            });
            add (w, "toggle-sidebar", (w) => w.set_sidebar_visible (!w.get_sidebar_visible ()));
            add (w, "toggle-inspector", (w) => w.inspector_revealer.reveal_child = !w.inspector_revealer.reveal_child);
            add (w, "simple-mode", (w) => w.set_simple (!w.simple));
            add (w, "zoom-in", (w) => w.timeline.zoom (1.4));
            add (w, "zoom-out", (w) => w.timeline.zoom (0.7));
            add (w, "zoom-fit", (w) => w.timeline.zoom_fit ());
            add (w, "snapping", (w) => {
                w.ctl.snapping = !w.ctl.snapping;
                w.ribbon.sync ();
                w.say (w.ctl.snapping ? _("Snapping on") : _("Snapping off"));
            });
            add (w, "linked", (w) => {
                w.ctl.linked = !w.ctl.linked;
                w.ribbon.sync ();
                w.say (w.ctl.linked ? _("Linked selection on") : _("Linked selection off"));
            });
            add (w, "use-proxies", (w) => {
                w.project.use_proxies = !w.project.use_proxies;
                w.project.commit ();
                w.ribbon.sync ();
                w.say (w.project.use_proxies ? _("Playing proxies where available. Export always uses the originals.") : _("Playing the original media."));
            });
            add (w, "make-proxies", (w) => {
                int n = 0;
                foreach (var m in w.project.media) if (m.has_video && !m.still) {
                    w.ctl.proxies.request (m);
                    n++;
                }
                w.say (ngettext ("Making %d proxy in the background.", "Making %d proxies in the background.", n).printf (n));
            });
            add (w, "new-sequence", (w) => {
                w.project.checkpoint (_("New Sequence"));
                var s = new Sequence (_("Sequence %d").printf (w.project.sequences.size + 1));
                var cur = w.ctl.seq;
                s.width = cur.width;
                s.height = cur.height;
                s.fps_n = cur.fps_n;
                s.fps_d = cur.fps_d;
                s.add_default_tracks ();
                w.project.sequences.add (s);
                w.project.active = s.id;
                w.project.commit ();
                if (w.pages.visible_child_name != "workspace") w.show_workspace ();
            });
            add (w, "shortcuts", (w) => Shortcuts.show (w));
            Features.install (w);
        }

        void shuttle (MontageWindow w, int direction) {
            var pb = w.ctl.program;
            double rate = pb.rate;
            if (direction > 0) rate = rate <= 0 ? 1 : double.min (8, rate * 2);
            else rate = rate >= 0 ? -1 : double.max (-8, rate * 2);
            pb.play (rate);
            w.say (_("Playing at %gx").printf (rate));
        }

        void ripple_to_playhead (MontageWindow w, bool previous) {
            var seq = w.ctl.seq;
            int64 t = w.ctl.playhead;
            string? track = w.ctl.selected_track != "" ? w.ctl.selected_track : null;
            foreach (var c in seq.clips) {
                if (track != null && c.track != track) continue;
                if (t <= c.position || t >= c.end) continue;
                attempt (w, () => {
                    if (previous) w.ctl.edits.trim (c.id, true, t - c.position, TrimMode.RIPPLE, true);
                    else w.ctl.edits.trim (c.id, false, t - c.end, TrimMode.RIPPLE, true);
                });
                if (previous) w.ctl.seek (c.position);
                return;
            }
        }

        void place_source (MontageWindow w, bool insert) {
            var m = w.ctl.source_media;
            if (m == null) {
                w.say (_("Choose a clip in the project panel first."));
                return;
            }
            int64 in_p = m.mark_in >= 0 ? m.mark_in : 0;
            int64 out_p = m.mark_out > in_p ? m.mark_out : (m.still ? in_p + 5 * Tc.SECOND : m.duration);
            string? v = m.has_video ? w.ctl.target_track (TrackKind.VIDEO) : null;
            string? a = m.has_audio ? w.ctl.target_track (TrackKind.AUDIO) : null;
            var clips = w.ctl.edits.make_media_clips (m, in_p, out_p, v, a);
            if (clips.size == 0) {
                w.say (_("The marked range is empty."));
                return;
            }
            attempt (w, () => {
                int64 at = w.ctl.seq.in_point >= 0 ? w.ctl.seq.in_point : w.ctl.playhead;
                w.ctl.edits.place (clips, at, insert);
                w.ctl.select (clips[0]);
                w.ctl.seek (at + clips[0].duration);
            });
        }

        void add_generated (MontageWindow w, ClipKind kind) {
            var c = new Clip ();
            c.kind = kind;
            c.duration = 5 * Tc.SECOND;
            if (kind == ClipKind.TITLE) {
                c.title = Titles.builtin ()[0].data.copy ();
                c.title.template_id = "title";
            }
            if (kind == ClipKind.COLOR) c.color = "#1c71d8ff";
            var seq = w.ctl.seq;
            var videos = seq.tracks_of (TrackKind.VIDEO);
            string? target = null;
            int64 at = w.ctl.playhead;
            for (int i = videos.size - 1; i >= 0; i--) {
                if (videos[i].locked) continue;
                bool free = true;
                foreach (var o in seq.on_track (videos[i].id)) if (o.position < at + c.duration && o.end > at) free = false;
                if (free) {
                    target = videos[i].id;
                    break;
                }
            }
            if (target == null) target = w.ctl.edits.add_track (TrackKind.VIDEO).id;
            c.track = target;
            var list = new Gee.ArrayList<Clip> ();
            list.add (c);
            attempt (w, () => {
                w.ctl.edits.place (list, at, false);
                w.ctl.select (c);
                w.inspector_stack.visible_child_name = "edit";
                w.workspace_switch.set_active ("edit");
                w.inspector_revealer.reveal_child = true;
            });
        }
    }
}
