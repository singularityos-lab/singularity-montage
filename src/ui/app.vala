using Gtk;

namespace Singularity.Apps.Montage {
    public class MontageApp : Singularity.Application {
        public GLib.Settings? settings;
        public bool simple_mode;
        public string? from_videos;

        public MontageApp () {
            Object (application_id: "dev.sinty.montage", flags: ApplicationFlags.HANDLES_OPEN | ApplicationFlags.HANDLES_COMMAND_LINE);
            add_main_option ("simple", 0, OptionFlags.NONE, OptionArg.NONE, _("Open media in the simple editor"), null);
            add_main_option ("edits", 0, OptionFlags.NONE, OptionArg.STRING, _("Cuts to keep, as start-end pairs in seconds, from the Videos trim editor"), "LIST");
            var schema = SettingsSchemaSource.get_default ()?.lookup ("dev.sinty.montage", true);
            if (schema != null) settings = new GLib.Settings ("dev.sinty.montage");
        }

        public bool get_bool (string key, bool fallback) {
            return settings != null ? settings.get_boolean (key) : fallback;
        }

        public int get_int (string key, int fallback) {
            return settings != null ? settings.get_int (key) : fallback;
        }

        public string get_str (string key, string fallback) {
            return settings != null ? settings.get_string (key) : fallback;
        }

        public override int command_line (ApplicationCommandLine cmd) {
            var options = cmd.get_options_dict ();
            simple_mode = options.contains ("simple");
            from_videos = null;
            if (options.contains ("edits")) {
                string? e = null;
                options.lookup ("edits", "s", out e);
                from_videos = e;
                simple_mode = true;
            }
            string[] args = cmd.get_arguments ();
            var files = new Gee.ArrayList<File> ();
            for (int i = 1; i < args.length; i++) {
                if (args[i].has_prefix ("-")) continue;
                files.add (cmd.create_file_for_arg (args[i]));
            }
            if (files.size == 0) activate ();
            else open (files.to_array (), "");
            return 0;
        }

        protected override void startup () {
            base.startup ();
            about_version = "0.2.0";
            about_license = _("GNU General Public License, version 3 only");
            if (!get_bool ("hardware-decoding", true) || Encoders.hardware_disabled ()) Encoders.set_hardware_decoding (false);
            Singularity.Application.add_app_css (Style.CSS);
            var new_action = new SimpleAction ("new-window", null);
            new_action.activate.connect (() => new MontageWindow (this).present ());
            add_action (new_action);
            var quit = new SimpleAction ("quit", null);
            quit.activate.connect (() => {
                var windows = new Gee.ArrayList<Gtk.Window> ();
                foreach (var w in get_windows ()) windows.add (w);
                foreach (var w in windows) w.close ();
            });
            add_action (quit);
            var settings_action = new SimpleAction ("settings", null);
            settings_action.activate.connect (() => {
                try {
                    Singularity.Shell.ShellService shell = GLib.Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings ("dev.sinty.montage");
                } catch (Error e) {
                    warning ("Failed to open settings: %s", e.message);
                }
            });
            add_action (settings_action);
            build_menu ();
            Keymap.install (this);
        }

        static GLib.Menu section (string[,] items) {
            var m = new GLib.Menu ();
            for (int i = 0; i < items.length[0]; i++) m.append (items[i, 0], items[i, 1]);
            return m;
        }

        static GLib.Menu submenu (string label, GLib.Menu sub) {
            var m = new GLib.Menu ();
            m.append_submenu (label, sub);
            return m;
        }

        void build_menu () {
            var menu = new GLib.Menu ();
            var file = new GLib.Menu ();
            file.append_section (null, section ({
                { _("New Project"), "win.new-project" }, { _("New Sequence…"), "win.new-sequence" }, { _("Open…"), "win.open" }, { _("New Window"), "app.new-window" }
            }));
            file.append_section (null, section ({ { _("Save"), "win.save" }, { _("Save As…"), "win.save-as" } }));
            file.append_section (null, submenu (_("Import"), section ({
                { _("Media…"), "win.import" }, { _("Folder…"), "win.import-folder" }, { _("From Camera or Card"), "win.import-card" },
                { _("From Phone (Nearby)"), "win.import-nearby" }, { _("Subtitles (SRT, WebVTT)…"), "win.import-subtitles" },
                { _("Timeline (OTIO, EDL, FCP XML, Premiere, AAF, Kdenlive)…"), "win.import-timeline" },
                { _("Keyframe Composition…"), "win.import-composition" }
            })));
            file.append_section (null, submenu (_("Export"), section ({
                { _("Media…"), "win.export" }, { _("Current Frame as PNG…"), "win.export-frame" },
                { _("Subtitles as SRT…"), "win.export-srt" }, { _("Subtitles as WebVTT…"), "win.export-vtt" },
                { _("OpenTimelineIO…"), "win.export-timeline::otio" }, { _("OpenTimelineIO Bundle (OTIOZ)…"), "win.export-timeline::otioz" },
                { _("EDL CMX3600…"), "win.export-timeline::edl" }, { _("Final Cut Pro XML…"), "win.export-timeline::xml" },
                { _("FCPXML…"), "win.export-timeline::fcpxml" }, { _("AAF…"), "win.export-timeline::aaf" },
                { _("Review Package…"), "win.export-review" }
            })));
            file.append_section (null, section ({ { _("Export Queue"), "win.show-queue" } }));
            file.append_section (null, section ({ { _("Print Storyboard…"), "win.print" } }));
            file.append_section (null, section ({ { _("Close Project"), "win.close-project" }, { _("Close Window"), "win.close" }, { _("Quit"), "app.quit" } }));
            menu.append_submenu (_("File"), file);
            var edit = new GLib.Menu ();
            edit.append_section (null, section ({ { _("Undo"), "win.undo" }, { _("Redo"), "win.redo" } }));
            edit.append_section (null, section ({
                { _("Split at Playhead"), "win.split" }, { _("Delete"), "win.lift" }, { _("Ripple Delete"), "win.ripple-delete" },
                { _("Lift In to Out"), "win.lift-range" }, { _("Extract In to Out"), "win.extract-range" },
                { _("Close Gaps on Track"), "win.close-gaps" }
            }));
            edit.append_section (null, section ({
                { _("Link"), "win.link" }, { _("Unlink"), "win.unlink" }, { _("Nest"), "win.nest" }, { _("Enable or Disable Clip"), "win.toggle-clip" },
                { _("Speed…"), "win.speed" }, { _("Move into Sync"), "win.resync" }
            }));
            edit.append_section (null, section ({ { _("Keyboard Shortcuts"), "win.shortcuts" }, { _("Settings"), "app.settings" } }));
            menu.append_submenu (_("Edit"), edit);
            var clip = new GLib.Menu ();
            clip.append_section (null, section ({
                { _("Insert from Source"), "win.insert" }, { _("Overwrite from Source"), "win.overwrite" },
                { _("Add Title"), "win.add-title" }, { _("Add Colour Matte"), "win.add-color" }, { _("Add Adjustment Layer"), "win.add-adjustment" }
            }));
            clip.append_section (null, section ({
                { _("Add Default Transition"), "win.add-transition" }, { _("Stabilize"), "win.stabilize" }, { _("Track Mask"), "win.track-mask" },
                { _("Match Colour to Reference"), "win.color-match" }, { _("Detect Scenes"), "win.detect-scenes" }
            }));
            clip.append_section (null, section ({
                { _("Synchronize by Audio"), "win.sync-audio" }, { _("Create Multicamera Source"), "win.make-multicam" },
                { _("Transcribe"), "win.transcribe" }, { _("Automatic Ducking"), "win.auto-duck" }, { _("Normalize Loudness"), "win.normalize" },
                { _("Record Voiceover"), "win.record" }, { _("Edit Clip in Wave"), "win.send-wave" }, { _("Edit Sequence Sound in Wave"), "win.sound-in-wave" }
            }));
            clip.append_section (null, section ({ { _("Generate Proxies"), "win.make-proxies" } }));
            menu.append_submenu (_("Clip"), clip);
            var view = new GLib.Menu ();
            view.append_section (null, section ({
                { _("Editing"), "win.workspace::edit" }, { _("Colour"), "win.workspace::color" }, { _("Audio"), "win.workspace::audio" },
                { _("Captions"), "win.workspace::captions" }, { _("Review"), "win.workspace::review" }
            }));
            view.append_section (null, section ({ { _("Project Panel"), "win.toggle-sidebar" }, { _("Inspector"), "win.toggle-inspector" }, { _("Simple Mode"), "win.simple-mode" } }));
            view.append_section (null, section ({ { _("Zoom In"), "win.zoom-in" }, { _("Zoom Out"), "win.zoom-out" }, { _("Fit Timeline"), "win.zoom-fit" } }));
            view.append_section (null, section ({ { _("Snapping"), "win.snapping" }, { _("Linked Selection"), "win.linked" }, { _("Use Proxies"), "win.use-proxies" } }));
            menu.append_submenu (_("View"), view);
            var mark = new GLib.Menu ();
            mark.append_section (null, section ({
                { _("Mark In"), "win.mark-in" }, { _("Mark Out"), "win.mark-out" }, { _("Clear In and Out"), "win.clear-marks" }
            }));
            mark.append_section (null, section ({
                { _("Add Marker"), "win.add-marker" }, { _("Add Chapter Marker"), "win.add-chapter" },
                { _("Next Edit"), "win.next-edit" }, { _("Previous Edit"), "win.previous-edit" }
            }));
            menu.append_submenu (_("Markers"), mark);
            set_menubar (menu);
        }

        public override void activate () {
            var w = get_active_window () as MontageWindow;
            if (w == null) w = new MontageWindow (this);
            w.present ();
            TestScript.maybe_run (w);
        }

        public override void open (File[] files, string hint) {
            var media = new Gee.ArrayList<File> ();
            foreach (var f in files) {
                string name = f.get_basename () ?? "";
                if (name.has_suffix (".montage") || name.has_suffix (".mtgproj")) {
                    var w = new MontageWindow (this);
                    w.present ();
                    w.open_file (f);
                } else {
                    media.add (f);
                }
            }
            if (media.size > 0) {
                var w = get_active_window () as MontageWindow;
                if (w == null) w = new MontageWindow (this);
                w.present ();
                w.open_media (media, simple_mode, from_videos);
            }
            var any = get_active_window () as MontageWindow;
            if (any != null) TestScript.maybe_run (any);
        }
    }
}

int main (string[] args) {
    Gst.init (ref args);
    Intl.setlocale (LocaleCategory.ALL, "");
    return new Singularity.Apps.Montage.MontageApp ().run (args);
}
