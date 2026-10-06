project('singularity-montage', ['vala', 'c'],
  version: '0.2.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-montage"', language: 'c')
add_project_arguments('-w', language: 'c')
subdir('po')

cc = meson.get_compiler('c')
gtk_dep = dependency('gtk4')
gee_dep = dependency('gee-0.8')
gio_dep = dependency('gio-2.0')
gio_unix_dep = dependency('gio-unix-2.0')
json_dep = dependency('json-glib-1.0')
zlib_dep = dependency('zlib')
cairo_dep = dependency('cairo')
pango_dep = dependency('pangocairo')
pixbuf_dep = dependency('gdk-pixbuf-2.0')
xml_dep = dependency('libxml-2.0')
gst_dep = dependency('gstreamer-1.0')
gst_app_dep = dependency('gstreamer-app-1.0')
gst_video_dep = dependency('gstreamer-video-1.0')
gst_audio_dep = dependency('gstreamer-audio-1.0')
gst_pbutils_dep = dependency('gstreamer-pbutils-1.0')
gst_tag_dep = dependency('gstreamer-tag-1.0')
math_dep = cc.find_library('m')

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

core_deps = [gtk_dep, gee_dep, gio_dep, json_dep, zlib_dep, cairo_dep, pango_dep, pixbuf_dep, xml_dep,
  gst_dep, gst_app_dep, gst_video_dep, gst_audio_dep, gst_pbutils_dep, gst_tag_dep, math_dep, libsingularity_dep]
core_args = ['--pkg', 'zlib', '--pkg', 'posix', '--vapidir', meson.current_source_dir() / 'vapi']
core_args += ['--pkg', 'montage-pack']
core_c = files('src/engine/master_pack.c')

core = files(
  'src/model/json_util.vala',
  'src/model/model.vala',
  'src/model/project.vala',
  'src/model/edits.vala',
  'src/engine/probe.vala',
  'src/engine/decoder.vala',
  'src/engine/color.vala',
  'src/engine/catalog.vala',
  'src/engine/video_fx.vala',
  'src/engine/compose.vala',
  'src/engine/titles.vala',
  'src/engine/composition.vala',
  'src/engine/subtitles.vala',
  'src/engine/frame_cache.vala',
  'src/engine/renderer.vala',
  'src/engine/mixer.vala',
  'src/engine/master.vala',
  'src/engine/export.vala',
  'src/io/zip.vala',
  'src/io/image_writers.vala',
  'src/io/mp4_chapters.vala',
  'src/io/native.vala',
  'src/io/otio.vala',
  'src/io/interchange.vala',
  'src/io/premiere.vala',
  'src/io/aaf.vala',
  'src/io/legacy.vala',
  'src/io/review.vala',
  'src/engine/media_cache.vala',
  'src/engine/background.vala',
  'src/engine/analysis.vala',
  'src/engine/transcribe.vala',
)

ui = files(
  'src/ui/app.vala',
  'src/ui/style.vala',
  'src/ui/keymap.vala',
  'src/ui/playback.vala',
  'src/ui/viewer.vala',
  'src/ui/controller.vala',
  'src/ui/timeline_view.vala',
  'src/ui/media_panel.vala',
  'src/ui/inspector.vala',
  'src/ui/ops.vala',
  'src/ui/window.vala',
  'src/ui/edit_ribbon.vala',
  'src/ui/actions.vala',
  'src/ui/window_actions.vala',
  'src/ui/features.vala',
  'src/ui/export_dialog.vala',
  'src/ui/scopes.vala',
  'src/ui/color_panel.vala',
  'src/ui/mixer_panel.vala',
  'src/ui/captions_panel.vala',
  'src/ui/review_panel.vala',
  'src/ui/misc.vala',
  'src/ui/media_ops.vala',
  'src/ui/test_script.vala',
  'src/ui/wave_roundtrip.vala',
)

core_lib = static_library('montage-core',
  core + core_c,
  dependencies: core_deps,
  vala_args: core_args,
  include_directories: include_directories('src/engine'),
)
core_dep = declare_dependency(link_with: core_lib, dependencies: core_deps, include_directories: include_directories('src/engine'))

test_env = ['TMPDIR=' + meson.current_build_dir(), 'LC_ALL=C.UTF-8', 'MONTAGE_TEST_OUT=' + meson.current_build_dir() / 'test-out', 'GSETTINGS_BACKEND=memory', 'MONTAGE_FIXTURES=' + meson.current_source_dir() / 'tests' / 'fixtures']

foreach t : ['model', 'engine', 'export', 'aaf']
  exe = executable('montage-' + t + '-test',
    files('tests/harness.vala', 'tests/' + t + '_test.vala'),
    dependencies: [core_dep],
    vala_args: core_args,
  )
  test('montage-' + t, exe, env: test_env, timeout: 600, is_parallel: false)
endforeach

interchange_test = executable('montage-interchange-test',
  files('tests/harness.vala', 'tests/interchange_test.vala'),
  dependencies: [core_dep],
  vala_args: core_args,
)
test('montage-interchange', interchange_test, env: test_env + ['MONTAGE_FIXTURES=' + meson.current_source_dir() / 'tests' / 'fixtures'], timeout: 300)

features_test = executable('montage-features-test',
  files('tests/harness.vala', 'tests/features_test.vala'),
  dependencies: [core_dep],
  vala_args: core_args,
)
keyframe_sample = meson.current_source_dir() / 'tests' / 'fixtures' / 'intro.keyframe'
keyframe_gst = meson.global_build_root() / 'subprojects' / 'singularity-keyframe' / 'src' / 'cli' / 'gst'
test('montage-features', features_test, env: test_env + ['MONTAGE_KEYFRAME_SAMPLE=' + keyframe_sample, 'GST_PLUGIN_PATH=' + keyframe_gst], timeout: 900, is_parallel: false)

executable('singularity-montage',
  ui,
  dependencies: [core_dep, gio_unix_dep],
  vala_args: core_args,
  install: true,
)

install_data('data/dev.sinty.montage.desktop',
  install_dir: get_option('datadir') / 'applications'
)
install_data('data/icons/dev.sinty.montage.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)
install_data('data/dev.sinty.montage.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)
install_data('data/dev.sinty.montage.json',
  install_dir: get_option('datadir') / 'singularity' / 'app-settings'
)
install_data('data/dev.sinty.montage.metainfo.xml',
  install_dir: get_option('datadir') / 'metainfo'
)
install_data('data/dev.sinty.montage.xml',
  install_dir: get_option('datadir') / 'mime' / 'packages'
)
install_data('data/dev.sinty.montage.open.ini',
  install_dir: get_option('datadir') / 'singularity' / 'files-actions'
)
install_data('data/dev.sinty.montage.quick.ini',
  install_dir: get_option('datadir') / 'singularity' / 'files-actions'
)
