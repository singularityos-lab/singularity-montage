using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Montage {
    public class EditRibbon : ContextRibbon {
        MontageWindow win;
        public RibbonToggle snap_toggle;
        public RibbonToggle link_toggle;
        public RibbonToggle proxies_toggle;

        public EditRibbon (MontageWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.win = win;
            build_edit (add_context ("edit", _("Edit"), "edit-cut-symbolic"));
            build_clip (add_context ("clip", _("Clip"), "video-x-generic-symbolic"));
            build_insert (add_context ("insert", _("Insert"), "list-add-symbolic"));
            build_markers (add_context ("markers", _("Markers"), "bookmark-new-symbolic"));
            build_view (add_context ("view", _("View"), "view-reveal-symbolic"));
        }

        RibbonButton act (RibbonContext c, string icon, string label, string action, string? tooltip = null, bool in_compact = false) {
            var b = c.add_button (icon, label, tooltip, action);
            b.label_in_compact = in_compact;
            return b;
        }

        RibbonMenu menu (RibbonContext c, string? icon, string label, string[,] items) {
            var model = new GLib.Menu ();
            for (int i = 0; i < items.length[0]; i++) model.append (items[i, 0], items[i, 1]);
            var m = c.add_menu (icon, label);
            m.label_in_compact = true;
            m.set_menu_model (model);
            return m;
        }

        void build_edit (RibbonContext c) {
            string[,] tools = {
                { "select", _("Selection"), "edit-select-all-symbolic" },
                { "ripple", _("Ripple Trim"), "go-last-symbolic" },
                { "roll", _("Rolling Edit"), "object-flip-horizontal-symbolic" },
                { "slip", _("Slip"), "view-continuous-symbolic" },
                { "slide", _("Slide"), "media-playlist-shuffle-symbolic" },
                { "razor", _("Razor"), "edit-cut-symbolic" }
            };
            ToggleButton? group = null;
            for (int i = 0; i < tools.length[0]; i++) {
                string id = tools[i, 0];
                string name = tools[i, 1];
                var t = c.add_toggle (tools[i, 2], name);
                t.shortcut = accel ("win.tool::" + id);
                if (group != null) t.button.group = group;
                else group = t.button;
                t.active = id == "select";
                t.toggled.connect ((on) => {
                    if (!on) return;
                    win.ctl.tool = id;
                    win.say (_("%s tool").printf (name));
                });
                win.tool_buttons[id] = t.button;
            }
            c.add_separator ();
            snap_toggle = c.add_toggle ("view-grid-symbolic", _("Snapping"));
            snap_toggle.shortcut = accel ("win.snapping");
            snap_toggle.active = win.ctl.snapping;
            snap_toggle.toggled.connect ((on) => win.ctl.snapping = on);
            link_toggle = c.add_toggle ("insert-link-symbolic", _("Linked Selection"));
            link_toggle.shortcut = accel ("win.linked");
            link_toggle.active = win.ctl.linked;
            link_toggle.toggled.connect ((on) => win.ctl.linked = on);
            c.add_separator ();
            act (c, "edit-cut-symbolic", _("Split"), "win.split", _("Split at Playhead"));
            act (c, "edit-delete-symbolic", _("Delete"), "win.lift");
            act (c, "edit-clear-all-symbolic", _("Ripple Delete"), "win.ripple-delete");
            act (c, "format-justify-fill-symbolic", _("Close Gaps"), "win.close-gaps", _("Close Gaps on Track"));
            menu (c, null, _("In to Out"), { { _("Lift In to Out"), "win.lift-range" }, { _("Extract In to Out"), "win.extract-range" } });
            c.add_separator ();
            act (c, "list-add-symbolic", _("Insert"), "win.insert", _("Insert from Source at the Playhead"));
            act (c, "edit-paste-symbolic", _("Overwrite"), "win.overwrite", _("Overwrite from Source at the Playhead"));
            act (c, "go-last-symbolic", _("Append"), "win.append", _("Append from Source to the End"));
        }

        void build_clip (RibbonContext c) {
            act (c, "media-skip-forward-symbolic", _("Speed"), "win.speed", _("Change the Clip Speed"), true);
            act (c, "object-select-symbolic", _("Enable or Disable"), "win.toggle-clip", _("Enable or Disable Clip"));
            act (c, "insert-link-symbolic", _("Link"), "win.link");
            act (c, "edit-clear-symbolic", _("Unlink"), "win.unlink");
            act (c, "folder-symbolic", _("Nest"), "win.nest");
            act (c, "emblem-synchronizing-symbolic", _("Move into Sync"), "win.resync");
            c.add_separator ();
            act (c, "view-dual-symbolic", _("Transition"), "win.add-transition", _("Add Default Transition"), true);
            act (c, "camera-video-symbolic", _("Stabilize"), "win.stabilize");
            act (c, "applications-graphics-symbolic", _("Track Mask"), "win.track-mask");
            act (c, "preferences-color-symbolic", _("Match Colour"), "win.color-match", _("Match Colour to Reference"));
            act (c, "edit-find-symbolic", _("Detect Scenes"), "win.detect-scenes");
            c.add_separator ();
            menu (c, "audio-x-generic-symbolic", _("Sound"), {
                { _("Synchronize by Audio"), "win.sync-audio" }, { _("Create Multicamera Source"), "win.make-multicam" },
                { _("Transcribe"), "win.transcribe" }, { _("Automatic Ducking"), "win.auto-duck" }, { _("Normalize Loudness"), "win.normalize" },
                { _("Edit Clip in Wave"), "win.send-wave" }, { _("Edit Sequence Sound in Wave"), "win.sound-in-wave" }
            });
            act (c, "system-run-symbolic", _("Generate Proxies"), "win.make-proxies");
        }

        void build_insert (RibbonContext c) {
            act (c, "insert-text-symbolic", _("Title"), "win.add-title", _("Add Title"), true);
            act (c, "color-select-symbolic", _("Colour Matte"), "win.add-color", _("Add Colour Matte"));
            act (c, "image-x-generic-symbolic", _("Adjustment Layer"), "win.add-adjustment", _("Add Adjustment Layer"));
            c.add_separator ();
            menu (c, "view-paged-symbolic", _("Track"), {
                { _("Video Track"), "win.add-track::video" }, { _("Audio Track"), "win.add-track::audio" },
                { _("Subtitle Track"), "win.add-track::subtitle" }, { _("Audio Bus"), "win.add-bus" }
            });
            c.add_separator ();
            act (c, "audio-input-microphone-symbolic", _("Voiceover"), "win.record", _("Record Voiceover"), true);
            act (c, "document-open-symbolic", _("Media"), "win.import", _("Import Media"), true);
        }

        void build_markers (RibbonContext c) {
            act (c, "go-first-symbolic", _("Mark In"), "win.mark-in");
            act (c, "go-last-symbolic", _("Mark Out"), "win.mark-out");
            act (c, "edit-clear-symbolic", _("Clear In and Out"), "win.clear-marks");
            c.add_separator ();
            act (c, "bookmark-new-symbolic", _("Marker"), "win.add-marker", _("Add Marker"), true);
            act (c, "starred-symbolic", _("Chapter"), "win.add-chapter", _("Add Chapter Marker"), true);
            c.add_separator ();
            act (c, "media-skip-backward-symbolic", _("Previous Edit"), "win.previous-edit");
            act (c, "media-skip-forward-symbolic", _("Next Edit"), "win.next-edit");
        }

        void build_view (RibbonContext c) {
            act (c, "zoom-out-symbolic", _("Zoom Out"), "win.zoom-out");
            act (c, "zoom-fit-best-symbolic", _("Fit Timeline"), "win.zoom-fit");
            act (c, "zoom-in-symbolic", _("Zoom In"), "win.zoom-in");
            c.add_separator ();
            proxies_toggle = c.add_toggle ("video-x-generic-symbolic", _("Use Proxies"));
            proxies_toggle.active = win.project.use_proxies;
            proxies_toggle.toggled.connect ((on) => {
                if (win.project.use_proxies != on) win.activate_action ("win.use-proxies", null);
            });
            act (c, "view-reveal-symbolic", _("Simple Mode"), "win.simple-mode");
        }

        string? accel (string detailed) {
            var app = win.application;
            if (app == null) return null;
            string[] accels = app.get_accels_for_action (detailed);
            if (accels.length == 0) return null;
            uint key;
            Gdk.ModifierType mods;
            if (!Gtk.accelerator_parse (accels[0], out key, out mods) || key == 0) return null;
            return Gtk.accelerator_get_label (key, mods);
        }

        public void sync () {
            if (snap_toggle.active != win.ctl.snapping) snap_toggle.active = win.ctl.snapping;
            if (link_toggle.active != win.ctl.linked) link_toggle.active = win.ctl.linked;
            if (proxies_toggle.active != win.project.use_proxies) proxies_toggle.active = win.project.use_proxies;
        }
    }
}
