using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Montage {
    namespace Review {
        public void export_package (MontageWindow w) {
            var dialog = new FileDialog ();
            dialog.select_folder.begin (w, null, (o, r) => {
                try {
                    var folder = dialog.select_folder.end (r);
                    var seq = w.ctl.seq;
                    var dir = folder.get_child ("%s Review".printf (seq.name));
                    if (!dir.query_exists ()) dir.make_directory ();
                    string? codec = Encoders.pick ("h264", false);
                    var preset = Presets.find (codec != null ? "web-720" : "webm-1080").copy ();
                    preset.width = 1280;
                    preset.height = (int) (1280.0 * seq.height / seq.width) & ~1;
                    preset.vbitrate = 3000;
                    var settings = new ExportSettings ();
                    settings.preset = preset;
                    settings.output = dir.get_child ("review." + preset.extension);
                    settings.subtitles = "burn";
                    settings.sequence_id = seq.id;
                    settings.hardware = false;
                    FileUtils.set_contents (dir.get_child ("index.html").get_path (), html (seq, "review." + preset.extension));
                    FileUtils.set_contents (dir.get_child ("review-comments.json").get_path (), comments_json (seq));
                    var job = new ExportJob (w.project.clone (), settings);
                    w.ctl.queue.add (job);
                    w.say (_("Rendering the review copy into %s. Send the folder or share it with an online account.").printf (dir.get_basename ()));
                    ReviewPanel.last_package = dir;
                } catch (Error e) {
                    if (!(e is DialogError.DISMISSED)) w.say (e.message);
                }
            });
        }

        public async void share (MontageWindow w, File dir) {
            try {
                var account = Singularity.Accounts.CloudShare.default_account ();
                if (account == null) {
                    w.say (_("Add an online account with file storage in Settings to share reviews."));
                    return;
                }
                foreach (var name in new string[] { "review.mp4", "review.webm" }) {
                    var f = dir.get_child (name);
                    if (f.query_exists ()) yield Singularity.Accounts.CloudShare.share_file (f, account, Singularity.Accounts.LinkAccess.VIEW);
                }
                var shared = yield Singularity.Accounts.CloudShare.share_file (dir.get_child ("index.html"), account, Singularity.Accounts.LinkAccess.VIEW);
                var clipboard = w.get_clipboard ();
                clipboard.set_text (shared.link.url);
                w.say (_("Review link copied: %s").printf (shared.link.url));
            } catch (Error e) {
                w.say (_("Could not share the review: %s").printf (e.message));
            }
        }
    }

    public class ReviewPanel : Box {
        MontageWindow w;
        Controller ctl;
        PreferencesGroup comment_group;
        PreferencesGroup marker_group;
        PreferencesGroup lock_group;
        EntryRow comment_entry;
        public static File? last_package;

        public ReviewPanel (MontageWindow w) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.w = w;
            ctl = w.ctl;
            spacing = 12;
            var cg = new PreferencesGroup ();
            cg.title = _("Comments");
            comment_group = cg;
            var entry = new EntryRow (_("Comment at the Playhead"));
            entry.entry_activated.connect (() => {
                if (entry.text.strip () == "") return;
                ctl.project.checkpoint (_("Add Comment"));
                var c = new ReviewComment ();
                c.time = ctl.playhead;
                c.text = entry.text.strip ();
                c.author = Environment.get_real_name () != "Unknown" ? Environment.get_real_name () : Environment.get_user_name ();
                c.created = new DateTime.now_utc ().to_unix ();
                ctl.seq.comments.add (c);
                ctl.seq.comments.sort ((a, b) => a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
                ctl.project.commit ();
                entry.text = "";
            });
            cg.add_row (entry);
            comment_entry = entry;
            append (cg);
            var pg = new PreferencesGroup ();
            pg.title = _("Review Package");
            pg.description = _("Send the cut with its comments to a reviewer, then bring their replies back.");
            pg.add_row (Rows.action (_("Make Review Package…"), null, () => w.activate_action ("win.export-review", null)));
            pg.add_row (Rows.action (_("Share Link"), _("Upload the last review package to your online account and copy the link"), () => {
                if (last_package == null) {
                    w.say (_("Make a review package first."));
                    return;
                }
                Review.share.begin (w, last_package);
            }));
            pg.add_row (Rows.action (_("Import Replies…"), null, () => {
                FileOps.open_dialog.begin (w, { FileOps.filter (_("Review Comments"), { "json" }) }, (o, r) => {
                    var f = FileOps.open_dialog.end (r);
                    if (f == null) return;
                    try {
                        uint8[] data;
                        f.load_contents (null, out data, null);
                        int n = Review.merge (ctl.project, ctl.seq, (string) data);
                        w.say (ngettext ("Imported %d comment or reply.", "Imported %d comments or replies.", n).printf (n));
                    } catch (Error e) {
                        w.say (e.message);
                    }
                });
            }));
            append (pg);
            var mg = new PreferencesGroup ();
            mg.title = _("Markers and Chapters");
            marker_group = mg;
            append (mg);
            var sg = new PreferencesGroup ();
            sg.title = _("Shared Project");
            lock_group = sg;
            append (sg);
            ctl.project.changed.connect (() => {
                if (get_mapped ()) rebuild ();
            });
            map.connect (rebuild);
        }

        void rebuild () {
            comment_group.clear ();
            comment_group.add_row (comment_entry);
            foreach (var item in ctl.seq.comments) {
                var c = item;
                var exp = new ExpanderRow ("%s  %s".printf (Tc.format (c.time, ctl.seq.fps_n, ctl.seq.fps_d), c.author), c.text);
                var resolved = new SwitchRow (_("Resolved"), null, c.resolved);
                resolved.switch_btn.notify["active"].connect (() => {
                    if (c.resolved == resolved.active) return;
                    ctl.project.checkpoint (_("Resolve Comment"));
                    c.resolved = resolved.active;
                    ctl.project.commit ();
                });
                exp.add_row (resolved);
                foreach (var r in c.replies) exp.add_row (new ActionRow (r.author, r.text));
                var reply = new EntryRow (_("Reply"));
                reply.entry_activated.connect (() => {
                    if (reply.text.strip () == "") return;
                    ctl.project.checkpoint (_("Reply"));
                    c.replies.add (new ReviewReply (Environment.get_user_name (), reply.text.strip (), new DateTime.now_utc ().to_unix ()));
                    ctl.project.commit ();
                });
                exp.add_row (reply);
                exp.add_row (Rows.action (_("Go to Comment"), null, () => ctl.seek (c.time)));
                comment_group.add_row (exp);
            }
            marker_group.clear ();
            foreach (var item in ctl.seq.markers) {
                var m = item;
                var row = new EntryRow (Tc.format (m.time, ctl.seq.fps_n, ctl.seq.fps_d) + (m.kind == "chapter" ? "  " + _("Chapter") : ""));
                row.text = m.name;
                row.entry_activated.connect (() => {
                    ctl.project.checkpoint (_("Rename Marker"));
                    m.name = row.text;
                    ctl.project.commit ();
                });
                var chapter = new ToggleButton.with_label (_("Chapter"));
                chapter.active = m.kind == "chapter";
                chapter.valign = Align.CENTER;
                chapter.toggled.connect (() => {
                    ctl.project.checkpoint (_("Marker Kind"));
                    m.kind = chapter.active ? "chapter" : "comment";
                    ctl.project.commit ();
                });
                row.add_suffix (chapter);
                var del = new Button.from_icon_name ("user-trash-symbolic");
                del.add_css_class ("flat");
                del.valign = Align.CENTER;
                del.clicked.connect (() => {
                    ctl.project.checkpoint (_("Delete Marker"));
                    ctl.seq.markers.remove (m);
                    ctl.project.commit ();
                });
                row.add_suffix (del);
                marker_group.add_row (row);
            }
            marker_group.description = ctl.seq.markers.size == 0 ? _("Add markers and chapters from the Markers menu.") : "";
            lock_group.clear ();
            var origin = w.session.origin;
            if (origin == null) {
                lock_group.description = _("Save the project in a shared folder. Each person then locks the sequence they edit, and saving merges the sequences changed by others.");
                return;
            }
            lock_group.description = _("Each person locks the sequence they edit; saving merges the sequences changed by others.");
            foreach (var s in ctl.project.sequences) {
                var seq = s;
                var holder = SharedProject.holder (origin, seq.id);
                string state = holder == null ? _("Free") : (SharedProject.is_mine (holder) ? _("Locked by you") : _("Locked by %s").printf (holder));
                var row = new ActionRow (seq.name, state);
                var toggle = new Button.with_label (holder != null && SharedProject.is_mine (holder) ? _("Release") : _("Lock"));
                toggle.valign = Align.CENTER;
                toggle.sensitive = holder == null || SharedProject.is_mine (holder);
                toggle.clicked.connect (() => {
                    try {
                        if (holder != null && SharedProject.is_mine (holder)) SharedProject.release (origin, seq.id);
                        else SharedProject.acquire (origin, seq.id);
                    } catch (Error e) {
                        w.say (e.message);
                    }
                    SharedProject.refresh_locks (ctl.project, origin);
                    rebuild ();
                });
                row.add_suffix (toggle);
                lock_group.add_row (row);
            }
        }
    }
}
