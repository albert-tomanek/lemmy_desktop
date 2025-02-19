namespace Lemmy.Desktop
{
	using API;

	public class App : Gtk.Application {
		public App () {
			Object(
				application_id: "com.github.alberttomanek.lemmy-desktop"
			);
		}

		protected override void activate () {
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

	private class AccountInfo : Object
	{
		/* Locally stored info related to desplaying/fetching data from the online account */

		public string internal_id { get; private set; }

		public string inst  { get; set; }
		public string uname { get; set; }
		public string? jwt  { get; set; }

		public AccountInfo.load(string id)
		{
			Object();
			this.internal_id = id;
			bind_props();
		}

		public AccountInfo.create()
		{
			Object();
			this.internal_id = GLib.Uuid.string_random();
			bind_props();
		}

		private void bind_props()
		{
			var sett = new Settings.with_path("com.github.alberttomanek.lemmy-desktop.account", @"/com/github/alberttomanek/lemmy-desktop/accounts/$internal_id/");
			sett.bind("instance", this, "inst", SettingsBindFlags.DEFAULT);
			sett.bind("username", this, "uname", SettingsBindFlags.DEFAULT);
			sett.bind("jwt", this, "jwt", SettingsBindFlags.DEFAULT);
		}
	}

	[GtkTemplate (ui = "/com/github/alberttomanek/lemmy-desktop/main.ui")]
	class MainWindow : Gtk.ApplicationWindow
	{
		/* UI */
		[GtkChild] unowned Gtk.Paned paned1;
		[GtkChild] unowned Gtk.Paned paned2;

		[GtkChild] unowned Gtk.Box post_hole;
		PostView post_view = new PostView();

		[GtkChild] unowned Gtk.ScrolledWindow posts_scrolledwindow;
		[GtkChild] unowned Gtk.SingleSelection posts_selection;
		[GtkChild] unowned Gtk.ColumnView posts_list;

		//  [GtkChild] unowned GLib.MenuModel app_menu;
		[GtkChild] unowned Gtk.ListView comms_list;
		[GtkChild] unowned Gtk.SingleSelection comm_selection;

		// Account state
		internal string[] account_ids { get; set; }
		internal AccountInfo? account { get; set; default = null; }		// This contains info needed to log in
		internal API.Session? session { get; set; default = null; }		// This is obtained by logging in and used to communicate with the API

		// View state
		public API.Handles.Post current_post { get; set; }
		//  public Community current_comm { get; set; }

		ListStore u_subscribed = new ListStore(typeof(Handles.Community));

		construct {
			var sett = new Settings ("com.github.alberttomanek.lemmy-desktop");
			this.init_ui();

			this.bind_property("current-post", this.post_view, "post", BindingFlags.DEFAULT);
			
			sett.bind("paned1-pos", this.paned1, "position", SettingsBindFlags.DEFAULT);
			sett.bind("paned2-pos", this.paned2, "position", SettingsBindFlags.DEFAULT);
			sett.bind("account-ids", this, "account-ids", SettingsBindFlags.DEFAULT);
			
			this.init_actions();

			this.notify["account"].connect(() => {
				if (this.account == null)
				{
					this.session = null;
					return;
				}

				API.check_token.begin(this.account.inst, this.account.jwt, (_, rc) => {
					try {
						if (API.check_token.end(rc))
						{
							this.session = new API.Session(this.account.inst, this.account.uname, this.account.jwt);
						}
						else
						{
							// Ask them for their password again, just as if logging in
							this.run_login_dialog(this.account, (new_jwt, inst, uname) => {
								if (new_jwt != null)
								{
									this.session = new API.Session(this.account.inst, this.account.uname, new_jwt);
									this.account.jwt = new_jwt;
								}
								else
								{
									this.account = null;
								}
							});
						}
					}
					catch (Error err)
					{
						errbox(this, "Login error", err.message);
					}
				});
			});
			notify["session"].connect(on_new_login);

			// Initial app state
			var current_account = sett.get_string("current-account");
			this.notify["account"].connect(() => {
				sett.set_string("current-account", this.account.internal_id);
			});

			if (current_account != "")
				this.account = new AccountInfo.load(current_account);
		}

		void init_ui()
		{
			// Fill holes
			this.post_hole.append(this.post_view);

			// Menus

			this.show_menubar = true;
			var menus = new Gtk.Builder.from_resource("/com/github/alberttomanek/lemmy-desktop/appmenu.ui");
			this.notify["application"].connect(() => {
				this.application.set_menubar(menus.get_object("app_menu") as GLib.MenuModel);
			});

			var accounts_menu = menus.get_object("account_subm") as GLib.Menu;
			var acc_list = new GLib.Menu();
			accounts_menu.prepend_section(null, acc_list);

			this.notify["account"].connect(key => {	// There is no way to listen to changes in the contents of entries/. But we can listen to this.account, which changes whenever an account is added/removed from that dir.
				acc_list.remove_all();

				foreach (string internal_id in this.account_ids)
				{
					var acc = new AccountInfo.load(internal_id);

					var item = new GLib.MenuItem(@"!$(acc.uname)@$(acc.inst)", null);
					item.set_action_and_target("win.login", "s", internal_id);
					acc_list.append_item(item);
				}
			});
			this.notify_property("account");	// Just to initially populate the menu

			// posts_list

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
						var lab  = (Gtk.Label) li.child;
						var text = ((Handles.Post) li.item).name;

						lab.label = text;
						lab.tooltip_text = text;
					},
					null
				)
			});

			this.posts_list.append_column(new Gtk.ColumnViewColumn(null, null) {
				title = "User",
				expand = false,
				resizable = true,
				visible = false,
				
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

			this.posts_scrolledwindow.edge_reached.connect((pos) => {
				if (this.posts_selection.model != null)
					if (pos == Gtk.PositionType.BOTTOM)
						(this.posts_selection.model as GroupIter).get_more_posts.begin();
			});

			this.posts_selection.notify["selected-item"].connect(() => {
				this.current_post = this.posts_selection.selected_item as Handles.Post;
			});

			// comms_list

			this.comm_selection.model = this.u_subscribed;
			this.comm_selection.notify["selected-item"].connect(() => {
				var grp = this.comm_selection.selected_item as Handles.Community;

				var gi = new GroupIter(session, grp.instance, grp.name);
				gi.get_more_posts.begin((a, b) => on_more_posts_gotten(a, b, gi));
	
				posts_selection.model = gi;
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
		
		void on_more_posts_gotten(Object? _, AsyncResult async_ctx, GroupIter gi)
		{
			// This is called at the end of the async function loading posts, and it keeps calling it again until the screen is full.
			int n_loaded = gi.get_more_posts.end(async_ctx);

			stdout.printf("======== %d %d %d\n", this.posts_list.get_height(), this.posts_scrolledwindow.get_height(), n_loaded);
			if (this.posts_list.get_height() < this.posts_scrolledwindow.get_height() && n_loaded > 0)	// (The n_loaded check is to stop this loop in case the community has fewer posts than fit on the screen)
				gi.get_more_posts.begin((a, b) => on_more_posts_gotten(a, b, gi));		
		}

		void init_actions()
		{
			/* Accounts */
			var login_act = new SimpleAction.stateful("login", VariantType.STRING, new Variant.string(""));
			login_act.activate.connect(param => {
				this.account = new AccountInfo.load(param.get_string());
			});	
			this.notify["account"].connect(() => {	// Make the menu repond to changes in the account
				login_act.set_state(new Variant.string((this.account != null) ? this.account.internal_id : ""));
			});	
			this.add_action(login_act);

			this.add_action_entries({
				{"settings", () => {
					var sett = new SettingsWindow() { modal = true, transient_for = this };
					sett.show();
				}, null, null, null},	
				{"add-account", () => {
					this.run_login_dialog(null, (token, inst, uname) => {
						if (token != null)
						{
							this.account = new AccountInfo.create() {
								inst = inst,
								uname = uname
							};	

							string[] ids = this.account_ids;
							ids += this.account.internal_id;
							this.account_ids = ids;
						}	
					});	
				}, null, null, null},	
				{"remove-account", () => {
					this.account = null;

					// Filter out of array
					string[] ids = {};
					foreach (var id in this.account_ids)
						if (id != this.account.internal_id)
							ids += id;
					this.account_ids = ids;
				}, null, null, null}	
			}, this);

			/* Post */
			this.add_action_entries({
				{"copy-post-url", () => {
					if (this.current_post != null)
					{
						Gdk.Display.get_default().get_clipboard().set_text(
							this.current_post.ap_id
						);
					}
				}, null, null, null}
			}, this);
		}

		delegate void OnLoginSuccessfulCb(string? token, string inst, string uname);

		void run_login_dialog(AccountInfo? acc, OnLoginSuccessfulCb? cb)
		{
			var dlg = new LoginDialog() { modal = true, transient_for = this };
			if (acc != null)
			{
				dlg.inst_entry.text = acc.inst;
				dlg.acc_entry.text  = acc.uname;
			}
			dlg.show();
			
			bool cb_called = false;
			dlg.response.connect(rc => {
				if (rc == Gtk.ResponseType.OK)
				{
					API.login.begin(dlg.inst_entry.text, dlg.acc_entry.text, dlg.pass_entry.text, (_, ctx) => {
						try {
							var token = API.login.end(ctx);		// First give an opportunity for login errors arise

							cb(token, dlg.inst_entry.text, dlg.acc_entry.text);
							cb_called = true;

							dlg.close();
						}
						catch (Error err)
						{
							errbox(dlg, "Login failed", err.message);
						}
					});
				}
				else
				{
					if (!cb_called)
						cb(null, dlg.inst_entry.text, dlg.acc_entry.text);
				}
			});
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

		void on_new_login()
		{
			this.u_subscribed.remove_all();
			session.get_subscribed.begin(this.u_subscribed);
		}
	}

	[GtkTemplate (ui = "/com/github/alberttomanek/lemmy-desktop/settings.ui")]
	class SettingsWindow : Gtk.Window
	{
	}

	[GtkTemplate (ui = "/com/github/alberttomanek/lemmy-desktop/login_dialog.ui")]
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

	[GtkTemplate (ui = "/com/github/alberttomanek/lemmy-desktop/post_widget.ui")]
	class PostView : Gtk.Box
	{
		[GtkChild] public unowned Gtk.Notebook notebook;
		[GtkChild] public unowned Gtk.NotebookPage text_tab;
		[GtkChild] public unowned Gtk.NotebookPage media_tab;

		[GtkChild] public unowned Gtk.Label body_label;
		[GtkChild] public unowned Gtk.Box   media_hole;
		public WebKit.WebView webview = new WebKit.WebView() { hexpand = true, vexpand = true };
		internal string? media_url { get; set; }

		public API.Handles.Post post { get; set; }

		construct {
			media_hole.append(webview);

			deep_bind(
				body_label, "label",
				this, typeof(PostView), "post", typeof(API.Handles.Post), "body"
			);
			deep_bind(
				this, "media-url",
				this, typeof(PostView), "post", typeof(API.Handles.Post), "url"
			);
			notify["media-url"].connect(() => {
				if (media_url != null)
				{
					webview.load_uri(media_url);
				}
				else
				{
					webview.load_uri("about:blank");
				}
			});

			notify["post"].connect(() => {
				if (post.url != null)
					notebook.page = media_tab.position;
				else
					notebook.page = text_tab.position;
			});
		}
	}
}


unowned Gtk.ExpressionWatch deep_bind(Object tgt_obj, string tgt_prop, Object src_obj, ...)
{
	// Equivalent:
	//
	//  var post_text = new Gtk.PropertyExpression(typeof(API.Handles.Post),
	//  	new Gtk.PropertyExpression(typeof(PostView), null, "post"),
	//  "body");
	//  post_text.bind(body_label, "label", this);
	//
	//  deep_bind(
	//  	body_label, "label",
	//  	this, "post", typeof(PostView), "body", typeof(API.Handles.Post)
	//  );

	string[] props = {};
	Type[]   types = {};

	// 1. extract the va_args
	for (var l = va_list(); true;)
	{
		Type type = l.arg();
		if (type == 0) break;
		types += type;
		
		string prop = l.arg();
		props += prop;
	}

	// 2. Construct the nested expression
	Gtk.Expression? exp = null;
	for (int i = 0; i < props.length; i++)
	{
		exp = new Gtk.PropertyExpression(types[i], exp, props[i]);
	}

	if (exp != null)
		return exp.bind(tgt_obj, tgt_prop, src_obj);
	else
		return null;
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

void errbox (Gtk.Window parent, string title, string text)
{
	var d2 = new Gtk.MessageDialog(parent, Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, null) {
		text = title,
		secondary_text = text,
	};
	d2.response.connect(_ => d2.close());
	d2.show();
}