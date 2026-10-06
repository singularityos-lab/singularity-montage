using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Montage {
    namespace SyncOps {
        public void sync_selected (MontageWindow w) {
            var clips = new Gee.ArrayList<Clip> ();
            var seen_links = new Gee.HashSet<string> ();
            foreach (var c in w.ctl.selected_clips ()) {
                if (c.kind != ClipKind.MEDIA) continue;
                var m = w.project.find_media (c.media);
                if (m == null || !m.has_audio) continue;
                string key = c.link != "" ? c.link : c.id;
                if (!seen_links.add (key)) continue;
                clips.add (c);
            }
            if (clips.size < 2) {
                w.say (_("Select at least two clips that were recorded at the same time."));
                return;
            }
            clips.sort ((a, b) => w.ctl.seq.track_index (a.track) - w.ctl.seq.track_index (b.track));
            var reference = clips[0];
            string ref_uri = w.project.find_media (reference.media).uri;
            var uris = new Gee.ArrayList<string> ();
            for (int i = 1; i < clips.size; i++) uris.add (w.project.find_media (clips[i].media).uri);
            var offsets = new Gee.ArrayList<int64?> ();
            var confidences = new Gee.ArrayList<double?> ();
            Tasks.run (w, _("Synchronizing by audio"), (p) => {
                for (int i = 0; i < uris.size; i++) {
                    double conf;
                    offsets.add (Analysis.audio_offset (ref_uri, uris[i], 30 * Tc.SECOND, out conf));
                    confidences.add (conf);
                    p ((double) (i + 1) / uris.size);
                }
            }, (err) => {
                if (err != null) {
                    w.say (err);
                    return;
                }
                w.project.checkpoint (_("Synchronize by Audio"));
                var seq = w.ctl.seq;
                var r = seq.clip (reference.id);
                int moved = 0;
                for (int i = 1; i < clips.size; i++) {
                    var c = seq.clip (clips[i].id);
                    if (c == null || r == null) continue;
                    int64 target = seq.snap (r.position - r.in_point + offsets[i - 1] + c.in_point);
                    int64 delta = target - c.position;
                    foreach (var l in seq.linked (c)) {
                        l.position += delta;
                        if (l.position < 0) {
                            w.ctl.edits.trim_head_raw (l, -l.position);
                        }
                    }
                    moved++;
                }
                w.project.commit ();
                var report = new StringBuilder ();
                for (int i = 0; i < offsets.size; i++) report.append ("%s%+.3f s (%.0f%%)".printf (i > 0 ? ", " : "", (double) offsets[i] / Tc.SECOND, confidences[i] * 100));
                w.say (_("Synchronized %d clips to %s: %s").printf (moved, w.project.clip_label (reference), report.str));
            });
        }

        public void make_multicam (MontageWindow w) {
            var media = new Gee.ArrayList<MediaItem> ();
            foreach (var c in w.ctl.selected_clips ()) {
                var m = w.project.find_media (c.media);
                if (m != null && m.has_video && !media.contains (m)) media.add (m);
            }
            if (media.size < 2) {
                w.say (_("Select clips from at least two cameras on the timeline."));
                return;
            }
            var uris = new Gee.ArrayList<string> ();
            foreach (var m in media) uris.add (m.uri);
            var offsets = new Gee.ArrayList<int64?> ();
            Tasks.run (w, _("Synchronizing cameras by audio"), (p) => {
                offsets.add (0);
                for (int i = 1; i < uris.size; i++) {
                    double conf;
                    offsets.add (media[i].has_audio && media[0].has_audio ? Analysis.audio_offset (uris[0], uris[i], 60 * Tc.SECOND, out conf) : 0);
                    p ((double) i / uris.size);
                }
            }, (err) => {
                if (err != null) {
                    w.say (err);
                    return;
                }
                var mc = new MediaItem ();
                mc.kind = "multicam";
                mc.name = _("Multicamera %d").printf (w.project.media.size + 1);
                int64 min_off = 0, end = 0;
                foreach (var o in offsets) min_off = int64.min (min_off, o);
                for (int i = 0; i < media.size; i++) {
                    int64 off = offsets[i] - min_off;
                    mc.angles.add (new MulticamAngle (media[i].id, media[i].name, off));
                    end = int64.max (end, off + media[i].duration);
                }
                mc.duration = end;
                mc.has_video = true;
                mc.has_audio = media[0].has_audio;
                mc.width = media[0].width;
                mc.height = media[0].height;
                mc.fps_n = media[0].fps_n;
                mc.fps_d = media[0].fps_d;
                w.project.checkpoint (_("Create Multicamera Source"));
                w.project.media.add (mc);
                w.project.media_changed ();
                w.project.commit ();
                var clips = w.ctl.edits.make_media_clips (mc, 0, mc.duration, w.ctl.target_track (TrackKind.VIDEO), mc.has_audio ? w.ctl.target_track (TrackKind.AUDIO) : null);
                try {
                    int64 at = w.ctl.seq.duration;
                    w.ctl.edits.place (clips, at, false);
                    w.ctl.select (clips[0]);
                    w.ctl.seek (at);
                    MulticamView.open (w, clips[0]);
                    w.say (_("Created %s with %d angles. Play and press 1 to %d to cut between cameras.").printf (mc.name, media.size, media.size));
                } catch (Error e) {
                    w.say (e.message);
                }
            });
        }
    }

    namespace MulticamView {
        uint timer;
        Gee.HashMap<string, VideoReader>? readers;

        public void open (MontageWindow w, Clip c) {
            var m = w.project.find_media (c.media);
            if (m == null) return;
            if (readers == null) readers = new Gee.HashMap<string, VideoReader> ();
            w.source_view.grid_clicked.connect ((index) => {
                var clip = w.ctl.primary;
                if (clip != null && clip.kind == ClipKind.MULTICAM) MulticamOps.cut (w.ctl, clip, w.ctl.playhead, index);
            });
            if (timer != 0) Source.remove (timer);
            timer = Timeout.add (180, () => {
                var clip = w.ctl.primary;
                if (clip == null || clip.kind != ClipKind.MULTICAM) {
                    w.source_view.show_grid (null, -1);
                    timer = 0;
                    return Source.REMOVE;
                }
                var mm = w.project.find_media (clip.media);
                if (mm == null) return Source.CONTINUE;
                int64 t = w.ctl.playhead.clamp (clip.position, clip.end - 1);
                int64 src = clip.source_time (t);
                var textures = new Gee.ArrayList<Gdk.Texture?> ();
                for (int i = 0; i < mm.angles.size; i++) {
                    var am = w.project.find_media (mm.angles[i].media_id);
                    Gdk.Texture? tex = null;
                    if (am != null && am.has_video) {
                        string key = am.uri;
                        var reader = readers[key];
                        if (reader == null) {
                            int h = 180, wd = ((int) (180.0 * am.width / int.max (1, am.height))) & ~1;
                            reader = new VideoReader (am.playback_uri (true), wd, h);
                            readers[key] = reader;
                        }
                        try {
                            var f = reader.frame_at (int64.max (0, src - mm.angles[i].offset));
                            if (f != null) tex = new Gdk.MemoryTexture (f.width, f.height, Gdk.MemoryFormat.R8G8B8A8, new Bytes (f.bytes), f.width * 4);
                        } catch (Error e) {
                        }
                    }
                    textures.add (tex);
                }
                w.source_view.show_grid (textures, clip.angle_at (t - clip.position));
                return Source.CONTINUE;
            });
        }
    }

    namespace VoiceOver {
        Gst.Pipeline? pipeline;

        public void start (MontageWindow w) {
            if (pipeline != null) return;
            var dir = File.new_for_path (Path.build_filename (Environment.get_user_special_dir (UserDirectory.MUSIC) ?? Environment.get_home_dir (), "Montage Recordings"));
            try {
                if (w.session.origin != null) dir = w.session.origin.get_parent ().get_child ("Recordings");
                if (!dir.query_exists ()) dir.make_directory_with_parents ();
            } catch (Error e) {
                w.say (e.message);
                return;
            }
            var file = dir.get_child ("Voiceover %s.wav".printf (new DateTime.now_local ().format ("%Y-%m-%d %H-%M-%S")));
            int64 start = w.ctl.playhead;
            var dialog = new AppDialog (w.application, false, false);
            dialog.title = _("Voiceover");
            dialog.transient_for = w;
            dialog.set_default_size (340, 220);
            var box = new Box (Orientation.VERTICAL, 12);
            box.margin_start = box.margin_end = 18;
            box.margin_bottom = 18;
            var big = new Label ("3");
            big.add_css_class ("title-1");
            var hint = new Label (_("Recording starts after the countdown at %s.").printf (Tc.clock (start)));
            hint.wrap = true;
            hint.add_css_class ("dim-label");
            var stop = new Button.with_label (_("Stop Recording"));
            stop.add_css_class ("destructive-action");
            stop.add_css_class ("pill");
            stop.sensitive = false;
            var cancel = dialog.add_cancel_button (_("Cancel"));
            box.append (big);
            box.append (hint);
            box.append (stop);
            box.append (cancel);
            dialog.content_box.append (box);
            dialog.present ();
            int count = 3;
            bool cancelled = false;
            cancel.clicked.connect (() => {
                cancelled = true;
                finish (w, null, start, dialog);
            });
            Timeout.add (1000, () => {
                if (cancelled) return Source.REMOVE;
                count--;
                if (count > 0) {
                    big.label = "%d".printf (count);
                    return Source.CONTINUE;
                }
                string source = Environment.get_variable ("MONTAGE_AUDIO_SOURCE") ?? "autoaudiosrc";
                try {
                    pipeline = (Gst.Pipeline) Gst.parse_launch ("%s ! audioconvert ! audioresample ! audio/x-raw,rate=48000,channels=2 ! wavenc ! filesink location=\"%s\"".printf (source, file.get_path ()));
                    pipeline.set_state (Gst.State.PLAYING);
                } catch (Error e) {
                    w.say (_("No microphone is available: %s").printf (e.message));
                    finish (w, null, start, dialog);
                    return Source.REMOVE;
                }
                big.label = _("Recording");
                stop.sensitive = true;
                cancel.sensitive = false;
                w.ctl.program.set_volume (0);
                w.ctl.program.play (1);
                return Source.REMOVE;
            });
            stop.clicked.connect (() => finish (w, file, start, dialog));
        }

        void finish (MontageWindow w, File? file, int64 start, AppDialog dialog) {
            w.ctl.program.pause ();
            w.ctl.program.set_volume (1);
            if (pipeline != null) {
                pipeline.send_event (new Gst.Event.eos ());
                pipeline.get_bus ().timed_pop_filtered (3 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR);
                pipeline.set_state (Gst.State.NULL);
                pipeline = null;
            }
            dialog.close_dialog ();
            if (file == null || !file.query_exists ()) return;
            try {
                var m = Probe.probe (file.get_uri ());
                w.project.checkpoint (_("Record Voiceover"));
                var bin = (Bin?) null;
                foreach (var b in w.project.bins) if (b.name == _("Voiceover")) bin = b;
                if (bin == null) {
                    bin = new Bin (_("Voiceover"));
                    w.project.bins.add (bin);
                }
                m.bin = bin.id;
                w.project.media.add (m);
                w.project.media_changed ();
                w.project.commit ();
                string? track = null;
                foreach (var t in w.ctl.seq.tracks_of (TrackKind.AUDIO)) {
                    bool free = true;
                    foreach (var c in w.ctl.seq.on_track (t.id)) if (c.position < start + m.duration && c.end > start) free = false;
                    if (free && !t.locked) {
                        track = t.id;
                        break;
                    }
                }
                if (track == null) track = w.ctl.edits.add_track (TrackKind.AUDIO).id;
                var clips = w.ctl.edits.make_media_clips (m, 0, m.duration, null, track);
                foreach (var c in clips) c.role = "dialogue";
                w.ctl.edits.place (clips, start, false);
                w.say (_("Recorded %s of voiceover.").printf (Tc.clock (m.duration)));
            } catch (Error e) {
                w.say (e.message);
            }
        }
    }

    namespace WaveLink {
        Gee.HashMap<string, FileMonitor>? monitors;

        public void send (MontageWindow w) {
            var c = w.ctl.primary;
            var t = c != null ? w.ctl.seq.track (c.track) : null;
            if (c == null || t == null || t.kind != TrackKind.AUDIO || c.media == "") {
                w.say (_("Select an audio clip to edit in Wave."));
                return;
            }
            var m = w.project.find_media (c.media);
            if (m == null) return;
            int64 handle = 2 * Tc.SECOND;
            int64 from = int64.max (0, c.in_point - handle);
            int64 to = int64.min (m.duration, c.in_point + c.source_span () + handle);
            var dir = w.session.origin != null ? w.session.origin.get_parent ().get_child ("Audio Edits") : File.new_for_path (Path.build_filename (Environment.get_user_special_dir (UserDirectory.MUSIC) ?? Environment.get_home_dir (), "Montage Audio Edits"));
            string clip_id = c.id;
            string name = (w.project.clip_label (c).replace ("/", "-")) + " (Wave).wav";
            string uri = m.uri;
            File? target = null;
            Tasks.run (w, _("Preparing the clip for Wave"), (p) => {
                if (!dir.query_exists ()) dir.make_directory_with_parents ();
                target = dir.get_child (name);
                var reader = new AudioReader (uri, 48000);
                int64 s0 = from * 48000 / Tc.SECOND, s1 = to * 48000 / Tc.SECOND;
                var pipeline = (Gst.Pipeline) Gst.parse_launch ("appsrc name=a format=time ! audioconvert ! audio/x-raw,format=S24LE ! wavenc ! filesink location=\"%s\"".printf (target.get_path ()));
                var src = (Gst.App.Src) pipeline.get_by_name ("a");
                src.caps = Gst.Caps.from_string ("audio/x-raw,format=F32LE,layout=interleaved,rate=48000,channels=2,channel-mask=(bitmask)0x3");
                pipeline.set_state (Gst.State.PLAYING);
                var buf = new float[48000 * 2];
                for (int64 s = s0; s < s1; s += 48000) {
                    int n = (int) int64.min (48000, s1 - s);
                    reader.read (s, n, buf);
                    uint8[] bytes = new uint8[n * 8];
                    Memory.copy (bytes, buf, bytes.length);
                    var gb = new Gst.Buffer.wrapped ((owned) bytes);
                    gb.pts = (s - s0) * Gst.SECOND / 48000;
                    gb.duration = (int64) n * Gst.SECOND / 48000;
                    src.push_buffer (gb);
                    p ((double) (s - s0) / (s1 - s0));
                }
                src.end_of_stream ();
                pipeline.get_bus ().timed_pop_filtered (30 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR);
                pipeline.set_state (Gst.State.NULL);
                reader.close ();
            }, (err) => {
                if (err != null) {
                    w.say (err);
                    return;
                }
                relink (w, clip_id, target, c.in_point - from);
                watch (w, clip_id, target, c.in_point - from);
                launch (w, target);
            });
        }

        void launch (MontageWindow w, File f) {
            try {
                var wave = new GLib.DesktopAppInfo ("dev.sinty.wave.desktop");
                if (wave != null) {
                    var list = new List<File> ();
                    list.append (f);
                    wave.launch (list, null);
                    w.say (_("Opened in Wave. Save there and the clip updates here."));
                    return;
                }
                var app = AppInfo.get_default_for_type ("audio/x-wav", false);
                if (app == null) {
                    w.say (_("No audio editor is installed. The file is in %s.").printf (f.get_parent ().get_path ()));
                    return;
                }
                var list = new List<File> ();
                list.append (f);
                app.launch (list, null);
                w.say (_("Opened in %s. Save there and the clip updates here.").printf (app.get_display_name ()));
            } catch (Error e) {
                w.say (e.message);
            }
        }

        public void relink (MontageWindow w, string clip_id, File f, int64 offset) {
            try {
                var m = Probe.probe (f.get_uri ());
                var c = w.ctl.seq.clip (clip_id);
                if (c == null) return;
                w.project.checkpoint (_("Relink to Wave Edit"));
                var existing = w.project.media_by_uri (m.uri);
                if (existing != null) {
                    existing.duration = m.duration;
                    m = existing;
                } else {
                    w.project.media.add (m);
                }
                foreach (var l in w.ctl.seq.linked (c)) {
                    var lt = w.ctl.seq.track (l.track);
                    if (lt == null || lt.kind != TrackKind.AUDIO || l.id != c.id) continue;
                    l.media = m.id;
                    l.in_point = offset;
                    l.params.texts["wave-file"] = f.get_uri ();
                }
                w.project.media_changed ();
                w.project.commit ();
            } catch (Error e) {
                w.say (e.message);
            }
        }

        void watch (MontageWindow w, string clip_id, File f, int64 offset) {
            if (monitors == null) monitors = new Gee.HashMap<string, FileMonitor> ();
            try {
                var monitor = f.monitor_file (FileMonitorFlags.WATCH_MOVES);
                monitor.changed.connect ((file, other, event) => {
                    if (event != FileMonitorEvent.CHANGES_DONE_HINT && event != FileMonitorEvent.MOVED_IN && event != FileMonitorEvent.RENAMED) return;
                    w.ctl.media_cache.ready ();
                    w.ctl.program.invalidate ();
                    w.say (_("The Wave edit of the clip was saved and is now used in the timeline."));
                });
                monitors[clip_id] = monitor;
            } catch (Error e) {
            }
        }
    }
}
