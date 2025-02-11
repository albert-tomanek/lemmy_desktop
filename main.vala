namespace Lemmy.Desktop
{
	using API;

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
		[GtkChild] unowned Gtk.ListView comms_list;
		[GtkChild] unowned Gtk.SingleSelection comm_selection;

		public API.Session? sess { get; set; default = null; }

		// Stuff obtained from the current account through the API
		ListStore u_subscribed = new ListStore(typeof(Handles.Community));

		construct {
			this.add_action_entries({
				{"settings", () => {
					var sett = new SettingsWindow() { modal = true, transient_for = this };
					sett.show();
				}, null, null, null},
				{"login", () => {
					var dlg = new LoginDialog() { modal = true, transient_for = this };
					dlg.show();

					dlg.response.connect(rc => {
						if (rc == Gtk.ResponseType.OK)
						{
							API.Session.login.begin(dlg.inst_entry.text, dlg.acc_entry.text, dlg.pass_entry.text, (_, ctx) => {
								try {
									this.sess = API.Session.login.end(ctx);
									dlg.close();
								}
								catch (Error err)
								{
									var d2 = new Gtk.MessageDialog(dlg, Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, null) {
										text = "Login failed",
										secondary_text = err.message,
									};
									d2.response.connect(_ => d2.close());
									d2.show();
								}
							});
						}
					});
				}, null, null, null}
			}, this);

			this.init_ui();
			notify["sess"].connect(on_account_changed);

			var settings = new Settings ("com.github.albert-tomanek.lemmy-desktop");
			settings.bind("paned1-pos", this.paned1, "position", SettingsBindFlags.DEFAULT);
			settings.bind("paned2-pos", this.paned2, "position", SettingsBindFlags.DEFAULT);
		}

		void init_ui()
		{
			this.show_menubar = true;

			// posts_list

			this.posts_list.model = new Gtk.SingleSelection(null);
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
						((Gtk.Label) li.child).label = ((Handles.Post) li.item).name;
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
						((Gtk.Label) li.child).label = ((Handles.Post) li.item).creator.name;
					},
					null
				)
			});

			// comms_list

			this.comm_selection.model = this.u_subscribed;
			this.comm_selection.notify["selected-item"].connect(() => {
				var grp = this.comm_selection.selected_item as Handles.Community;

				var gi = new GroupIter(sess, grp.instance, grp.name);
				gi.get_more_posts.begin();
	
				(this.posts_list.model as Gtk.SingleSelection).model = gi;
			});

			this.comms_list.factory = new_signal_list_item_factory(
				(@this, li) => {
					li.child = new CommunityListRow();
				},
				null,
				(@this, li) => {
					var comm = ((Handles.Community) li.item);
					var row  = ((CommunityListRow) li.child);

					row.name.label = comm.title;
					row.tooltip_text = (comm.description != null) ? (comm.description.length <= 300) ? comm.description : null : null;
					row.set_icon.begin(comm.icon);
				},
				null
			);
		}

		class CommunityListRow : Gtk.Box
		{
			public Gtk.Label name = new Gtk.Label(null) {
				halign = Gtk.Align.START,
				hexpand = true,
				ellipsize = Pango.EllipsizeMode.END
			};
			public Gtk.Image icon = new Gtk.Image() {
				width_request = 16,
				height_request = 16
			};

			construct {
				orientation = Gtk.Orientation.HORIZONTAL;
				spacing = 4;

				this.append(icon);
				this.append(name);
			}

			public async void set_icon(string? url)
			{
				if (url != null)
				{
					this.icon.opacity = 1.0;

					var bytes = yield (new Soup.Session()).send_and_read_async(new Soup.Message ("GET", url), 0, null);	
					this.icon.gicon = new GLib.BytesIcon(bytes);
				}
				else
					this.icon.opacity = 0.0;
			}
		}

		void on_account_changed()
		{
			stdout.printf("on_account_changed\n");
			this.u_subscribed.remove_all();
			sess.get_subscribed.begin(this.u_subscribed);
		}
	}

	[GtkTemplate (ui = "/com/github/albert-tomanek/lemmy-desktop/settings.ui")]
	class SettingsWindow : Gtk.Window
	{
	}

	[GtkTemplate (ui = "/com/github/albert-tomanek/lemmy-desktop/login_dialog.ui")]
	class LoginDialog : Gtk.Dialog
	{
		[GtkChild] public unowned Gtk.Entry inst_entry;
		[GtkChild] public unowned Gtk.Entry acc_entry;
		[GtkChild] public unowned Gtk.PasswordEntry pass_entry;
		[GtkChild] unowned Gtk.Button cancel_button;
		[GtkChild] unowned Gtk.Button login_button;

		construct {
			//  add_button("_Cancel", Gtk.ResponseType.CANCEL);
			//  login_button = add_button("_Login", Gtk.ResponseType.OK) as Gtk.Button;
			//  login_button.add_css_class("suggested-action");

			cancel_button.clicked.connect(() => this.close());
			login_button.clicked.connect(() => this.response(Gtk.ResponseType.OK));

			inst_entry.notify["text"].connect(update_sensitive);
			acc_entry.notify["text"].connect(update_sensitive);
			update_sensitive();
		}

		void update_sensitive()
		{
			login_button.sensitive = (inst_entry.text != "" && acc_entry.text != "");
		}
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
