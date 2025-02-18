project('flyby', ['vala', 'c'])
gnome = import('gnome')

resources = gnome.compile_resources(
   'flyby_res', 'resource.xml',
    source_dir: '.',
	export: true,
)

executable('lemmy_desktop',
	resources,
	sources: [
		'main.vala',
		'api.vala'
	],
	dependencies: [
		dependency('glib-2.0'),
		dependency('gobject-2.0'),
		dependency('gtk4'),
		dependency('libsoup-3.0'),
		dependency('json-glib-1.0'),
		dependency('webkitgtk-6.0'),
	],
	install: true
)

install_data('com.github.alberttomanek.lemmy-desktop.gschema.xml', install_dir : get_option('datadir') / 'glib-2.0' / 'schemas')
gnome.post_install(
	glib_compile_schemas: true
)