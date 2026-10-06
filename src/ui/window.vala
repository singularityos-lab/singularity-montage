using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Montage {
    public class MontageWindow : Singularity.Widgets.Window {
        public Project project = new Project ();
        public Controller ctl;
        public Session session;
        public Stack pages = new Stack ();
        public WelcomePage welcome = new WelcomePage ();
        public MediaBin media_panel;
        public Viewer source_view = new Viewer ();
        public Viewer program_view = new Viewer ();
        public TimelineView timeline;
        public Inspector inspector;
        public InspectorPanel inspector_panel = new InspectorPanel (360);
        public Stack inspector_stack;
        public Revealer inspector_revealer = new Revealer ();
        public Stack monitor_stack = new Stack ();
        public Label status = new Label ("");
        public Label source_time = new Label ("00:00:00:00");
        public Label program_time = new Label ("00:00:00:00");
        public Box queue_box = new Box (Orientation.HORIZONTAL, 8);
        public Paned vertical = new Paned (Orientation.VERTICAL);
        bool fitting;
        bool user_sized;
        public ProgressBar queue_progress = new ProgressBar ();
        public Label queue_label = new Label ("");
        public SidebarTabs workspace_switch;
        public EditRibbon ribbon;
        public Gee.HashMap<string, ToggleButton> tool_buttons = new Gee.HashMap<string, ToggleButton> ();
        public Gee.ArrayList<Widget> workspace_bubbles = new Gee.ArrayList<Widget> ();
        public Box source_pane;
        public Box monitors_paned;
        Box program_pane;
        public bool simple;
        Box recovery_box = new Box (Orientation.VERTICAL, 6);
        bool closing_confirmed;

        public MontageWindow (MontageApp app) {
            Object (application: app, title: _("Montage"), default_width: 1500, default_height: 920);
            ctl = new Controller (project);
            session = new Session (project);
            session.versions = app.get_int ("auto-save-versions", 5);
            project.use_proxies = app.get_bool ("use-proxies", true);
            ctl.program.preview_scale = app.get_str ("preview-resolution", "half") == "full" ? 1.0 : (app.get_str ("preview-resolution", "half") == "quarter" ? 0.25 : 0.5);
            ctl.prerender.scale = ctl.program.preview_scale;
            ctl.prerender.enabled = app.get_bool ("background-render", true);
            ctl.snapping = app.get_bool ("snapping", true);
            timeline = new TimelineView (ctl);
            inspector = new Inspector (ctl);
            media_panel = new MediaBin (ctl);
            inspector_stack = inspector_panel.stack;
            workspace_switch = inspector_panel.tabs;
            pages.transition_type = StackTransitionType.CROSSFADE;
            ribbon = new EditRibbon (this);
            pages.add_named (build_welcome (), "welcome");
            pages.add_named (build_workspace (), "workspace");
            set_content (pages);
            set_sidebar (media_panel);
            build_bubbles ();
            WindowActions.install (this);
            connect_signals ();
            show_welcome ();
            close_request.connect (on_close);
        }

        Widget build_welcome () {
            welcome.app_icon_name = "dev.sinty.montage";
            welcome.title = _("Montage");
            welcome.subtitle = _("Edit video on a multitrack timeline, then export for the web, social or a master");
            welcome.add_action ("document-new", _("New Project"), _("Start with an empty 1080p timeline"), () => new_project ());
            welcome.add_action ("document-open", _("Open Project"), _("Continue a Montage project or open an OTIO, EDL or FCP XML timeline"), () => activate_action ("win.open", null));
            welcome.add_action ("folder-videos", _("Import Media"), _("Create a project from video, audio and pictures"), () => {
                new_project ();
                activate_action ("win.import", null);
            });
            welcome.add_action ("video-trim", _("Quick Edit"), _("Trim one video with the simple editor"), () => {
                new_project ();
                set_simple (true);
                activate_action ("win.import", null);
            });
            var orphans = Session.orphans ();
            if (orphans.size > 0) {
                var title = new Label (_("Unsaved Projects"));
                title.add_css_class ("title-3");
                title.halign = Align.START;
                recovery_box.append (title);
                foreach (var item in orphans) {
                    var rec = item;
                    var row = new Button.with_label (_("Restore %s from %s").printf (rec.name, new DateTime.from_unix_local (rec.time).format ("%x %X")));
                    row.add_css_class ("flat");
                    row.clicked.connect (() => {
                        try {
                            var p = session.recover (rec);
                            project.replace_with (p);
                            session.mark_modified ();
                            show_workspace ();
                            say (_("Recovered the unsaved project. Save it to keep the changes."));
                            row.visible = false;
                        } catch (Error e) {
                            say (e.message);
                        }
                    });
                    recovery_box.append (row);
                }
                welcome.set_extra_widget (recovery_box);
            }
            return welcome;
        }

        Widget monitor (string title, Viewer view, Playback pb, bool source) {
            var card = new Box (Orientation.VERTICAL, 0);
            card.add_css_class ("montage-monitor");
            card.hexpand = true;
            view.caption = title;
            view.timecode = "00:00:00:00";
            card.append (view);
            var strip = new ControlStrip (6, 6);
            strip.margin_start = strip.margin_end = 4;
            strip.add_spacer ();
            if (source) {
                var mark_in = strip.add_text_button (_("In"), tip (_("Mark the Source In Point"), "win.mark-in"));
                mark_in.clicked.connect (() => mark_source (true));
                var mark_out = strip.add_text_button (_("Out"), tip (_("Mark the Source Out Point"), "win.mark-out"));
                mark_out.clicked.connect (() => mark_source (false));
            }
            var back = strip.add_icon_button ("media-seek-backward-symbolic", _("Previous Frame"));
            back.clicked.connect (() => {
                pb.pause ();
                pb.seek (pb.position - pb.sequence.frame);
            });
            var play = strip.add_icon_button ("media-playback-start-symbolic", tip (_("Play or Pause"), "win.play-pause"));
            pb.state_changed.connect (() => play.icon_name = pb.playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic");
            play.clicked.connect (() => pb.toggle ());
            var forward = strip.add_icon_button ("media-seek-forward-symbolic", _("Next Frame"));
            forward.clicked.connect (() => {
                pb.pause ();
                pb.seek (pb.position + pb.sequence.frame);
            });
            if (source) {
                var insert = strip.add_icon_button ("list-add-symbolic", tip (_("Insert into the Timeline at the Playhead"), "win.insert"));
                insert.clicked.connect (() => activate_action ("win.insert", null));
                var overwrite = strip.add_icon_button ("edit-paste-symbolic", tip (_("Overwrite the Timeline at the Playhead"), "win.overwrite"));
                overwrite.clicked.connect (() => activate_action ("win.overwrite", null));
            }
            strip.add_spacer ();
            card.append (strip);
            return card;
        }

        public void mark_source (bool start) {
            var m = ctl.source_media;
            if (m == null) return;
            project.checkpoint (start ? _("Mark In") : _("Mark Out"));
            if (start) m.mark_in = ctl.source.position;
            else m.mark_out = ctl.source.position + ctl.source.sequence.frame;
            if (m.mark_out >= 0 && m.mark_in >= m.mark_out) m.mark_out = -1;
            project.commit ();
            source_view.label_left = "";
            say (_("Source marked %s to %s").printf (Tc.clock (int64.max (0, m.mark_in)), Tc.clock (m.mark_out >= 0 ? m.mark_out : m.duration)));
        }

        Widget build_workspace () {
            var root = new Box (Orientation.VERTICAL, 0);
            source_pane = (Box) monitor (_("Source"), source_view, ctl.source, true);
            program_pane = (Box) monitor (_("Program"), program_view, ctl.program, false);
            monitors_paned = new Box (Orientation.HORIZONTAL, 12);
            monitors_paned.homogeneous = true;
            monitors_paned.append (source_pane);
            monitors_paned.append (program_pane);
            monitors_paned.margin_start = monitors_paned.margin_end = 12;
            monitors_paned.margin_top = 12;
            monitors_paned.margin_bottom = 8;
            monitors_paned.hexpand = true;
            monitors_paned.vexpand = true;
            var upper = new Box (Orientation.VERTICAL, 0);
            upper.append (monitors_paned);
            inspector_panel.add_page ("edit", _("Edit"), inspector);
            Panels.install (this);
            inspector_revealer.transition_type = RevealerTransitionType.SLIDE_LEFT;
            inspector_revealer.reveal_child = true;
            inspector_revealer.child = inspector_panel;
            vertical.start_child = upper;
            vertical.resize_start_child = true;
            vertical.shrink_start_child = false;
            vertical.shrink_end_child = false;
            var lower = new Box (Orientation.VERTICAL, 0);
            lower.add_css_class ("montage-timeline-area");
            lower.append (timeline);
            timeline.vexpand = true;
            vertical.end_child = lower;
            vertical.position = 470;
            vertical.vexpand = true;
            vertical.hexpand = true;
            vertical.notify["position"].connect (() => {
                if (!fitting) user_sized = true;
            });
            program_view.width_changed.connect (() => schedule_fit ());
            source_view.width_changed.connect (() => schedule_fit ());
            var column = new Box (Orientation.VERTICAL, 0);
            column.hexpand = true;
            apply_view_edge (column);
            column.append (ribbon);
            column.append (vertical);
            var body = new Box (Orientation.HORIZONTAL, 0);
            body.vexpand = true;
            body.append (column);
            body.append (inspector_revealer);
            root.append (body);
            var footer = new Box (Orientation.HORIZONTAL, 10);
            footer.add_css_class ("montage-status");
            status.xalign = 0;
            status.hexpand = true;
            status.ellipsize = Pango.EllipsizeMode.END;
            status.add_css_class ("caption");
            status.add_css_class ("dim-label");
            footer.append (status);
            queue_progress.valign = Align.CENTER;
            queue_progress.set_size_request (160, -1);
            queue_label.add_css_class ("caption");
            queue_box.append (queue_label);
            queue_box.append (queue_progress);
            queue_box.visible = false;
            footer.append (queue_box);
            root.append (footer);
            return root;
        }

        uint fit_source;

        void schedule_fit () {
            if (fit_source != 0) return;
            fit_source = Idle.add (() => {
                fit_source = 0;
                fit_monitors ();
                return Source.REMOVE;
            });
        }

        public void fit_monitors () {
            if (user_sized) return;
            int total = vertical.get_height ();
            int width = program_view.get_width ();
            if (total <= 0 || width <= 0) return;
            double aspect = ctl.seq.height > 0 ? (double) ctl.seq.width / ctl.seq.height : 16.0 / 9.0;
            int strip = 44;
            int chrome = monitors_paned.margin_top + monitors_paned.margin_bottom + strip;
            int wanted = (int) (width / aspect) + chrome;
            int position = wanted.clamp (220, int.max (220, total - 300));
            if ((vertical.position - position).abs () < 2) return;
            fitting = true;
            vertical.position = position;
            fitting = false;
        }

        Gee.HashMap<string, string>? keys;

        string tip (string label, string action) {
            if (keys == null) keys = Keymap.current ((MontageApp) application);
            if (!keys.has_key (action)) return label;
            uint key;
            Gdk.ModifierType mods;
            Gtk.accelerator_parse (keys[action], out key, out mods);
            if (key == 0) return label;
            return "%s (%s)".printf (label, Gtk.accelerator_get_label (key, mods));
        }

        void build_bubbles () {
            workspace_bubbles.add (add_bubble_icon ("go-previous-symbolic", _("Close Project"), () => activate_action ("win.close-project", null)));
            workspace_bubbles.add (add_bubble_icon ("sidebar-show-symbolic", tip (_("Project Panel"), "win.toggle-sidebar"), () => set_sidebar_visible (!get_sidebar_visible ())));
            workspace_bubbles.add (add_bubble_icon ("document-save-symbolic", tip (_("Save Project"), "win.save"), () => activate_action ("win.save", null)));
            workspace_bubbles.add (add_bubble_icon ("edit-undo-symbolic", tip (_("Undo"), "win.undo"), () => activate_action ("win.undo", null)));
            workspace_bubbles.add (add_bubble_icon ("edit-redo-symbolic", tip (_("Redo"), "win.redo"), () => activate_action ("win.redo", null)));
            ribbon.attach (this);
            workspace_bubbles.add (ribbon.tabs);
            workspace_bubbles.add (add_bubble_icon ("sidebar-show-right-symbolic", tip (_("Inspector"), "win.toggle-inspector"), () => inspector_revealer.reveal_child = !inspector_revealer.reveal_child));
            workspace_bubbles.add (add_bubble_suggested (_("Export…"), () => activate_action ("win.export", null)));
        }

        void connect_signals () {
            ctl.status.connect (say);
            timeline.edit_failed.connect (say);
            timeline.context_menu.connect (show_context_menu);
            ctl.program.frame.connect ((f) => {
                program_view.show_texture (f.texture);
                program_view.aspect = (double) ctl.seq.width / ctl.seq.height;
            });
            ctl.program.position_changed.connect ((t) => {
                program_time.label = Tc.format (t, ctl.seq.fps_n, ctl.seq.fps_d);
                program_view.timecode = program_time.label;
            });
            ctl.source.frame.connect ((f) => source_view.show_texture (f.texture));
            ctl.source.position_changed.connect ((t) => {
                var s = ctl.source.sequence;
                source_time.label = Tc.format (t, s.fps_n, s.fps_d);
                source_view.timecode = source_time.label;
            });
            media_panel.media_activated.connect ((m) => {
                ctl.show_source (m);
                inspector.show_media (m);
                ctl.select (null);
            });
            media_panel.request_import.connect (() => activate_action ("win.import", null));
            timeline.trim_preview.connect ((left, right, active) => {
                if (!active) {
                    program_view.show_compare (null);
                    ctl.program.seek (ctl.program.position);
                    return;
                }
                TrimPreview.show (this, left, right);
            });
            project.changed.connect (() => {
                update_title ();
                if (ctl.seq.duration == 0) program_view.show_texture (null);
            });
            session.notify["modified"].connect (update_title);
            ctl.queue.changed.connect (update_queue);
            ctl.queue.job_finished.connect ((job, ok, err) => {
                if (ok) say (_("Exported %s with %s. %s").printf (job.title, job.encoder_used, job.message));
                else say (_("Export of %s failed: %s").printf (job.title, err ?? ""));
                send_notification (ok ? _("Export finished") : _("Export failed"), ok ? job.title : (err ?? job.title));
            });
            ctl.proxies.finished.connect ((id, ok, err) => {
                var m = project.find_media (id);
                say (ok ? _("Proxy ready for %s").printf (m != null ? m.name : "") : _("Proxy failed: %s").printf (err ?? ""));
            });
            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((key, code, mods) => {
                if (pages.visible_child_name != "workspace") return false;
                if (key == Gdk.Key.f && (mods & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    focus_search ();
                    return true;
                }
                if (focus_widget is Editable || focus_widget is TextView) return false;
                if (key >= Gdk.Key.@1 && key <= Gdk.Key.@9 && (mods & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK)) == 0) {
                    var c = ctl.primary;
                    if (c != null && c.kind == ClipKind.MULTICAM) {
                        MulticamOps.cut (ctl, c, ctl.program.position, (int) (key - Gdk.Key.@1));
                        return true;
                    }
                }
                return false;
            });
            ((Widget) this).add_controller (keys);
        }

        void send_notification (string title, string body) {
            var n = new GLib.Notification (title);
            n.set_body (body);
            application.send_notification ("export", n);
        }

        void update_queue () {
            var q = ctl.queue;
            queue_box.visible = q.pending > 0;
            if (q.current != null) {
                queue_progress.fraction = q.current.fraction;
                queue_label.label = ngettext ("Exporting %s, %d in queue", "Exporting %s, %d in queue", q.pending).printf (q.current.title, q.pending);
            }
        }

        public void say (string message) {
            status.label = message;
        }

        void show_context_menu (double x, double y) {
            var menu = new ContextMenu (timeline);
            menu.add_item (_("Split at Playhead"), "edit-cut-symbolic", () => activate_action ("win.split", null));
            menu.add_item (_("Ripple Delete"), "edit-delete-symbolic", () => activate_action ("win.ripple-delete", null));
            menu.add_separator ();
            menu.add_item (_("Speed…"), "media-seek-forward-symbolic", () => activate_action ("win.speed", null));
            menu.add_item (_("Enable or Disable"), "object-select-symbolic", () => activate_action ("win.toggle-clip", null));
            menu.add_item (_("Link"), "insert-link-symbolic", () => activate_action ("win.link", null));
            menu.add_item (_("Unlink"), "edit-clear-symbolic", () => activate_action ("win.unlink", null));
            menu.add_item (_("Nest"), "folder-symbolic", () => activate_action ("win.nest", null));
            menu.add_item (_("Move into Sync"), "emblem-synchronizing-symbolic", () => activate_action ("win.resync", null));
            menu.add_separator ();
            menu.add_item (_("Add Default Transition"), "list-add-symbolic", () => activate_action ("win.add-transition", null));
            menu.add_item (_("Stabilize"), "camera-video-symbolic", () => activate_action ("win.stabilize", null));
            menu.add_item (_("Detect Scenes"), "edit-find-symbolic", () => activate_action ("win.detect-scenes", null));
            menu.add_item (_("Edit in Wave"), "audio-x-generic-symbolic", () => activate_action ("win.send-wave", null));
            menu.add_separator ();
            menu.add_item (_("Delete"), "user-trash-symbolic", () => activate_action ("win.lift", null), "destructive-action");
            menu.pointing_to = Gdk.Rectangle () { x = (int) x, y = (int) y, width = 1, height = 1 };
            menu.popup ();
        }

        public void focus_search () {
            if (pages.visible_child_name != "workspace") return;
            set_sidebar_visible (true);
            media_panel.focus_search ();
        }

        public void update_title () {
            if (pages.visible_child_name != "workspace") {
                title = _("Montage");
                return;
            }
            string name = session.origin != null ? (session.origin.get_basename () ?? _("Untitled")) : _("Untitled");
            title = (session.modified ? "* " : "") + name + " - " + ctl.seq.name;
        }

        public void show_welcome () {
            pages.visible_child_name = "welcome";
            set_sidebar_visible (false);
            foreach (var b in workspace_bubbles) b.visible = false;
            update_title ();
        }

        public void show_workspace () {
            pages.visible_child_name = "workspace";
            set_sidebar_visible (!simple);
            foreach (var b in workspace_bubbles) b.visible = true;
            update_title ();
            ctl.program.seek (ctl.program.position);
        }

        public void new_project () {
            var p = new Project ();
            var app = (MontageApp) application;
            var s = p.sequence;
            string res = app.get_str ("default-resolution", "1920x1080");
            var parts = res.split ("x");
            if (parts.length == 2) {
                s.width = int.parse (parts[0]).clamp (16, 16384);
                s.height = int.parse (parts[1]).clamp (16, 16384);
            }
            int fps = app.get_int ("default-frame-rate", 30);
            if (fps == 2997) {
                s.fps_n = 30000;
                s.fps_d = 1001;
            } else if (fps == 2398) {
                s.fps_n = 24000;
                s.fps_d = 1001;
            } else {
                s.fps_n = fps;
                s.fps_d = 1;
            }
            p.use_proxies = project.use_proxies;
            project.replace_with (p);
            session.opened (null);
            show_workspace ();
            say (_("New project with a %dx%d sequence at %.3g frames per second.").printf (s.width, s.height, (double) s.fps_n / s.fps_d));
        }

        public void open_file (File file) {
            try {
                string name = file.get_basename () ?? "";
                Project p;
                if (name.has_suffix (".montage")) p = NativeFormat.load (file);
                else p = Importers.read (file);
                project.replace_with (p);
                if (name.has_suffix (".montage")) session.opened (file);
                else session.opened (null);
                SharedProject.refresh_locks (project, session.origin);
                show_workspace ();
                timeline.zoom_fit ();
                Recent.add (file);
                int missing = 0;
                foreach (var m in project.media) if (m.offline) missing++;
                say (missing > 0 ? ngettext ("Opened %s. %d media file is offline.", "Opened %s. %d media files are offline.", missing).printf (name, missing) : _("Opened %s.").printf (name));
            } catch (Error e) {
                say (_("Could not open %s: %s").printf (file.get_basename (), e.message));
            }
        }

        public void open_media (Gee.List<File> files, bool simple_mode, string? edits) {
            if (pages.visible_child_name != "workspace") new_project ();
            if (simple_mode) set_simple (true);
            Importing.import_files.begin (this, files, null, (o, r) => {
                Importing.import_files.end (r);
                if (edits != null) SimpleMode.apply_edits (this, edits);
            });
        }

        public void set_simple (bool value) {
            simple = value;
            source_pane.visible = !value;
            inspector_revealer.reveal_child = !value;
            if (pages.visible_child_name == "workspace") set_sidebar_visible (!value);
            say (value ? _("Simple mode: cut, trim and export. Open the View menu to bring back the panels.") : _("All panels are shown."));
        }

        bool on_close () {
            if (closing_confirmed || !session.modified) {
                ctl.queue.cancel_all ();
                ctl.shutdown ();
                session.close ();
                return false;
            }
            var dialog = new ConfirmDialog (application, _("Save Changes?"), "dialog-warning",
                _("The project has unsaved changes."), _("Discard"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dialog.transient_for = this;
            dialog.set_secondary (_("Save"), ConfirmDialog.ActionStyle.SUGGESTED);
            dialog.response.connect ((response) => {
                if (response == ConfirmDialog.Response.CANCEL) return;
                if (response == ConfirmDialog.Response.SECONDARY) {
                    FileOps.save.begin (this, false, (o, r) => {
                        if (FileOps.save.end (r)) {
                            closing_confirmed = true;
                            close ();
                        }
                    });
                } else {
                    session.discard_recovery ();
                    closing_confirmed = true;
                    close ();
                }
            });
            dialog.present ();
            return true;
        }
    }
}
