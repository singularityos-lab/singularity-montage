namespace Singularity.Apps.Montage {
    namespace Keymap {
        public string custom_file () {
            return Path.build_filename (Environment.get_user_config_dir (), "singularity-montage", "keys.json");
        }


        void put (Gee.HashMap<string, string> map, string action, string accel) {
            map[action] = accel;
        }

        public Gee.HashMap<string, string> preset (string name) {
            var m = new Gee.HashMap<string, string> ();
            put (m, "app.quit", "<Control>q");
            put (m, "app.settings", "<Control>comma");
            put (m, "win.open", "<Control>o");
            put (m, "win.save", "<Control>s");
            put (m, "win.save-as", "<Control><Shift>s");
            put (m, "win.new-project", "<Control><Alt>n");
            put (m, "win.new-sequence", "<Control>n");
            put (m, "win.import", "<Control>i");
            put (m, "win.export", "<Control>m");
            put (m, "win.print", "<Control>p");
            put (m, "win.undo", "<Control>z");
            put (m, "win.redo", "<Control><Shift>z");
            put (m, "win.close-project", "<Control>w");
            put (m, "win.play-pause", "space");
            put (m, "win.shuttle-back", "j");
            put (m, "win.shuttle-stop", "k");
            put (m, "win.shuttle-forward", "l");
            put (m, "win.frame-back", "Left");
            put (m, "win.frame-forward", "Right");
            put (m, "win.go-start", "Home");
            put (m, "win.go-end", "End");
            put (m, "win.zoom-in", "equal");
            put (m, "win.zoom-out", "minus");
            put (m, "win.zoom-fit", "backslash");
            put (m, "win.toggle-sidebar", "F9");
            put (m, "win.toggle-inspector", "F10");
            put (m, "win.shortcuts", "<Control>question");
            put (m, "win.workspace::edit", "<Alt>1");
            put (m, "win.workspace::color", "<Alt>2");
            put (m, "win.workspace::audio", "<Alt>3");
            put (m, "win.workspace::captions", "<Alt>4");
            put (m, "win.workspace::review", "<Alt>5");
            switch (name) {
                case "finalcut":
                    put (m, "win.mark-in", "i");
                    put (m, "win.mark-out", "o");
                    put (m, "win.split", "<Control>b");
                    put (m, "win.tool::razor", "b");
                    put (m, "win.tool::select", "a");
                    put (m, "win.tool::ripple", "t");
                    put (m, "win.tool::roll", "<Shift>t");
                    put (m, "win.tool::slip", "<Alt>t");
                    put (m, "win.tool::slide", "<Control>t");
                    put (m, "win.insert", "w");
                    put (m, "win.overwrite", "d");
                    put (m, "win.append", "e");
                    put (m, "win.lift", "<Shift>Delete");
                    put (m, "win.ripple-delete", "Delete");
                    put (m, "win.add-marker", "m");
                    put (m, "win.add-chapter", "<Alt>m");
                    put (m, "win.next-edit", "Down");
                    put (m, "win.previous-edit", "Up");
                    put (m, "win.snapping", "n");
                    put (m, "win.add-transition", "<Control>t");
                    break;
                case "avid":
                    put (m, "win.mark-in", "e");
                    put (m, "win.mark-out", "r");
                    put (m, "win.split", "<Control>e");
                    put (m, "win.tool::razor", "<Shift>e");
                    put (m, "win.tool::select", "<Shift>s");
                    put (m, "win.tool::ripple", "u");
                    put (m, "win.tool::roll", "<Shift>u");
                    put (m, "win.tool::slip", "<Alt>u");
                    put (m, "win.tool::slide", "<Control>u");
                    put (m, "win.insert", "v");
                    put (m, "win.overwrite", "b");
                    put (m, "win.lift-range", "z");
                    put (m, "win.extract-range", "x");
                    put (m, "win.lift", "Delete");
                    put (m, "win.ripple-delete", "<Shift>Delete");
                    put (m, "win.add-marker", "F5");
                    put (m, "win.add-chapter", "<Shift>F5");
                    put (m, "win.next-edit", "s");
                    put (m, "win.previous-edit", "a");
                    put (m, "win.snapping", "<Control>n");
                    put (m, "win.add-transition", "<Control>d");
                    break;
                default:
                    put (m, "win.mark-in", "i");
                    put (m, "win.mark-out", "o");
                    put (m, "win.split", "<Control>k");
                    put (m, "win.tool::razor", "c");
                    put (m, "win.tool::select", "v");
                    put (m, "win.tool::ripple", "b");
                    put (m, "win.tool::roll", "n");
                    put (m, "win.tool::slip", "y");
                    put (m, "win.tool::slide", "u");
                    put (m, "win.insert", "comma");
                    put (m, "win.overwrite", "period");
                    put (m, "win.lift", "Delete");
                    put (m, "win.ripple-delete", "<Shift>Delete");
                    put (m, "win.lift-range", "semicolon");
                    put (m, "win.extract-range", "apostrophe");
                    put (m, "win.ripple-trim-previous", "q");
                    put (m, "win.ripple-trim-next", "w");
                    put (m, "win.add-marker", "m");
                    put (m, "win.add-chapter", "<Shift>m");
                    put (m, "win.next-edit", "Down");
                    put (m, "win.previous-edit", "Up");
                    put (m, "win.snapping", "s");
                    put (m, "win.add-transition", "<Control>d");
                    put (m, "win.nest", "<Control><Alt>n");
                    put (m, "win.link", "<Control>l");
                    put (m, "win.speed", "<Control>r");
                    break;
            }
            return m;
        }

        public Gee.HashMap<string, string> current (MontageApp app) {
            var map = preset (app.get_str ("keymap", "montage"));
            try {
                string text;
                if (FileUtils.get_contents (custom_file (), out text)) {
                    var o = Js.parse (text);
                    foreach (var name in o.get_members ()) {
                        string accel = Js.str (o, name);
                        uint key;
                        Gdk.ModifierType mods;
                        if (accel == "") map.unset (name);
                        else if (Gtk.accelerator_parse (accel, out key, out mods)) map[name] = accel;
                    }
                }
            } catch (Error e) {
            }
            return map;
        }

        public void install (MontageApp app) {
            var map = current (app);
            foreach (var e in map.entries) app.set_accels_for_action (e.key, { e.value });
            app.set_accels_for_action ("win.redo", { map["win.redo"] ?? "<Control><Shift>z", "<Control>y" });
            if (app.settings != null) {
                app.settings.changed["keymap"].connect (() => {
                    foreach (var name in app.list_action_descriptions ()) app.set_accels_for_action (name, {});
                    var again = current (app);
                    foreach (var e in again.entries) app.set_accels_for_action (e.key, { e.value });
                });
            }
        }
    }
}
