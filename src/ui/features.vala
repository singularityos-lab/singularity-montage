using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Montage {
    namespace Tasks {
        public delegate void Work (Progress progress) throws Error;
        public delegate void Done (string? error);

        public void run (MontageWindow w, string label, owned Work work, owned Done done) {
            w.say (label);
            double shown = -1;
            string? failure = null;
            new Thread<void*> ("montage-task", () => {
                try {
                    work ((f) => {
                        if (f - shown >= 0.05) {
                            shown = f;
                            double value = f;
                            Idle.add (() => {
                                w.say ("%s %d%%".printf (label, (int) (value * 100)));
                                return Source.REMOVE;
                            });
                        }
                        return true;
                    });
                } catch (Error e) {
                    failure = e.message;
                }
                Idle.add (() => {
                    done (failure);
                    return Source.REMOVE;
                });
                return null;
            });
        }
    }

    namespace Features {
        void add (MontageWindow w, string name, owned WindowActions.Handler handler) {
            var a = new SimpleAction (name, null);
            a.activate.connect (() => handler (w));
            w.add_action (a);
        }

        Clip? need_media_clip (MontageWindow w) {
            var c = w.ctl.primary;
            if (c == null || (c.kind != ClipKind.MEDIA && c.kind != ClipKind.MULTICAM)) {
                w.say (_("Select a video or audio clip first."));
                return null;
            }
            return c;
        }

        public void install (MontageWindow w) {
            add (w, "export", (w) => {
                if (w.ctl.seq.clips.size == 0) {
                    w.say (_("Add clips to the timeline before exporting."));
                    return;
                }
                new ExportDialog (w).present ();
            });
            add (w, "export-frame", (w) => {
                FileOps.save_dialog.begin (w, w.ctl.seq.name + "-" + Tc.format (w.ctl.playhead, w.ctl.seq.fps_n, w.ctl.seq.fps_d).replace (":", "-") + ".png", { FileOps.filter (_("PNG Image"), { "png" }) }, (o, r) => {
                    var f = FileOps.save_dialog.end (r);
                    if (f == null) return;
                    try {
                        var snap = w.project.clone ();
                        var renderer = new Renderer (snap, snap.sequence, 1, false);
                        var img = renderer.render (w.ctl.playhead);
                        renderer.close ();
                        ImageWriters.png (img, f.get_path (), false);
                        w.say (_("Saved the frame as %s.").printf (f.get_basename ()));
                    } catch (Error e) {
                        w.say (e.message);
                    }
                });
            });
            add (w, "export-srt", (w) => export_subtitles (w, "srt"));
            add (w, "export-vtt", (w) => export_subtitles (w, "vtt"));
            var timeline = new SimpleAction ("export-timeline", VariantType.STRING);
            timeline.activate.connect ((v) => export_timeline (w, v.get_string ()));
            w.add_action (timeline);
            add (w, "show-queue", (w) => QueueWindow.show (w));
            add (w, "print", (w) => StoryboardPrint.run.begin (w));
            add (w, "detect-scenes", (w) => {
                var c = need_media_clip (w);
                if (c == null) return;
                var m = w.project.find_media (c.media);
                string uri = m.uri;
                int64 start = c.in_point, end = c.in_point + c.source_span ();
                Gee.ArrayList<int64?>? cuts = null;
                double sensitivity = ((MontageApp) w.application).get_int ("scene-sensitivity", 60) / 100.0;
                Tasks.run (w, _("Detecting scenes"), (p) => { cuts = Analysis.detect_scenes (uri, start, end, sensitivity, p); }, (err) => {
                    if (err != null) {
                        w.say (err);
                        return;
                    }
                    var clip = w.ctl.seq.clip (c.id);
                    if (clip == null) return;
                    int made = 0;
                    var cut_times = new Gee.ArrayList<int64?> ();
                    foreach (var src in cuts) cut_times.add (clip.position + (src - clip.in_point));
                    w.project.begin_batch (_("Scene Cuts"));
                    foreach (var t in cut_times) {
                        try {
                            var ids = new Gee.ArrayList<string> ();
                            foreach (var l in w.ctl.seq.linked (clip)) ids.add (l.id);
                            var target = w.ctl.seq.clip_at (clip.track, t);
                            if (target == null) continue;
                            ids.clear ();
                            ids.add (target.id);
                            w.ctl.edits.split (t, ids);
                            made++;
                        } catch (Error e) {
                        }
                    }
                    w.project.end_batch ();
                    w.say (ngettext ("Found %d scene change and cut the clip there.", "Found %d scene changes and cut the clip there.", made).printf (made));
                });
            });
            add (w, "stabilize", (w) => {
                var c = need_media_clip (w);
                if (c == null) return;
                var m = w.project.find_media (c.media);
                if (m == null || !m.has_video) return;
                string uri = m.uri;
                int64 start = c.in_point, end = c.in_point + c.source_span ();
                string? data = null;
                Tasks.run (w, _("Analysing motion"), (p) => { data = Analysis.stabilize (uri, start, end, 0.5, p); }, (err) => {
                    if (err != null) {
                        w.say (err);
                        return;
                    }
                    var clip = w.ctl.seq.clip (c.id);
                    if (clip == null) return;
                    w.project.checkpoint (_("Stabilize"));
                    var e = clip.find_effect ("stabilize");
                    if (e == null) {
                        e = Catalog.find ("stabilize").create ();
                        clip.effects.insert (0, e);
                    }
                    e.params.texts["data"] = data;
                    w.project.commit ();
                    w.say (_("Stabilized. Adjust the smoothness in the Stabilizer effect."));
                });
            });
            add (w, "track-mask", (w) => {
                var c = need_media_clip (w);
                if (c == null) return;
                var mask = c.find_effect ("mask");
                if (mask == null) {
                    w.say (_("Add a Mask effect to the clip first, then track it."));
                    return;
                }
                var m = w.project.find_media (c.media);
                string uri = m.uri;
                double cx = 0, cy = 0;
                int n = 0;
                foreach (var pair in mask.params.text ("path").split (";")) {
                    var pt = pair.split (",");
                    if (pt.length < 2) continue;
                    cx += double.parse (pt[0]);
                    cy += double.parse (pt[1]);
                    n++;
                }
                if (n == 0) return;
                cx = cx / n / 100 * m.width;
                cy = cy / n / 100 * m.height;
                int64 start = c.source_time (int64.max (c.position, w.ctl.playhead)), end = c.in_point + c.source_span ();
                var times = new Gee.ArrayList<int64?> ();
                var xs = new Gee.ArrayList<double?> ();
                var ys = new Gee.ArrayList<double?> ();
                int width = m.width, height = m.height;
                double ox = cx, oy = cy;
                Tasks.run (w, _("Tracking the mask"), (p) => { Analysis.track_point (uri, start, end, ox, oy, 48, width, height, times, xs, ys, p); }, (err) => {
                    if (err != null) {
                        w.say (err);
                        return;
                    }
                    var clip = w.ctl.seq.clip (c.id);
                    var fx = clip != null ? clip.find_effect ("mask") : null;
                    if (fx == null) return;
                    w.project.checkpoint (_("Track Mask"));
                    var tx = fx.params.ensure ("track-x", 0);
                    var ty = fx.params.ensure ("track-y", 0);
                    for (int i = 0; i < times.size; i++) {
                        double sx = w.ctl.seq.width / (double) width;
                        double fit = double.min ((double) w.ctl.seq.width / width, (double) w.ctl.seq.height / height) / sx;
                        tx.set_key (times[i], (xs[i] - ox) * fit * sx);
                        ty.set_key (times[i], (ys[i] - oy) * fit * sx);
                    }
                    w.project.commit ();
                    w.say (ngettext ("Tracked the mask over %d frame.", "Tracked the mask over %d frames.", times.size).printf (times.size));
                });
            });
            add (w, "color-match", (w) => ColorPanel.match_selected (w));
            add (w, "sync-audio", (w) => SyncOps.sync_selected (w));
            add (w, "make-multicam", (w) => SyncOps.make_multicam (w));
            add (w, "auto-duck", (w) => {
                var snap = w.project.clone ();
                string sid = w.ctl.seq.id;
                Analysis.DuckPlan? plan = null;
                Tasks.run (w, _("Ducking music under dialogue"), (p) => { plan = Analysis.plan_duck (snap, sid, -15, p); }, (err) => {
                    if (err != null) {
                        w.say (err);
                        return;
                    }
                    int keys = Analysis.apply_duck (w.project, w.ctl.seq, plan);
                    w.say (ngettext ("Added %d volume keyframe to the music.", "Added %d volume keyframes to the music.", keys).printf (keys));
                });
            });
            add (w, "normalize", (w) => {
                var clips = w.ctl.selected_clips ();
                var audio = new Gee.ArrayList<Clip> ();
                foreach (var c in clips) {
                    var t = w.ctl.seq.track (c.track);
                    if (t != null && t.kind == TrackKind.AUDIO) audio.add (c);
                }
                if (audio.size == 0) {
                    w.project.checkpoint (_("Normalize Loudness"));
                    w.ctl.seq.normalize = true;
                    w.project.commit ();
                    w.say (_("The export will be normalized to %.0f LUFS. Select audio clips to match them to each other.").printf (w.ctl.seq.loudness_target));
                    return;
                }
                double target = w.ctl.seq.loudness_target;
                w.project.checkpoint (_("Normalize Clips"));
                int done = 0;
                foreach (var c in audio) {
                    try {
                        double lufs = Analysis.clip_loudness (w.project, w.ctl.seq, c);
                        if (lufs < -100) continue;
                        var vol = c.params.ensure ("volume", 0);
                        vol.keys.clear ();
                        vol.value = (target - lufs).clamp (-40, 24);
                        done++;
                    } catch (Error e) {
                        w.say (e.message);
                    }
                }
                w.project.commit ();
                w.say (ngettext ("Matched %d clip to %.0f LUFS.", "Matched %d clips to %.0f LUFS.", done).printf (done, target));
            });
            add (w, "transcribe", (w) => TranscribeOps.transcribe (w));
            add (w, "record", (w) => VoiceOver.start (w));
            add (w, "send-wave", (w) => WaveLink.send (w));
            add (w, "sound-in-wave", (w) => WaveRoundTrip.send (w));
            add (w, "export-review", (w) => Review.export_package (w));
        }

        void export_subtitles (MontageWindow w, string format) {
            var cues = Subtitles.all (w.ctl.seq);
            if (cues.size == 0) {
                w.say (_("The sequence has no captions."));
                return;
            }
            FileOps.save_dialog.begin (w, w.ctl.seq.name + "." + format, { FileOps.filter (format.up (), { format }) }, (o, r) => {
                var f = FileOps.save_dialog.end (r);
                if (f == null) return;
                try {
                    FileUtils.set_contents (f.get_path (), format == "srt" ? Subtitles.to_srt (cues) : Subtitles.to_vtt (cues));
                    w.say (_("Saved %d captions.").printf (cues.size));
                } catch (Error e) {
                    w.say (e.message);
                }
            });
        }

        void export_timeline (MontageWindow w, string format) {
            string ext = format == "xml" ? "xml" : format;
            FileOps.save_dialog.begin (w, w.ctl.seq.name + "." + ext, { FileOps.filter (ext.up (), { ext }) }, (o, r) => {
                var f = FileOps.save_dialog.end (r);
                if (f == null) return;
                try {
                    var p = w.project;
                    var s = w.ctl.seq;
                    switch (format) {
                        case "otio": FileUtils.set_contents (f.get_path (), Otio.write (p, s)); break;
                        case "otioz": Otio.write_bundle (p, s, f); break;
                        case "edl": FileUtils.set_contents (f.get_path (), Edl.write (p, s)); break;
                        case "xml": FileUtils.set_contents (f.get_path (), Fcp7.write (p, s)); break;
                        case "fcpxml": FileUtils.set_contents (f.get_path (), FcpXml.write (p, s)); break;
                        case "aaf": Aaf.write (p, s, f); break;
                    }
                    w.say (_("Exported the timeline as %s.").printf (f.get_basename ()));
                } catch (Error e) {
                    w.say (e.message);
                }
            });
        }
    }
}
