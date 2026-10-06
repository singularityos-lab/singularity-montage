namespace Singularity.Apps.Montage {
    namespace NativeFormat {
        public const string EXTENSION = ".montage";

        public void save (Project p, File file) throws Error {
            var zip = new ZipArchive ();
            zip.add_text ("mimetype", "application/x-montage-project", false);
            zip.add_text ("project.json", p.serialize (true));
            foreach (var s in p.sequences) zip.add_text ("timelines/%s.otio".printf (safe (s.name, s.id)), Otio.write (p, s));
            zip.add_text ("README.txt", "Montage project.\nproject.json is the full project in JSON.\ntimelines/ holds every sequence as OpenTimelineIO, readable by other editors.\n");
            var tmp = file.get_parent ().get_child (".%s.part".printf (file.get_basename ()));
            zip.save (tmp);
            tmp.move (file, FileCopyFlags.OVERWRITE);
        }

        string safe (string name, string id) {
            var sb = new StringBuilder ();
            foreach (char c in name.to_utf8 ()) sb.append_c (c.isalnum () || c == '-' || c == '_' ? c : '_');
            return sb.len > 0 ? sb.str + "-" + id : id;
        }

        public Project load (File file) throws Error {
            uint8[] head;
            var stream = file.read ();
            head = new uint8[2];
            size_t n;
            stream.read_all (head, out n);
            stream.close ();
            if (n == 2 && head[0] == 'P' && head[1] == 'K') {
                var zip = ZipArchive.read (file);
                var text = zip.text ("project.json");
                if (text != null) return Project.parse (text);
                foreach (var name in zip.names ()) {
                    if (name.has_suffix (".otio")) return Otio.read (zip.text (name), file);
                }
                throw new IOError.INVALID_DATA (_("The project archive has no timeline."));
            }
            uint8[] data;
            file.load_contents (null, out data, null);
            var root = Js.parse ((string) data);
            if (LegacyFormat.detect (root)) return LegacyFormat.read (root);
            return Project.parse ((string) data);
        }
    }

    public class Session : Object {
        public Project project;
        public File? origin { get; private set; }
        public bool modified { get; private set; }
        public string id = new_id ();
        int saved_revision;
        uint pending;
        File recovery;
        File lock_file;
        public int versions = 5;

        public Session (Project project) {
            this.project = project;
            var dir = recovery_dir ();
            DirUtils.create_with_parents (dir.get_path (), 0700);
            recovery = dir.get_child (id + ".montage");
            lock_file = dir.get_child (id + ".lock");
            try {
                FileUtils.set_contents (lock_file.get_path (), "%d".printf ((int) Posix.getpid ()));
            } catch (Error e) {
            }
            project.changed.connect (() => {
                modified = project.revision != saved_revision;
                schedule ();
            });
        }

        public static File recovery_dir () {
            return File.new_for_path (Path.build_filename (Environment.get_user_state_dir (), "singularity-montage", "recovery"));
        }

        void schedule () {
            if (pending != 0) Source.remove (pending);
            pending = Timeout.add (800, () => {
                pending = 0;
                write_recovery ();
                return Source.REMOVE;
            });
        }

        public void write_recovery () {
            if (!modified) {
                try { if (recovery.query_exists ()) recovery.delete (); } catch (Error e) { }
                return;
            }
            try {
                var b = new Json.Builder ();
                b.begin_object ();
                Js.s (b, "origin", origin != null ? origin.get_uri () : "");
                Js.i (b, "time", new DateTime.now_utc ().to_unix ());
                b.end_object ();
                var zip = new ZipArchive ();
                zip.add_text ("project.json", project.serialize ());
                zip.add_text ("recovery.json", Js.write (b.get_root ()));
                var tmp = recovery.get_parent ().get_child (id + ".part");
                zip.save (tmp);
                tmp.move (recovery, FileCopyFlags.OVERWRITE);
            } catch (Error e) {
                warning ("recovery: %s", e.message);
            }
        }

        public void flush () {
            if (pending != 0) {
                Source.remove (pending);
                pending = 0;
                write_recovery ();
            }
        }

        public void opened (File? file) {
            origin = file;
            saved_revision = project.revision;
            modified = false;
        }

        public void save (File file) throws Error {
            if (file.query_exists () && versions > 0) keep_version (file);
            NativeFormat.save (project, file);
            origin = file;
            saved_revision = project.revision;
            modified = false;
            write_recovery ();
        }

        void keep_version (File file) {
            try {
                var dir = file.get_parent ().get_child ("Montage Auto-Save");
                if (!dir.query_exists ()) dir.make_directory ();
                string stamp = new DateTime.now_local ().format ("%Y-%m-%d_%H-%M-%S");
                file.copy (dir.get_child ("%s.%s.montage".printf ((file.get_basename () ?? "project").replace (".montage", ""), stamp)), FileCopyFlags.OVERWRITE);
                var list = new Gee.ArrayList<string> ();
                var e = dir.enumerate_children ("standard::name", FileQueryInfoFlags.NONE);
                FileInfo? info;
                string prefix = (file.get_basename () ?? "project").replace (".montage", "") + ".";
                while ((info = e.next_file ()) != null) if (info.get_name ().has_prefix (prefix)) list.add (info.get_name ());
                list.sort ();
                for (int i = 0; i < list.size - versions; i++) dir.get_child (list[i]).delete ();
            } catch (Error e) {
                warning ("auto-save version: %s", e.message);
            }
        }

        public void close () {
            if (pending != 0) Source.remove (pending);
            pending = 0;
            try {
                if (recovery.query_exists ()) recovery.delete ();
                if (lock_file.query_exists ()) lock_file.delete ();
            } catch (Error e) {
            }
        }

        public void discard_recovery () {
            modified = false;
            saved_revision = project.revision;
            try { if (recovery.query_exists ()) recovery.delete (); } catch (Error e) { }
        }

        public class Recoverable : Object {
            public File file;
            public string origin;
            public int64 time;
            public string name;
        }

        public static Gee.ArrayList<Recoverable> orphans () {
            var r = new Gee.ArrayList<Recoverable> ();
            var dir = recovery_dir ();
            try {
                var e = dir.enumerate_children ("standard::name", FileQueryInfoFlags.NONE);
                FileInfo? info;
                while ((info = e.next_file ()) != null) {
                    string name = info.get_name ();
                    if (!name.has_suffix (".montage")) continue;
                    string sid = name.substring (0, name.length - 8);
                    var lockf = dir.get_child (sid + ".lock");
                    if (lockf.query_exists ()) {
                        string pid_text;
                        FileUtils.get_contents (lockf.get_path (), out pid_text);
                        int pid = int.parse (pid_text);
                        if (pid > 0 && FileUtils.test ("/proc/%d".printf (pid), FileTest.EXISTS)) continue;
                    }
                    try {
                        var zip = ZipArchive.read (dir.get_child (name));
                        var meta = Js.parse (zip.text ("recovery.json") ?? "{}");
                        var rec = new Recoverable ();
                        rec.file = dir.get_child (name);
                        rec.origin = Js.str (meta, "origin");
                        rec.time = Js.integer (meta, "time");
                        rec.name = rec.origin != "" ? (File.new_for_uri (rec.origin).get_basename () ?? _("Untitled")) : _("Untitled");
                        r.add (rec);
                    } catch (Error err) {
                        warning ("recovery %s: %s", name, err.message);
                    }
                }
            } catch (Error e) {
            }
            return r;
        }

        public Project recover (Recoverable rec) throws Error {
            var zip = ZipArchive.read (rec.file);
            var p = Project.parse (zip.text ("project.json"));
            origin = rec.origin != "" ? File.new_for_uri (rec.origin) : null;
            rec.file.delete ();
            var sid = (rec.file.get_basename () ?? "").replace (".montage", "");
            var lockf = recovery_dir ().get_child (sid + ".lock");
            if (lockf.query_exists ()) lockf.delete ();
            return p;
        }

        public void mark_modified () {
            saved_revision = -1;
            modified = true;
            schedule ();
        }
    }
}
