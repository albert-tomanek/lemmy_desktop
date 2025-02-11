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
			var win = new MainWindow();
			this.add_window(win);
			win.show();

			var gi = new GroupIter("lemmy.world", "asklemmy");
			gi.get_posts.begin();
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

		construct {
			//  this.add_action_entries({
			//  	{"save-as", () => {
			//  		var d = new Gtk.FileChooserDialog("Save As", this, Gtk.FileChooserAction.SAVE, "Cancel", Gtk.ResponseType.CANCEL, "Save As", Gtk.ResponseType.OK) {
			//  			select_multiple = false,
			//  			filter = App.ff_flyby
			//  		};
			//  		d.set_current_name(".flyby");
			//  		d.show();
		
			//  		d.response.connect((r) => {
			//  			if (r == Gtk.ResponseType.OK)
			//  				this.save.begin(d.get_file(), (_, ctx) => {
			//  					this.save.end(ctx);
			//  					message("Finished saving");
			//  				});
		
			//  			d.close();
			//  		});		
			//  	}, null, null, null},
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
			//  }, this);

			var settings = new Settings ("com.github.albert-tomanek.lemmy-desktop");
			settings.bind("paned1-pos", this.paned1, "position", SettingsBindFlags.DEFAULT);
			settings.bind("paned2-pos", this.paned2, "position", SettingsBindFlags.DEFAULT);
		}
	}
}