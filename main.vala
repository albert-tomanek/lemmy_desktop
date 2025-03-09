namespace Lemmy.Desktop
{//https://lemmy.world/api/v3/federated_instances
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

		public static Soup.Session icon_session;

		static construct {
			icon_session = new Soup.Session();
			icon_session.add_feature(new Soup.Cache(null, Soup.CacheType.SHARED));
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
		[GtkChild] unowned Gtk.SearchEntry comm_search;
		[GtkChild] unowned Gtk.ListView comms_list;
		[GtkChild] unowned Gtk.SingleSelection comm_selection;

		// Account state
		internal string[] account_ids { get; set; }
		internal AccountInfo? account { get; set; default = null; }		// This contains info needed to log in
		internal API.Session? session { get; set; default = null; }		// This is obtained by logging in and used to communicate with the API

		// View state
		public API.Structs.Post current_post { get; set; }
		//  public Community current_comm { get; set; }

		ListStore u_subscribed = new ListStore(typeof(Structs.Community));

		construct {
			this.init_ui();
			
			this.bind_property("current-post", this.post_view, "post", BindingFlags.DEFAULT);
			
			var sett = new Settings ("com.github.alberttomanek.lemmy-desktop");
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
			string[] disallow = {"Title"};
			attach_column_toggle_menu(this.posts_list, disallow);

			this.posts_list.append_column(new Gtk.ColumnViewColumn(null, null) {
				title = "Title",
				expand = true,
				resizable = true,

				factory = new_signal_list_item_factory(
					(@this, li) => {
						li.child = new Gtk.Label(null) {
							halign = Gtk.Align.START,
							hexpand = true,
							ellipsize = Pango.EllipsizeMode.END,
							use_markup = true
						};
					},
					null,
					(@this, li) => {
						var lab  = (Gtk.Label) li.child;
						var post = (Structs.Post) li.item;

						lab.label = (post.post.featured_community) ? @"<b>$(post.post.name)</b>" : post.post.name;
						get_li_cell(li).tooltip_text = post.post.name;
					},
					null
				)
			});

			this.posts_list.append_column(new Gtk.ColumnViewColumn(null, null) {
				title = "Age",
				expand = false,
				resizable = false,
				visible = true,

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
						var date = ((Structs.Post) li.item).post.published_d;

						((Gtk.Label) li.child).label = age_humanized(date);
						get_li_cell(li).tooltip_text = date.format("%c");
					},
					null
				)
			});

			this.posts_list.append_column(new Gtk.ColumnViewColumn(null, null) {
				title = "User",
				expand = false,
				resizable = true,
				visible = true,

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
						((Gtk.Label) li.child).label = ((Structs.Post) li.item).creator.name;
					},
					null
				)
			});

			this.posts_scrolledwindow.edge_reached.connect((pos) => {
				if (this.posts_selection.model != null)
					if (pos == Gtk.PositionType.BOTTOM)
						(this.posts_selection.model as SubmissionIter).get_more_posts.begin();
			});

			this.posts_selection.notify["selected-item"].connect(() => {
				this.current_post = this.posts_selection.selected_item as Structs.Post;
			});

			this.posts_list.activate.connect(idx => {
				var post = this.posts_list.model.get_item(idx) as Structs.Post;
				var c = new CommentsWindow(this, this.session, post);
				c.show();
			});

			this.init_comms_list();
		}

		void on_more_posts_gotten(Object? _, AsyncResult async_ctx, SubmissionIter gi)
		{
			// This is called at the end of the async function loading posts, and it keeps calling it again until the screen is full.
			uint n_loaded = gi.get_more_posts.end(async_ctx);

			//  stdout.printf("======== %d %d %d\n", this.posts_list.get_height(), this.posts_scrolledwindow.get_height(), n_loaded);
			if (this.posts_list.get_height() < this.posts_scrolledwindow.get_height() && n_loaded > 0)	// (The n_loaded check is to stop this loop in case the community has fewer posts than fit on the screen)
				gi.get_more_posts.begin((a, b) => on_more_posts_gotten(a, b, gi));
		}

		void init_comms_list()
		{
			// https://stackoverflow.com/a/75047830/6130358

			/* User view */

			var root = new ListStore(typeof(SpecialComm));

			root.append(new SpecialComm.with_children({
				new SpecialComm() {
					name = "My posts",
					special_id = "my-posts",
				},
				new SpecialComm() {
					name = "Saved",
					special_id = "saved",
				},
				new SpecialComm() {
					name = "Subscribed",
					special_id = "subscribed",
					children = this.u_subscribed
				}
			}) {
				name = "User"
			});

			var user_view = this.comm_selection.model = new Gtk.TreeListModel(root, false, true, item => (item as SpecialComm)?.children);

			/* Search view */

			var sorter_by_instance = new Gtk.SortListModel(null, null);
			GLib.CompareDataFunc<API.Structs.Community> cmp_subs = (p, q) => q.counts.subscribers - p.counts.subscribers;
			sorter_by_instance.sorter = new Gtk.CustomSorter(cmp_subs);	// Sort whithin a secion (by subscriber count)
			//  sorter_by_instance.section_sorter = Gtk.CustomSorter(
			//  	(p, q) => (p.instance == q.instance) ? 0 : -1
			//  );

			var search_view = new Gtk.TreeListModel(sorter_by_instance, false, true, item => null);

			//

			this.comm_search.search_changed.connect(() => {
				if (this.comm_search.text == "")
					this.comm_selection.model = user_view;
				else
				{
					sorter_by_instance.model = new SubmissionIter.on_url(session, @"https://$(session.inst)/api/v3/search?type_=Communities&q=" + this.comm_search.text.replace(" ", "%20"), "$.communities[*]", typeof(API.Structs.Community)).exhaust();
					this.comm_selection.model = search_view;
				}
			});

			this.comm_selection.notify["selected-item"].connect(() => {
				Object item = ((Gtk.TreeListRow) this.comm_selection.selected_item).item;
				SubmissionIter gi;

				if (item is Structs.Community)
				{
					var grp = item as Structs.Community;
					gi = new SubmissionIter.group(session, grp.community.instance, grp.community.name);
				}
				else if (item is SpecialComm)
				{
					var sc = item as SpecialComm;

					if (sc.special_id == "subscribed")
						gi = new SubmissionIter.on_url(session, @"https://$(session.inst)/api/v3/post/list?type_=Subscribed", "$.posts[*]", typeof(API.Structs.Post));
					else if (sc.special_id == "saved")
						gi = new SubmissionIter.on_url(session, @"https://$(session.inst)/api/v3/post/list?saved_only=true", "$.posts[*]", typeof(API.Structs.Post));
					else if (sc.special_id == "my-posts")
						gi = new SubmissionIter.on_url(session, @"https://$(session.inst)/api/v3/user?username=$(session.uname)", "$.posts[*]", typeof(API.Structs.Post));
					else
						return;
				}
				else
					return;

				gi.get_more_posts.begin((a, b) => on_more_posts_gotten(a, b, gi));
				posts_selection.model = gi;
			});

			this.comms_list.factory = new_signal_list_item_factory(
				(@this, li) => {
					li.child = new Gtk.TreeExpander() {
						child = new CommListRow()
					};
					li.focusable = false;
				},
				null,
				(@this, li) => {
					//  stdout.printf("%s %s\n", li.get_type().name(), li.item.get_type().name());
					var row  = li.item as Gtk.TreeListRow;
					var expander = li.child as Gtk.TreeExpander;
					var widget = expander.child as CommListRow;

					expander.set_list_row(row);		// Binds the expander arrow to this TreeListRow

					if (row.item is Structs.Community)
					{
						var comm = row.item as Structs.Community;

						widget.name.label = comm.community.title;
						widget.tooltip_text = (comm.community.description != null) ? (comm.community.description.length <= 300) ? comm.community.description : null : null;
						widget.set_icon.begin(comm.community.icon);
					}
					else if (row.item is SpecialComm)
					{
						var spec = row.item as SpecialComm;

						widget.name.label = spec.name;
						li.selectable = (spec.special_id != null);
					}
				},
				null
			);
		}

		class SpecialComm : Object
		{
			public string  name { get; set; }
			public string? special_id { get; set; default = null; }		// If this is specified, the row itself will be selectable, whereupon it will trigger the action `display-special-comm` with this as the name argument.
			public ListModel? children { get; set; default = null; }

			public SpecialComm.with_children(SpecialComm[] items)
			requires(items.length > 0)
			{
				var list = new ListStore(items[0].get_type());

				foreach (var item in items)
					list.append(item);

				Object(children: list);
			}
		}

		class CommListRow : Gtk.Box
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
					
					var bytes = yield (App.icon_session).send_and_read_async(new Soup.Message ("GET", url), 0, null);
					this.icon.gicon = new GLib.BytesIcon(bytes);				
				}
				else
					this.icon.opacity = 0.0;
			}
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
					// Filter out of array
					string[] ids = {};
					foreach (var id in this.account_ids)
						if (id != this.account.internal_id)
							ids += id;
					this.account_ids = ids;

					this.account = null;
				}, null, null, null}
			}, this);

			/* Post */
			this.add_action_entries({
				{"copy-post-url", () => {
					if (this.current_post != null)
					{
						Gdk.Display.get_default().get_clipboard().set_text(
							this.current_post.post.ap_id
						);
					}
				}, null, null, null}
			}, this);

			/* Media */
			this.add_action_entries({
				{"copy-media-url", () => {
					if (this.post_view.post.post.url != null)
					{
						Gdk.Display.get_default().get_clipboard().set_text(
							this.post_view.post.post.url
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

		void on_new_login()
		{
			this.u_subscribed.remove_all();
			session.get_subscribed.begin(this.u_subscribed);
		}
	}

	void attach_column_toggle_menu(Gtk.ColumnView cv, [CCode (array_length = false, array_null_terminated = true)] string[] disallow)
	{
		Gtk.Widget title_row = null;
		for (var children = cv.observe_children(), i = 0; i < children.get_n_items(); i++)
		{
			title_row = (Gtk.Widget) children.get_object(i);
			if (title_row.get_type().name() == "GtkColumnViewRowWidget")
				break;
		}

		var popover2 = new Gtk.Popover() {
			child = new Gtk.ListView(null, null) {
				model = new Gtk.NoSelection(cv.get_columns()),
				factory = new_signal_list_item_factory(
					(@this, li) => {
						li.child = new Gtk.CheckButton() {
							halign = Gtk.Align.START,
							hexpand = true,
						};
					},
					null,
					(@this, li) => {
						var col = li.item as Gtk.ColumnViewColumn;
						var cb  = li.child as Gtk.CheckButton;

						cb.label = col.title;
						cb.sensitive = !GLib.strv_contains(disallow, col.title);

						cb.get_data<Binding>("binding")?.unbind();
						Binding b = col.bind_property("visible", cb, "active", BindingFlags.BIDIRECTIONAL|BindingFlags.SYNC_CREATE);
						cb.set_data<Binding>("binding", b);
					},
					null
				)
			}
		};
		popover2.set_parent(title_row);

		var rclick = new Gtk.GestureClick() {
			button = Gdk.BUTTON_SECONDARY,
			propagation_phase = Gtk.PropagationPhase.CAPTURE
		};
		rclick.pressed.connect((n, x, y) => {
			popover2.set_pointing_to(Gdk.Rectangle() { x = (int) x, y = (int) y, width = 0, height = 0 });
			popover2.popup();
		});
		title_row.add_controller(rclick);
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

		[GtkChild] public unowned Gtk.Box  text_hole;
		[GtkChild] public unowned Gtk.Box  media_hole;

		[GtkChild] public unowned Gtk.Label votes_label;

		MarkdownLabel md_label = new MarkdownLabel() { selectable = true };
		public WebKit.WebView webview = new WebKit.WebView() { hexpand = true, vexpand = true };

		public API.Structs.Post post { get; set; }

		internal string? media_url { get; set; }
		internal string body  { get; set; }
		internal string title { get; set; }
		internal int votes { get; set; }

		construct {
			media_hole.append(webview);
			text_hole.append(md_label);

			deep_bind(
				this, "media-url",
				this, typeof(PostView), "post", typeof(API.Structs.Post), "post", typeof(API.Structs.Post.PostField), "url"
			);
			notify["media-url"].connect(() => {
				if (media_url != null)
					webview.load_uri(media_url);
				else
					webview.load_uri("about:blank");
			});

			deep_bind(
				this, "votes",
				this, typeof(PostView), "post", typeof(API.Structs.Post), "counts", typeof(API.Structs.UserSubmission.Counts), "score"
			);
			notify["votes"].connect(() => {
				votes_label.label = @"$votes votes";
			});

			notify["post"].connect(() => {
				if (post.post.url != null)
					notebook.page = media_tab.position;
				else
					notebook.page = text_tab.position;
			});
			notify["post"].connect(() => {
				md_label.text = "# %s\n\n%s".printf(this.post.post.name, this.post.post.body ?? ""); 
			});
		}
	}
}
