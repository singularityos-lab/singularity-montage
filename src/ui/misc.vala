using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Montage {
    namespace Panels {
        public void install (MontageWindow w) {
            w.inspector_panel.add_page ("color", _("Colour"), new ColorPanel (w));
            w.inspector_panel.add_page ("audio", _("Audio"), new MixerPanel (w));
            w.inspector_panel.add_page ("captions", _("Captions"), new CaptionsPanel (w));
            w.inspector_panel.add_page ("review", _("Review"), new ReviewPanel (w));
        }
    }

    namespace QueueWindow {
        public void show (MontageWindow w) {
            var dialog = new AppDialog (w.application, false, true);
            dialog.title = _("Export Queue");
            dialog.transient_for = w;
            dialog.set_default_size (520, 560);
            var box = new Box (Orientation.VERTICAL, 12);
            box.margin_start = box.margin_end = 16;
            box.margin_bottom = 16;
            var jobs = new PreferencesGroup ();
            jobs.title = _("Exports");
            var empty = new StatusPage ();
            empty.compact = true;
            empty.icon_name = "dev.sinty.montage";
            empty.title = _("No Exports");
            empty.description = _("Exports you add from the Export dialog run here in the background.");
            empty.vexpand = true;
            empty.valign = Align.CENTER;
            box.append (empty);
            box.append (jobs);
            var controls = new PreferencesGroup ();
            controls.title = _("Queue");
            var pause = new SwitchRow (_("Pause Queue"), _("Finish the current export, then wait"), w.ctl.queue.paused);
            pause.switch_btn.notify["active"].connect (() => w.ctl.queue.set_paused (pause.active));
            controls.add_row (pause);
            controls.add_row (Rows.action (_("Clear Finished"), _("Remove done, failed and cancelled exports from the list"), () => w.ctl.queue.clear_finished ()));
            var encoders = new ExpanderRow (_("Encoders"), _("What this system can encode"));
            var info = new Label ("");
            info.xalign = 0;
            info.wrap = true;
            info.selectable = true;
            info.add_css_class ("numeric");
            info.add_css_class ("caption");
            info.margin_start = info.margin_end = 12;
            info.margin_top = info.margin_bottom = 10;
            encoders.add_row (info);
            encoders.notify["expanded"].connect (() => {
                if (encoders.expanded && info.label == "") info.label = Encoders.report ();
            });
            controls.add_row (encoders);
            box.append (controls);
            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.child = box;
            dialog.content_box.append (scroll);
            ulong handler = 0;
            Delegates.Action refresh = () => {
                jobs.clear ();
                empty.visible = w.ctl.queue.jobs.size == 0;
                jobs.visible = !empty.visible;
                foreach (var item in w.ctl.queue.jobs) {
                    var job = item;
                    string state;
                    switch (job.state) {
                        case "running": state = _("Exporting %d%%").printf ((int) (job.fraction * 100)); break;
                        case "done": state = _("Done in %.1f s").printf (job.elapsed / 1e6); break;
                        case "failed": state = _("Failed"); break;
                        case "cancelled": state = _("Cancelled"); break;
                        default: state = _("Waiting"); break;
                    }
                    var detail = "%s, %s%s".printf (job.settings.preset.name, job.encoder_used != "" ? job.encoder_used : _("encoder chosen at start"), job.message != "" ? ". " + job.message : "");
                    var row = new ActionRow (job.title, "%s. %s".printf (state, detail));
                    if (job.state == "running") {
                        var bar = new ProgressBar ();
                        bar.fraction = job.fraction;
                        bar.valign = Align.CENTER;
                        bar.set_size_request (90, -1);
                        row.add_suffix (bar);
                    }
                    if (job.state == "queued" || job.state == "running") {
                        var cancel = new Button.from_icon_name ("process-stop-symbolic");
                        cancel.add_css_class ("flat");
                        cancel.valign = Align.CENTER;
                        cancel.tooltip_text = _("Cancel Export");
                        cancel.clicked.connect (() => {
                            if (job.state == "queued") job.state = "cancelled";
                            w.ctl.queue.remove (job);
                        });
                        row.add_suffix (cancel);
                    }
                    if (job.state == "done") {
                        var open = new Button.from_icon_name ("folder-open-symbolic");
                        open.add_css_class ("flat");
                        open.valign = Align.CENTER;
                        open.tooltip_text = _("Show in Files");
                        open.clicked.connect (() => {
                            try {
                                AppInfo.launch_default_for_uri (job.settings.output.get_parent ().get_uri (), null);
                            } catch (Error e) {
                                w.say (e.message);
                            }
                        });
                        row.add_suffix (open);
                    }
                    jobs.add_row (row);
                }
            };
            refresh ();
            handler = w.ctl.queue.changed.connect (() => refresh ());
            dialog.close_request.connect (() => {
                w.ctl.queue.disconnect (handler);
                return false;
            });
            dialog.present ();
        }
    }

    namespace StoryboardPrint {
        public async void run (MontageWindow w) {
            var snap = w.project.clone ();
            var seq = snap.sequence;
            var clips = new Gee.ArrayList<Clip> ();
            foreach (var t in seq.tracks_of (TrackKind.VIDEO)) clips.add_all (seq.on_track (t.id));
            clips.sort ((a, b) => a.position < b.position ? -1 : (a.position > b.position ? 1 : 0));
            var renderer = new Renderer (snap, seq, 320.0 / seq.width, false);
            var thumbs = new Gee.ArrayList<Cairo.ImageSurface> ();
            foreach (var c in clips) thumbs.add (Compose.to_surface (renderer.render (c.position + int64.min (c.duration / 2, Tc.SECOND))));
            renderer.close ();
            int per_page = 6;
            var source = new Singularity.Print.CallbackSource (seq.name, (format) => {
                return int.max (1, (clips.size + per_page - 1) / per_page) + (seq.markers.size > 0 || seq.comments.size > 0 ? 1 : 0);
            }, (cr, page, format) => {
                double x0 = format.margin_left, y0 = format.margin_top;
                double cw = format.content_width;
                cr.set_source_rgb (0, 0, 0);
                cr.select_font_face ("sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.BOLD);
                cr.set_font_size (14);
                cr.move_to (x0, y0 + 14);
                cr.show_text ("%s  %s".printf (seq.name, Tc.format (seq.duration, seq.fps_n, seq.fps_d)));
                cr.select_font_face ("sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
                int pages = int.max (1, (clips.size + per_page - 1) / per_page);
                if (page >= pages) {
                    double y = y0 + 40;
                    cr.set_font_size (12);
                    cr.move_to (x0, y);
                    cr.show_text (_("Markers and Comments"));
                    y += 20;
                    cr.set_font_size (9.5);
                    foreach (var m in seq.markers) {
                        cr.move_to (x0, y);
                        cr.show_text ("%s  %s  %s".printf (Tc.format (m.time, seq.fps_n, seq.fps_d), m.kind == "chapter" ? _("Chapter") : _("Marker"), m.name));
                        y += 14;
                    }
                    foreach (var c in seq.comments) {
                        cr.move_to (x0, y);
                        cr.show_text ("%s  %s: %s%s".printf (Tc.format (c.time, seq.fps_n, seq.fps_d), c.author, c.text, c.resolved ? "  (" + _("resolved") + ")" : ""));
                        y += 14;
                    }
                    return;
                }
                double cell_w = (cw - 20) / 2, img_h = cell_w * seq.height / seq.width;
                double cell_h = (format.content_height - 30) / 3;
                for (int i = 0; i < per_page; i++) {
                    int index = page * per_page + i;
                    if (index >= clips.size) break;
                    double x = x0 + (i % 2) * (cell_w + 20), y = y0 + 30 + (i / 2) * cell_h;
                    var thumb = thumbs[index];
                    double ih = double.min (img_h, cell_h - 40);
                    double iw = ih * seq.width / seq.height;
                    cr.save ();
                    cr.translate (x, y);
                    cr.scale (iw / thumb.get_width (), ih / thumb.get_height ());
                    cr.set_source_surface (thumb, 0, 0);
                    cr.paint ();
                    cr.restore ();
                    cr.set_source_rgb (0.3, 0.3, 0.3);
                    cr.rectangle (x, y, iw, ih);
                    cr.stroke ();
                    var c = clips[index];
                    cr.set_source_rgb (0, 0, 0);
                    cr.set_font_size (10);
                    cr.move_to (x, y + ih + 14);
                    cr.show_text ("%d. %s".printf (index + 1, snap.clip_label (c)));
                    cr.set_font_size (8.5);
                    cr.move_to (x, y + ih + 27);
                    cr.show_text ("%s - %s  (%s)".printf (Tc.format (c.position, seq.fps_n, seq.fps_d), Tc.format (c.end, seq.fps_n, seq.fps_d), Tc.format (c.duration, seq.fps_n, seq.fps_d)));
                }
            });
            try {
                yield Singularity.Print.run_source (w, source);
            } catch (Error e) {
                w.say (e.message);
            }
        }
    }

    namespace CompositionWatch {
        Gee.HashMap<string, FileMonitor>? monitors;

        public void watch (MontageWindow w, File f) {
            if (monitors == null) monitors = new Gee.HashMap<string, FileMonitor> ();
            if (monitors.has_key (f.get_uri ())) return;
            try {
                var monitor = f.monitor_file (FileMonitorFlags.WATCH_MOVES);
                monitor.changed.connect ((file, other, event) => {
                    if (event != FileMonitorEvent.CHANGES_DONE_HINT && event != FileMonitorEvent.RENAMED && event != FileMonitorEvent.MOVED_IN) return;
                    w.ctl.program.invalidate ();
                    w.ctl.prerender.schedule ();
                    w.say (_("%s was saved in Keyframe and is updated in the timeline.").printf (f.get_basename ()));
                });
                monitors[f.get_uri ()] = monitor;
            } catch (Error e) {
                warning ("watch %s: %s", f.get_uri (), e.message);
            }
        }
    }

    namespace NearbyImport {
        public async void run (MontageWindow w) {
            var client = Singularity.NearbyClient.get_default ();
            yield client.refresh ();
            var items = yield client.list ("GetReceivedFiles");
            var files = new Gee.ArrayList<File> ();
            foreach (var d in items) {
                string path = Singularity.NearbyClient.text_of (d, "path");
                if (path == "" || !Singularity.NearbyClient.flag_of (d, "exists")) continue;
                if (!Probe.is_media_name (path)) continue;
                files.add (File.new_for_path (path));
            }
            if (!client.running) {
                w.say (_("The phone service is not running. Pair your phone in Settings, Connected Devices."));
                return;
            }
            if (files.size == 0) {
                w.say (_("No videos, songs or pictures have been received from your phone yet. Send them with the share button on the phone."));
                return;
            }
            if (w.pages.visible_child_name != "workspace") w.new_project ();
            w.project.checkpoint (_("New Bin"));
            var bin = new Bin (_("From Phone"));
            w.project.bins.add (bin);
            w.project.commit ();
            yield Importing.import_files (w, files, bin.id);
        }
    }

    namespace Shortcuts {
        public void show (MontageWindow w) {
            var app = (MontageApp) w.application;
            var dialog = new AppDialog (w.application, false, true);
            dialog.title = _("Keyboard Shortcuts");
            dialog.transient_for = w;
            dialog.set_default_size (520, 640);
            var map = Keymap.current (app);
            var keys = new Gee.ArrayList<string> ();
            keys.add_all (map.keys);
            keys.sort ();
            var group = new PreferencesGroup ();
            foreach (var k in keys) {
                uint key;
                Gdk.ModifierType mods;
                Gtk.accelerator_parse (map[k], out key, out mods);
                string[] words = k.replace ("win.", "").replace ("app.", "").replace ("::", " ").replace ("-", " ").split (" ");
                for (int i = 0; i < words.length; i++) if (words[i] != "") words[i] = words[i].substring (0, 1).up () + words[i].substring (1);
                var row = new ActionRow (string.joinv (" ", words));
                var label = new Label (Gtk.accelerator_get_label (key, mods));
                label.add_css_class ("dim-label");
                label.add_css_class ("numeric");
                row.add_suffix (label);
                group.add_row (row);
            }
            group.title = _("Shortcuts");
            group.description = _("The key layout follows the Keyboard Layout setting of Montage in Settings. Personal changes go in %s as JSON, for example {\"win.split\": \"<Control>b\"}.").printf (Keymap.custom_file ());
            var box = new Box (Orientation.VERTICAL, 12);
            box.margin_start = box.margin_end = 16;
            box.margin_bottom = 16;
            box.append (group);
            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.child = box;
            dialog.content_box.append (scroll);
            dialog.present ();
        }
    }
}
