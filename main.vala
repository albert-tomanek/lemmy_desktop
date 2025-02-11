namespace LemmyDesktop
{
	public class App : Gtk.Application {
		public App () {
			Object(
				application_id: "com.github.albert-tomanek.lemmy-desktop",
				flags: ApplicationFlags.HANDLES_OPEN
			);
		}

		protected override void activate () {
			this.set_menubar((new Gtk.Builder.from_resource("/com/github/albert-tomanek/lemmy-desktop/appmenu.ui")).get_object("app_menu") as GLib.MenuModel);

			var win = new MainWindow();
			this.add_window(win);
			win.show();
		}

		public static int main(string[] args)
		{
			var app = new App();
			return app.run(args);
		}

	}

	[GtkTemplate (ui = "/com/github/albert-tomanek/lemmy-desktop/main.ui")]
	class MainWindow : Gtk.ApplicationWindow
	{
		/* UI */
		[GtkChild] unowned Gtk.Paned paned1;
		[GtkChild] unowned Gtk.Paned paned2;

		[GtkChild] unowned Gtk.ColumnView posts_list;
		//  [GtkChild] unowned GLib.MenuModel app_menu;

		construct {
			{
				this.add_action_entries({
					{"settings", () => {
						var sett = new SettingsWindow() { modal = true, transient_for = this };
						sett.show();
					}, null, null, null}
				//  	{"open", () => {
				//  		var d = new Gtk.FileChooserDialog("Open", this, Gtk.FileChooserAction.OPEN, "Cancel", Gtk.ResponseType.CANCEL, "_Open", Gtk.ResponseType.OK) {
				//  			select_multiple = false,
				//  			filter = App.ff_flyby,
				//  		};
				//  		d.show();
			
				//  		d.response.connect((r) => {
				//  			if (r == Gtk.ResponseType.OK)
				//  				this.open.begin(d.get_file(), (_, ctx) => {
				//  					this.open.end(ctx);
				//  				});
			
				//  			d.close();
				//  		});
				//  	}, null, null, null}
				}, this);
			}

			this.init_ui();

			var settings = new Settings ("com.github.albert-tomanek.lemmy-desktop");
			settings.bind("paned1-pos", this.paned1, "position", SettingsBindFlags.DEFAULT);
			settings.bind("paned2-pos", this.paned2, "position", SettingsBindFlags.DEFAULT);
		}

		void init_ui()
		{
			this.show_menubar = true;

			var gi = new GroupIter("lemmy.world", "asklemmy");
			gi.get_more_posts.begin();

			this.posts_list.model = new Gtk.SingleSelection(gi);
			this.posts_list.append_column(new Gtk.ColumnViewColumn(null, null) {
				title = "Title",
				expand = true,
				resizable = true,
				
				factory = new_signal_list_item_factory(
					(@this, li) => {
						li.child = new Gtk.Label(null) {
							halign = Gtk.Align.START,
							hexpand = true,
							ellipsize = Pango.EllipsizeMode.END
						};
					},
					null,
					(@this, li) => {
						((Gtk.Label) li.child).label = ((PostHandle) li.item).name;
					},
					null
				)
			});

			this.posts_list.append_column(new Gtk.ColumnViewColumn(null, null) {
				title = "User",
				expand = false,
				resizable = true,
				
				factory = new_signal_list_item_factory(
					(@this, li) => {
						li.child = new Gtk.Label(null) {
							halign = Gtk.Align.START,
							hexpand = true,
							ellipsize = Pango.EllipsizeMode.END
						};
					},
					null,
					(@this, li) => {
						((Gtk.Label) li.child).label = ((PostHandle) li.item).creator.name;
					},
					null
				)
			});
		}
	}

	[GtkTemplate (ui = "/com/github/albert-tomanek/lemmy-desktop/settings.ui")]
	class SettingsWindow : Gtk.Window
	{
	}
}



delegate void SignalListItemFactoryCallback(Gtk.SignalListItemFactory @this, Gtk.ListItem li);

Gtk.SignalListItemFactory new_signal_list_item_factory(
    SignalListItemFactoryCallback? setup,
    SignalListItemFactoryCallback? teardown,
    SignalListItemFactoryCallback? bind,
    SignalListItemFactoryCallback? unbind
)
{
    var f = new Gtk.SignalListItemFactory();

    if (setup    != null) f.setup.connect((t, li) => setup(f, (Gtk.ListItem) li));      // FIXME: We get passed Objects, not ListItems so this cast might be ignoring some aspect of reaity
    if (teardown != null) f.teardown.connect((t, li) => teardown(f, (Gtk.ListItem) li));
    if (bind     != null) f.bind.connect((t, li) => bind(f, (Gtk.ListItem) li));
    if (unbind   != null) f.unbind.connect((t, li) => unbind(f, (Gtk.ListItem) li));

    return f;
}
