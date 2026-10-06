using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Montage {
    public class MediaBin : AppSidebar {
        Controller ctl;
        Box sequences = new Box (Orientation.VERTICAL, 2);
        Box bins = new Box (Orientation.VERTICAL, 2);
        Box labels = new Box (Orientation.VERTICAL, 2);
        Box items = new Box (Orientation.VERTICAL, 2);
        Box empty_box = new Box (Orientation.VERTICAL, 0);
        SidebarSectionLabel media_label;
        uint thumb_refresh;
        SearchBubble search;
        string query = "";
        int label_filter;
        string current_bin = "*";
        public string? selected_media;
        public signal void media_activated (MediaItem m);
        public signal void request_import ();
        static string[] LABEL_NAMES;

        public MediaBin (Controller ctl) {
            base (280);
            this.ctl = ctl;
            add_css_class ("sx-media-bin");
            LABEL_NAMES = { _("Any Label"), _("Red"), _("Orange"), _("Yellow"), _("Green"), _("Violet"), _("Cyan"), _("Pink") };
            add_bubble_icon ("list-add-symbolic", _("Import Media"), () => request_import ());
            add_bubble_icon ("folder-new-symbolic", _("New Bin"), () => add_bin ());
            search = add_bubble_search (_("Search Media (Ctrl+F)"), (text) => {
                query = text;
                rebuild_items ();
            });
            box.append (new SidebarSectionLabel (_("Sequences")));
            box.append (sequences);
            box.append (bins);
            box.append (labels);
            media_label = new SidebarSectionLabel (_("Media"));
            box.append (media_label);
            box.append (items);
            empty_box.margin_top = 8;
            box.append (empty_box);
            ctl.media_cache.ready.connect (() => {
                if (thumb_refresh != 0) return;
                thumb_refresh = Timeout.add (400, () => {
                    thumb_refresh = 0;
                    rebuild_items ();
                    return Source.REMOVE;
                });
            });
            ctl.project.changed.connect (rebuild);
            ctl.project.media_changed.connect (rebuild);
            ctl.proxies.progress.connect ((id, f) => {
                if (f >= 0.999 || ((int) (f * 100)) % 5 == 0) rebuild_items ();
            });
            rebuild ();
        }

        public void focus_search () {
            search.grab_focus_entry ();
        }

        void add_bin () {
            ctl.project.checkpoint (_("New Bin"));
            var b = new Bin (_("Bin %d").printf (ctl.project.bins.size + 1));
            ctl.project.bins.add (b);
            current_bin = b.id;
            ctl.project.commit ();
        }

        void clear (Box box) {
            Widget? c;
            while ((c = box.get_first_child ()) != null) box.remove (c);
        }

        SidebarRow bin_row (string icon, string name, string id) {
            var row = new SidebarRow (icon, name);
            row.set_active (current_bin == id);
            row.clicked.connect (() => {
                current_bin = id;
                rebuild ();
            });
            return row;
        }

        public void rebuild () {
            clear (sequences);
            foreach (var s in ctl.project.sequences) {
                var seq = s;
                var row = new SidebarRow ("video-display-symbolic", seq.name);
                row.set_active (seq.id == ctl.project.active);
                var info = new Label ("%d × %d".printf (seq.width, seq.height));
                info.add_css_class ("dim-label");
                info.add_css_class ("caption");
                info.add_css_class ("numeric");
                ((Box) row.child).append (info);
                row.tooltip_text = _("Open %s in the timeline").printf (seq.name);
                row.clicked.connect (() => {
                    if (ctl.project.active == seq.id) return;
                    ctl.project.active = seq.id;
                    ctl.selection.clear ();
                    ctl.project.commit ();
                });
                var source = new DragSource ();
                source.actions = Gdk.DragAction.COPY;
                source.prepare.connect ((x, y) => new Gdk.ContentProvider.for_value ("sequence:" + seq.id));
                row.add_controller (source);
                sequences.append (row);
            }
            clear (bins);
            if (ctl.project.bins.size > 0) {
                bins.append (new SidebarSectionLabel (_("Bins")));
                bins.append (bin_row ("view-grid-symbolic", _("All Media"), "*"));
                bins.append (bin_row ("folder-symbolic", _("Unsorted"), ""));
                foreach (var b in ctl.project.bins) {
                    var bin = b;
                    var row = bin_row ("folder-symbolic", bin.name, bin.id);
                    var drop = new DropTarget (typeof (string), Gdk.DragAction.COPY);
                    drop.drop.connect ((value, x, y) => {
                        var m = ctl.project.find_media (value.get_string ());
                        if (m == null) return false;
                        ctl.project.checkpoint (_("Move to Bin"));
                        m.bin = bin.id;
                        ctl.project.commit ();
                        return true;
                    });
                    row.add_controller (drop);
                    bins.append (row);
                }
            } else {
                current_bin = "*";
            }
            clear (labels);
            var used = new Gee.HashSet<int> ();
            foreach (var m in ctl.project.media) if (m.label > 0) used.add (m.label);
            if (!used.contains (label_filter)) label_filter = 0;
            if (used.size > 0) {
                labels.append (new SidebarSectionLabel (_("Labels")));
                for (int i = 1; i < LABEL_NAMES.length; i++) if (used.contains (i)) labels.append (label_row (i));
            }
            rebuild_items ();
        }

        Widget label_row (int label) {
            var row = new Button ();
            row.has_frame = false;
            row.add_css_class ("flat");
            row.add_css_class ("singularity-sidebar-row");
            if (label == label_filter) row.add_css_class ("sidebar-nav-active");
            var box = new Box (Orientation.HORIZONTAL, 12);
            box.append (label_dot (label));
            var name = new Label (LABEL_NAMES[label]);
            name.xalign = 0;
            name.hexpand = true;
            box.append (name);
            row.child = box;
            row.tooltip_text = _("Show only media with the %s label").printf (LABEL_NAMES[label]);
            row.clicked.connect (() => {
                label_filter = label_filter == label ? 0 : label;
                rebuild ();
            });
            return row;
        }

        Widget label_dot (int label) {
            var dot = new DrawingArea ();
            dot.set_size_request (16, 16);
            dot.valign = Align.CENTER;
            string hex = label_color (label);
            dot.set_draw_func ((a, cr, w, h) => {
                var c = Gdk.RGBA ();
                c.parse (hex);
                cr.set_source_rgba (c.red, c.green, c.blue, 1);
                cr.arc (w / 2.0, h / 2.0, 5, 0, 2 * Math.PI);
                cr.fill ();
            });
            return dot;
        }

        string label_color (int label) {
            string[] colors = { "", "#bf616a", "#d08770", "#ebcb8b", "#a3be8c", "#b48ead", "#88c0d0", "#e5739f" };
            return colors[label.clamp (0, 7)];
        }

        Widget thumbnail (MediaItem m) {
            var frame = new Box (Orientation.HORIZONTAL, 0);
            frame.overflow = Overflow.HIDDEN;
            frame.set_size_request (56, 32);
            frame.valign = Align.CENTER;
            Gdk.Pixbuf? pix = null;
            if (m.has_video && m.kind != "multicam") pix = ctl.media_cache.get_thumb (m.uri, m.mark_in > 0 ? m.mark_in : 0);
            if (pix != null) {
                frame.add_css_class ("montage-thumb");
                int tw = 56, th = 32;
                double scale = double.max ((double) tw / pix.width, (double) th / pix.height);
                var fitted = new Gdk.Pixbuf (Gdk.Colorspace.RGB, pix.has_alpha, 8, tw, th);
                pix.scale (fitted, 0, 0, tw, th, (tw - pix.width * scale) / 2, (th - pix.height * scale) / 2, scale, scale, Gdk.InterpType.BILINEAR);
                var picture = new Picture.for_paintable (Gdk.Texture.for_pixbuf (fitted));
                picture.can_shrink = true;
                picture.set_size_request (56, 32);
                picture.content_fit = ContentFit.COVER;
                frame.append (picture);
            } else {
                string icon = m.has_video || m.kind == "multicam" ? "video-x-generic" : (m.still ? "image-x-generic" : "audio-x-generic");
                var image = new Image.from_icon_name (icon);
                image.pixel_size = 32;
                image.margin_start = 12;
                frame.append (image);
            }
            return frame;
        }

        Widget media_row (MediaItem m) {
            var row = new Button ();
            row.has_frame = false;
            row.add_css_class ("flat");
            row.add_css_class ("singularity-sidebar-row");
            row.add_css_class ("montage-media-row");
            if (m.id == selected_media) row.add_css_class ("sidebar-nav-active");
            var box = new Box (Orientation.HORIZONTAL, 10);
            box.append (thumbnail (m));
            var labels = new Box (Orientation.VERTICAL, 1);
            labels.hexpand = true;
            labels.valign = Align.CENTER;
            var name = new Label (m.name);
            name.xalign = 0;
            name.ellipsize = Pango.EllipsizeMode.MIDDLE;
            labels.append (name);
            string info = m.still ? _("Picture") : Tc.clock (m.duration);
            if (m.kind == "multicam") info = _("Multicamera, %d angles").printf (m.angles.size);
            if (m.proxy_state == "ready") info += ", " + _("Proxy");
            else if (m.proxy_state == "running" || m.proxy_state == "queued") info += ", " + _("Making proxy");
            if (m.offline) info += ", " + _("Offline");
            var sub = new Label (info);
            sub.xalign = 0;
            sub.ellipsize = Pango.EllipsizeMode.END;
            sub.add_css_class ("caption");
            sub.add_css_class ("dim-label");
            sub.add_css_class ("numeric");
            labels.append (sub);
            box.append (labels);
            if (m.label > 0) box.append (label_dot (m.label));
            row.child = box;
            row.tooltip_text = m.name;
            string id = m.id;
            row.clicked.connect (() => {
                var item = ctl.project.find_media (id);
                if (item == null) return;
                selected_media = id;
                for (var c = items.get_first_child (); c != null; c = c.get_next_sibling ()) {
                    if (c.get_data<string> ("media-id") == id) c.add_css_class ("sidebar-nav-active");
                    else c.remove_css_class ("sidebar-nav-active");
                }
                media_activated (item);
            });
            row.set_data<string> ("media-id", id);
            var source = new DragSource ();
            source.actions = Gdk.DragAction.COPY;
            source.prepare.connect ((x, y) => new Gdk.ContentProvider.for_value (id));
            row.add_controller (source);
            return row;
        }

        public void rebuild_items () {
            clear (items);
            clear (empty_box);
            var list = ctl.project.search (query, current_bin, label_filter);
            media_label.visible = list.size > 0;
            if (list.size == 0) {
                if (ctl.project.media.size == 0) empty_box.append (import_page ());
                else empty_box.append (no_results ());
                return;
            }
            foreach (var m in list) items.append (media_row (m));
        }

        Widget import_page () {
            var page = new WelcomePage ();
            page.is_section = true;
            page.compact = true;
            page.embedded = true;
            page.vexpand = false;
            page.valign = Align.START;
            page.app_icon_name = "folder-videos";
            page.title = _("No Media");
            page.subtitle = _("Bring in the clips, music and pictures for this project.");
            page.add_action ("video-x-generic", _("Import Media"), _("Video, audio, pictures"), () => request_import ());
            page.add_action ("folder", _("Import Folder"), _("All files in a folder"), () => activate_action ("win.import-folder", null));
            page.add_action ("media-removable", _("From a Camera"), _("Copy from a card"), () => activate_action ("win.import-card", null));
            return page;
        }

        Widget no_results () {
            var page = new StatusPage ();
            page.compact = true;
            page.icon_name = "edit-find";
            page.title = _("No Results");
            page.description = label_filter > 0 && query == "" ? _("No media has the %s label.").printf (LABEL_NAMES[label_filter]) : _("No media matches the search.");
            var clear_btn = new Button.with_label (_("Show All Media"));
            clear_btn.add_css_class ("pill");
            clear_btn.halign = Align.CENTER;
            clear_btn.clicked.connect (() => {
                label_filter = 0;
                current_bin = "*";
                rebuild ();
            });
            page.child = clear_btn;
            return page;
        }
    }
}
